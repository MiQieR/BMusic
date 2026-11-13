import Foundation
import Libmpv

enum MPVValue {
    case double(Double)
    case flag(Bool)
    case string(String)
    case none
}

enum MPVEvent {
    case property(name: String, value: MPVValue)
    case fileLoaded
    case startFile
    case endFile(reason: String)
    case idle
    case shutdown
    case log(level: String, message: String)
}

enum MPVError: LocalizedError {
    case createFailed
    case initializeFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .createFailed: return "无法创建 libmpv 播放核心"
        case .initializeFailed(let message): return "libmpv 初始化失败：\(message)"
        case .commandFailed(let message): return "播放命令失败：\(message)"
        }
    }
}

/// Thin libmpv wrapper. Audio-only: `vid=no`, CoreAudio output, network cache
/// on, and Bilibili CDN headers supplied per load. The app never falls back to
/// AVPlayer for music; decoding, demuxing and output are libmpv's job.
final class MPVEngine {
    private var handle: OpaquePointer?
    private let eventThread = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var stopping = false
    private var started = false
    private var skipDestroy = false

    var onEvent: ((MPVEvent) -> Void)?

    init() throws {
        guard let handle = mpv_create() else {
            throw MPVError.createFailed
        }
        self.handle = handle

        setOption("vid", "no")
        setOption("audio-display", "no")
        setOption("idle", "yes")
        setOption("keep-open", "no")
        setOption("terminal", "no")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
        setOption("osc", "no")
        setOption("ytdl", "no")
        setOption("gapless-audio", "yes")
        setOption("audio-client-name", "BMusic")
        setOption("volume-max", "100")
        setOption("cache", "yes")
        setOption("cache-secs", "120")
        setOption("demuxer-max-bytes", "128MiB")
        setOption("demuxer-readahead-secs", "45")
        setOption("audio-fallback-to-null", "no")
        setOption("msg-level", "all=warn")
        setOption("user-agent", BiliClient.userAgent)

        let result = mpv_initialize(handle)
        guard result >= 0 else {
            let message = String(cString: mpv_error_string(result))
            mpv_terminate_destroy(handle)
            self.handle = nil
            throw MPVError.initializeFailed(message)
        }

        mpv_request_log_messages(handle, "warn")
        observe("time-pos", MPV_FORMAT_DOUBLE)
        observe("duration", MPV_FORMAT_DOUBLE)
        observe("pause", MPV_FORMAT_FLAG)
        observe("core-idle", MPV_FORMAT_FLAG)
        observe("idle-active", MPV_FORMAT_FLAG)
        observe("paused-for-cache", MPV_FORMAT_FLAG)
        observe("cache-buffering-state", MPV_FORMAT_DOUBLE)
        observe("eof-reached", MPV_FORMAT_FLAG)
        observe("volume", MPV_FORMAT_DOUBLE)
        observe("mute", MPV_FORMAT_FLAG)
        observe("media-title", MPV_FORMAT_STRING)

        started = true
        let thread = Thread { [weak self] in
            self?.eventLoop()
        }
        thread.name = "app.bmusic.mpv-events"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    deinit {
        shutdown()
    }

    // MARK: - Commands

    func setGapless(_ enabled: Bool) {
        setOption("gapless-audio", enabled ? "yes" : "no")
    }

    func load(url: URL, headers: [String: String]) {
        let headerValue = headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ",")
        setPropertyString("http-header-fields", headerValue)
        command(["loadfile", url.absoluteString, "replace"])
    }

    func loadLocal(url: URL) {
        setPropertyString("http-header-fields", "")
        command(["loadfile", url.path, "replace"])
    }

    func play() {
        setFlag("pause", false)
    }

    func pause() {
        setFlag("pause", true)
    }

    func togglePause() {
        let paused = getFlag("pause")
        setFlag("pause", !paused)
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        command(["seek", String(format: "%.3f", clamped), "absolute"])
    }

    func setVolume(_ volume: Double) {
        setDouble("volume", max(0, min(100, volume * 100)))
    }

    func setMuted(_ muted: Bool) {
        setFlag("mute", muted)
    }

    func stop() {
        command(["stop"])
        setPropertyString("http-header-fields", "")
    }

    /// 进程即将退出时调用：跳过 mpv_terminate_destroy。退出时由系统回收资源，
    /// 避免销毁期间 CoreAudio 热插拔回调与释放竞态（SIGSEGV in hotplug_cb）。
    func skipDestroyOnExit() {
        skipDestroy = true
    }

    func shutdown() {
        stateLock.lock()
        if stopping {
            stateLock.unlock()
            return
        }
        stopping = true
        let wasStarted = started
        stateLock.unlock()

        guard wasStarted, let handle else { return }
        if skipDestroy {
            mpv_wakeup(handle)
            _ = eventThread.wait(timeout: .now() + 1.0)
            self.handle = nil
            started = false
            return
        }
        // 先让 mpv 核心自己卸载音频输出（同步移除 CoreAudio 监听），
        // 再销毁上下文，缩小设备事件回调的竞态窗口。
        command(["quit"])
        mpv_wakeup(handle)
        _ = eventThread.wait(timeout: .now() + 2.0)
        mpv_terminate_destroy(handle)
        self.handle = nil
        started = false
    }

    // MARK: - Properties

    func getDouble(_ name: String) -> Double {
        guard let handle else { return 0 }
        var value = Double(0)
        mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value)
        return value
    }

    func getFlag(_ name: String) -> Bool {
        guard let handle else { return false }
        var value: Int32 = 0
        mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value)
        return value != 0
    }

    func getString(_ name: String) -> String? {
        guard let handle, let raw = mpv_get_property_string(handle, name) else {
            return nil
        }
        let value = String(cString: raw)
        mpv_free(raw)
        return value
    }

    // MARK: - Event loop

    private func eventLoop() {
        while true {
            stateLock.lock()
            let shouldStop = stopping
            stateLock.unlock()
            if shouldStop { break }

            guard let handle, let raw = mpv_wait_event(handle, 0.15) else { continue }
            let event = raw.pointee
            switch event.event_id {
            case MPV_EVENT_NONE:
                continue
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event)
            case MPV_EVENT_FILE_LOADED:
                emit(.fileLoaded)
            case MPV_EVENT_START_FILE:
                emit(.startFile)
            case MPV_EVENT_END_FILE:
                var reason = "eof"
                if let data = event.data {
                    let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    if end.reason == MPV_END_FILE_REASON_ERROR {
                        reason = String(cString: mpv_error_string(end.error))
                    } else if end.reason == MPV_END_FILE_REASON_STOP {
                        reason = "stop"
                    } else if end.reason == MPV_END_FILE_REASON_QUIT {
                        reason = "quit"
                    }
                }
                emit(.endFile(reason: reason))
            case MPV_EVENT_IDLE:
                emit(.idle)
            case MPV_EVENT_SHUTDOWN:
                emit(.shutdown)
            case MPV_EVENT_LOG_MESSAGE:
                if let data = event.data {
                    let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                    let level = message.level.map { String(cString: $0) } ?? ""
                    let text = message.text.map { String(cString: $0) } ?? ""
                    emit(.log(level: level, message: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            default:
                break
            }
        }
        eventThread.signal()
    }

    private func handlePropertyChange(_ event: mpv_event) {
        guard let data = event.data else { return }
        let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
        guard let namePointer = property.name else { return }
        let name = String(cString: namePointer)

        let value: MPVValue
        switch property.format {
        case MPV_FORMAT_DOUBLE:
            if let raw = property.data {
                value = .double(raw.assumingMemoryBound(to: Double.self).pointee)
            } else {
                value = .none
            }
        case MPV_FORMAT_FLAG:
            if let raw = property.data {
                value = .flag(raw.assumingMemoryBound(to: Int32.self).pointee != 0)
            } else {
                value = .none
            }
        case MPV_FORMAT_STRING:
            value = getString(name).map(MPVValue.string) ?? .none
        default:
            value = .none
        }
        emit(.property(name: name, value: value))
    }

    private func emit(_ event: MPVEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    // MARK: - Low-level

    private func setOption(_ name: String, _ value: String) {
        guard let handle else { return }
        let result = mpv_set_option_string(handle, name, value)
        if result < 0 {
            NSLog("[BMusic] mpv option \(name) failed: \(String(cString: mpv_error_string(result)))")
        }
    }

    private func observe(_ name: String, _ format: mpv_format) {
        guard let handle else { return }
        let result = mpv_observe_property(handle, 0, name, format)
        if result < 0 {
            NSLog("[BMusic] mpv observe \(name) failed: \(String(cString: mpv_error_string(result)))")
        }
    }

    private func setPropertyString(_ name: String, _ value: String) {
        guard let handle else { return }
        let result = mpv_set_property_string(handle, name, value)
        if result < 0 {
            NSLog("[BMusic] mpv set \(name) failed: \(String(cString: mpv_error_string(result)))")
        }
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let handle else { return }
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard let handle else { return }
        var number = value
        mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &number)
    }

    private func command(_ arguments: [String]) {
        guard let handle else { return }
        var pointers: [UnsafePointer<CChar>?] = arguments.map { argument in
            UnsafePointer(strdup(argument))
        }
        pointers.append(nil)
        defer {
            for pointer in pointers {
                if let pointer {
                    free(UnsafeMutablePointer(mutating: pointer))
                }
            }
        }
        let result = mpv_command(handle, &pointers)
        if result < 0 {
            NSLog("[BMusic] mpv command \(arguments.first ?? "") failed: \(String(cString: mpv_error_string(result)))")
        }
    }
}

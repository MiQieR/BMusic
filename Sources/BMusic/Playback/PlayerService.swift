import Combine
import Foundation
import MediaPlayer
#if os(macOS)
import AppKit
#else
import UIKit
import AVFAudio
#endif

private struct PlaybackSnapshot: Codable {
    var queue: [Track]
    var index: Int
    var position: Double
    var sourceTitle: String
}

@MainActor
final class PlayerService: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var volume: Double = 0.72
    @Published private(set) var isMuted = false
    @Published private(set) var actualQuality: PlaybackQuality = .lossless
    @Published private(set) var errorText: String?
    @Published private(set) var sourceTitle: String = ""
    @Published private(set) var isOfflinePlayback = false
    @Published private(set) var engineAvailable = true
    @Published private(set) var sleepEnd: Date?

    let api: BiliAPI
    let library: LibraryStore
    let downloads: DownloadStore
    let settings: SettingsStore
    let lyrics: LyricsService

    private var engine: MPVEngine?
    private var streamTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var engineHasLoaded = false
    private var isSwitching = false
    private var didHandleEnd = false
    private var pendingResume: Double = 0
    private var historyIndices: [Int] = []
    private var cancellables: Set<AnyCancellable> = []
    private var sleepTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private let snapshotURL: URL

    var currentTrack: Track? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var hasCurrentTrack: Bool { currentTrack != nil }
    var hasNext: Bool { queue.count > 1 && currentIndex < queue.count - 1 }
    var hasPrevious: Bool { queue.count > 1 && currentIndex > 0 }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var isLiked: Bool { currentTrack.map(library.isLiked) ?? false }
    var upNext: [Track] {
        guard currentIndex >= 0, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }
    var timeText: String { Formatters.duration(Int(position.rounded())) }
    var durationText: String { Formatters.duration(Int(duration.rounded())) }
    var sleepRemainingText: String? {
        guard let sleepEnd else { return nil }
        let remaining = max(0, Int(sleepEnd.timeIntervalSinceNow))
        return Formatters.duration(remaining)
    }

    init(
        api: BiliAPI,
        library: LibraryStore,
        downloads: DownloadStore,
        settings: SettingsStore,
        lyrics: LyricsService,
        snapshotURL: URL = AppPaths.root.appendingPathComponent("playback.json")
    ) {
        self.api = api
        self.library = library
        self.downloads = downloads
        self.settings = settings
        self.lyrics = lyrics
        self.snapshotURL = snapshotURL
        self.volume = settings.volume
        self.actualQuality = settings.quality

        do {
            let engine = try MPVEngine()
            self.engine = engine
            engine.onEvent = { [weak self] event in
                self?.handle(event)
            }
            engine.setVolume(settings.volume)
            engine.setGapless(settings.gaplessPlayback)
        } catch {
            engineAvailable = false
            errorText = error.localizedDescription
            NSLog("[BMusic] MPV init failed: \(error.localizedDescription)")
        }

        restoreSnapshot()
        setupRemoteCommands()

        settings.$gaplessPlayback
            .sink { [weak self] enabled in self?.engine?.setGapless(enabled) }
            .store(in: &cancellables)
        settings.$systemNowPlaying
            .sink { [weak self] enabled in self?.applyNowPlayingVisibility(enabled) }
            .store(in: &cancellables)

        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.saveSnapshotNow()
                // 进程要退出了：跳过 libmpv 销毁，规避退出期音频事件竞态崩溃。
                self.engine?.skipDestroyOnExit()
            }
        }
        #else
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.saveSnapshotNow() }
        }
        #endif

        settings.$quality
            .dropFirst()
            .sink { [weak self] quality in
                guard let self, quality != self.actualQuality else { return }
                self.reloadForQuality(quality)
            }
            .store(in: &cancellables)
    }

    deinit {
        streamTask?.cancel()
        sleepTask?.cancel()
        snapshotTask?.cancel()
        artworkTask?.cancel()
    }

    // MARK: - Queue control

    func play(_ track: Track, sourceTitle: String = "") {
        play(tracks: [track], startingAt: 0, sourceTitle: sourceTitle)
    }

    func play(tracks: [Track], startingAt index: Int, sourceTitle: String = "") {
        guard !tracks.isEmpty else { return }
        let safeIndex = min(max(0, index), tracks.count - 1)
        queue = tracks
        currentIndex = safeIndex
        self.sourceTitle = sourceTitle
        position = 0
        duration = Double(tracks[safeIndex].duration)
        historyIndices = [safeIndex]
        didHandleEnd = false
        library.recordPlay(tracks[safeIndex])
        loadCurrent(resumeAt: 0)
        saveSnapshotSoon()
    }

    func play(at index: Int, resumeAt: Double = 0) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        position = resumeAt
        historyIndices.append(index)
        didHandleEnd = false
        let track = queue[index]
        duration = Double(track.duration)
        library.recordPlay(track)
        loadCurrent(resumeAt: resumeAt)
        saveSnapshotSoon()
    }

    func addToQueue(_ track: Track, playNext: Bool = false) {
        if queue.isEmpty {
            play(track)
            return
        }
        let insertIndex = min(queue.count, currentIndex + 1)
        if playNext, queue.indices.contains(insertIndex) {
            queue.insert(track, at: insertIndex)
        } else {
            queue.append(track)
        }
        saveSnapshotSoon()
    }

    func removeQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        if index == currentIndex {
            queue.remove(at: index)
            if queue.isEmpty {
                stop()
                return
            }
            currentIndex = min(index, queue.count - 1)
            loadCurrent(resumeAt: 0)
        } else {
            queue.remove(at: index)
            if index < currentIndex { currentIndex -= 1 }
        }
        saveSnapshotSoon()
    }

    func moveQueueItem(from source: Int, to destination: Int) {
        guard queue.indices.contains(source), queue.indices.contains(destination) else { return }
        let item = queue.remove(at: source)
        queue.insert(item, at: destination)
        if source == currentIndex {
            currentIndex = destination
        } else if source < currentIndex && destination >= currentIndex {
            currentIndex -= 1
        } else if source > currentIndex && destination <= currentIndex {
            currentIndex += 1
        }
        saveSnapshotSoon()
    }

    func clearQueue() {
        stop()
        queue = []
        currentIndex = -1
        sourceTitle = ""
        saveSnapshotSoon()
    }

    // MARK: - Transport

    func togglePlayPause() {
        guard currentTrack != nil else {
            if !queue.isEmpty {
                play(at: 0)
            }
            return
        }
        guard engineAvailable else {
            errorText = "libmpv 播放引擎不可用"
            return
        }
        if !engineHasLoaded {
            loadCurrent(resumeAt: position)
            return
        }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard engineHasLoaded else {
            loadCurrent(resumeAt: position)
            return
        }
        engine?.play()
        isPlaying = true
        updateNowPlaying()
        saveSnapshotSoon()
    }

    func pause() {
        engine?.pause()
        isPlaying = false
        updateNowPlaying()
        saveSnapshotSoon()
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        if auto && settings.repeatMode == .one {
            engine?.seek(to: 0)
            engine?.play()
            return
        }
        var nextIndex: Int
        if settings.shuffle && queue.count > 1 {
            repeat {
                nextIndex = Int.random(in: 0..<queue.count)
            } while nextIndex == currentIndex
        } else {
            nextIndex = currentIndex + 1
        }
        if nextIndex >= queue.count {
            if settings.repeatMode == .all || !auto {
                nextIndex = 0
            } else {
                isPlaying = false
                position = duration
                updateNowPlaying()
                return
            }
        }
        play(at: nextIndex)
    }

    func previous() {
        if position > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        let previousIndex: Int
        if settings.shuffle, historyIndices.count > 1 {
            historyIndices.removeLast()
            previousIndex = historyIndices.last ?? 0
        } else {
            previousIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        }
        play(at: previousIndex)
    }

    func seek(to seconds: Double) {
        let target = max(0, min(duration > 0 ? duration : seconds, seconds))
        position = target
        engine?.seek(to: target)
        updateNowPlaying()
        saveSnapshotSoon()
    }

    func seek(by delta: Double) {
        seek(to: position + delta)
    }

    func setVolume(_ newValue: Double) {
        let clamped = max(0, min(1, newValue))
        volume = clamped
        settings.volume = clamped
        engine?.setVolume(clamped)
        if clamped > 0 && isMuted {
            isMuted = false
            engine?.setMuted(false)
        }
    }

    func toggleMute() {
        isMuted.toggle()
        engine?.setMuted(isMuted)
    }

    func toggleShuffle() {
        settings.shuffle.toggle()
        ToastCenter.shared.show(settings.shuffle ? "已开启随机播放" : "已关闭随机播放", symbol: "shuffle")
    }

    func cycleRepeatMode() {
        settings.cycleRepeatMode()
        let title: String
        switch settings.repeatMode {
        case .off: title = "顺序播放"
        case .all: title = "列表循环"
        case .one: title = "单曲循环"
        }
        ToastCenter.shared.show(title, symbol: settings.repeatMode.symbol)
    }

    func toggleLikeCurrent() {
        guard let track = currentTrack else { return }
        let liked = library.toggleLike(track)
        ToastCenter.shared.show(
            liked ? "已收藏到喜欢的音乐" : "已取消收藏",
            symbol: liked ? "heart.fill" : "heart"
        )
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        loadGeneration += 1
        engine?.stop()
        engineHasLoaded = false
        isPlaying = false
        isLoading = false
        isBuffering = false
        isOfflinePlayback = false
        position = 0
        lyrics.clear()
        updateNowPlaying()
    }

    func downloadCurrent() {
        guard let track = currentTrack else { return }
        downloads.enqueue(track: track, quality: settings.quality, api: api)
        ToastCenter.shared.show("已加入下载队列", symbol: "arrow.down.circle")
    }

    // MARK: - Quality

    func reloadForQuality(_ quality: PlaybackQuality) {
        guard let track = currentTrack, engineHasLoaded else {
            actualQuality = quality
            return
        }
        let resumePosition = position
        actualQuality = quality
        loadCurrent(resumeAt: resumePosition)
    }

    // MARK: - Loading

    private func loadCurrent(resumeAt: Double) {
        guard let track = currentTrack else { return }
        guard engineAvailable else {
            errorText = "libmpv 播放引擎不可用"
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        streamTask?.cancel()
        didHandleEnd = false
        isSwitching = true
        engineHasLoaded = false
        isLoading = true
        isBuffering = true
        errorText = nil
        pendingResume = resumeAt
        actualQuality = settings.quality
        isOfflinePlayback = false

        if !track.cid.isEmpty {
            lyrics.load(for: track)
        }

        if let local = downloads.localFile(for: track, quality: settings.quality)
            ?? downloads.bestLocalFile(for: track) {
            isOfflinePlayback = true
            isBuffering = false
            isLoading = false
            duration = Double(track.duration)
            engine?.loadLocal(url: local)
            return
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await self.api.ensureCID(for: track)
                guard generation == self.loadGeneration, !Task.isCancelled else { return }
                if prepared.cid != track.cid || prepared.pages.count != track.pages.count {
                    self.replaceCurrentTrack(prepared)
                }
                self.lyrics.load(for: prepared)
                let stream = try await self.api.resolveStream(
                    for: prepared,
                    quality: self.settings.quality
                )
                guard generation == self.loadGeneration, !Task.isCancelled else { return }
                self.actualQuality = stream.quality
                self.duration = Double(prepared.duration)
                self.engine?.load(url: stream.url, headers: stream.headers)
                self.updateNowPlaying()
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.loadGeneration else { return }
                self.isLoading = false
                self.isBuffering = false
                self.isSwitching = false
                self.isPlaying = false
                self.errorText = error.localizedDescription
                NSLog("[BMusic] stream load failed: \(error.localizedDescription)")
                ToastCenter.shared.error(error.localizedDescription)
            }
        }
    }

    private func replaceCurrentTrack(_ track: Track) {
        guard queue.indices.contains(currentIndex) else { return }
        queue[currentIndex] = track
        duration = max(duration, Double(track.duration))
    }

    // MARK: - Engine events

    private func handle(_ event: MPVEvent) {
        switch event {
        case .property(let name, let value):
            handleProperty(name: name, value: value)
        case .fileLoaded:
            handleFileLoaded()
        case .endFile(let reason):
            if isSwitching || reason == "stop" || reason == "quit" { return }
            if reason != "eof" && !reason.isEmpty {
                errorText = reason
            }
            handleEnded()
        case .idle:
            break
        case .shutdown:
            engineAvailable = false
        case .startFile:
            break
        case .log(let level, let message):
            if level == "error" && !message.isEmpty {
                NSLog("[BMusic] mpv: \(message)")
            }
        }
    }

    private func handleProperty(name: String, value: MPVValue) {
        switch (name, value) {
        case ("time-pos", .double(let seconds)):
            guard seconds.isFinite, seconds >= 0 else { return }
            position = seconds
        case ("duration", .double(let seconds)):
            guard seconds.isFinite, seconds > 0 else { return }
            duration = seconds
        case ("pause", .flag(let paused)):
            if engineHasLoaded && !isSwitching {
                isPlaying = !paused
                updateNowPlaying()
            }
        case ("paused-for-cache", .flag(let paused)):
            isBuffering = paused
        case ("eof-reached", .flag(let ended)):
            guard ended, engineHasLoaded, !didHandleEnd else { return }
            handleEnded()
        case ("core-idle", .flag(let idle)):
            if idle && engineHasLoaded && !isSwitching && position > 0 && duration > 0 {
                // mpv becomes core-idle briefly while switching audio tracks.
            }
        default:
            break
        }
    }

    private func handleFileLoaded() {
        guard let track = currentTrack else { return }
        isSwitching = false
        isLoading = false
        isBuffering = false
        engineHasLoaded = true
        didHandleEnd = false
        if duration <= 0 { duration = Double(track.duration) }
        if pendingResume > 1 {
            engine?.seek(to: pendingResume)
            position = pendingResume
        }
        pendingResume = 0
        engine?.play()
        isPlaying = true
        updateNowPlaying()
        lyrics.load(for: track)
        saveSnapshotSoon()
    }

    private func handleEnded() {
        guard !didHandleEnd else { return }
        didHandleEnd = true
        isPlaying = false
        if settings.repeatMode == .one {
            engine?.seek(to: 0)
            engine?.play()
            isPlaying = true
            didHandleEnd = false
            return
        }
        if settings.autoPlayNext {
            next(auto: true)
        } else {
            stop()
        }
    }

    // MARK: - Sleep timer

    func setSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepTask = nil
        if minutes <= 0 {
            sleepEnd = nil
            return
        }
        sleepEnd = Date().addingTimeInterval(TimeInterval(minutes * 60))
        ToastCenter.shared.show("将在 \(minutes) 分钟后暂停播放", symbol: "moon.zzz")
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                guard let end = self.sleepEnd else { return }
                if Date() >= end {
                    self.pause()
                    self.sleepEnd = nil
                    ToastCenter.shared.show("睡眠定时已结束", symbol: "moon.zzz")
                    return
                }
            }
        }
    }

    // MARK: - System now playing

    private func applyNowPlayingVisibility(_ enabled: Bool) {
        setRemoteCommandsEnabled(enabled)
        if enabled {
            updateNowPlaying()
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            #if os(iOS)
            UIApplication.shared.endReceivingRemoteControlEvents()
            #endif
        }
    }

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.nextTrackCommand.isEnabled = enabled
        center.previousTrackCommand.isEnabled = enabled
        center.changePlaybackPositionCommand.isEnabled = enabled
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        setRemoteCommandsEnabled(settings.systemNowPlaying)

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard settings.systemNowPlaying, let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.displayName,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: max(duration, Double(track.duration))
        ]
        if !track.coverURL.isEmpty,
           let image = ImageStore.shared.cached(track.coverURL) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        loadArtwork(for: track)
    }

    private func loadArtwork(for track: Track) {
        guard !track.coverURL.isEmpty,
              MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil
        else { return }
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let image = await ImageStore.shared.image(for: track.coverURL) else { return }
            guard let self, self.currentTrack?.id == track.id else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    // MARK: - Snapshot

    private func restoreSnapshot() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data),
              !snapshot.queue.isEmpty
        else { return }
        queue = snapshot.queue
        currentIndex = min(max(0, snapshot.index), queue.count - 1)
        position = max(0, snapshot.position)
        duration = Double(queue[currentIndex].duration)
        sourceTitle = snapshot.sourceTitle
        actualQuality = settings.quality
        isPlaying = false
        if !queue[currentIndex].coverURL.isEmpty {
            Task { [weak self] in
                _ = await ImageStore.shared.image(for: queue[currentIndex].coverURL)
                self?.updateNowPlaying()
            }
        }
    }

    func saveSnapshotNow() {
        guard !queue.isEmpty else {
            try? FileManager.default.removeItem(at: snapshotURL)
            return
        }
        let snapshot = PlaybackSnapshot(
            queue: queue,
            index: currentIndex,
            position: position,
            sourceTitle: sourceTitle
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            NSLog("[BMusic] playback snapshot failed: \(error.localizedDescription)")
        }
    }

    private func saveSnapshotSoon() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.saveSnapshotNow() }
        }
    }
}

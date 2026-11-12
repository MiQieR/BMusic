import Foundation

enum DownloadState: String, Codable {
    case queued, downloading, completed, failed
}

struct DownloadItem: Identifiable, Codable, Hashable {
    var id: String
    var track: Track
    var quality: PlaybackQuality
    var state: DownloadState
    var progress: Double
    var filePath: String?
    var bytes: Int64
    var message: String?
    var createdAt: Date
}

private struct DownloadArchive: Codable {
    var items: [DownloadItem]
}

@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    private let directory: URL
    private let manifestURL: URL
    private var tasks: [String: Task<Void, Never>] = [:]

    init(directory: URL = AppPaths.downloads) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent("downloads.json")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        load()
    }

    var activeCount: Int {
        items.filter { $0.state == .downloading || $0.state == .queued }.count
    }

    var completedCount: Int {
        items.filter { $0.state == .completed }.count
    }

    var totalBytes: Int64 {
        items.filter { $0.state == .completed }.reduce(0) { $0 + $1.bytes }
    }

    func localFile(for track: Track, quality: PlaybackQuality) -> URL? {
        let id = identifier(track: track, quality: quality)
        guard let item = items.first(where: { $0.id == id }),
              item.state == .completed,
              let path = item.filePath,
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Any downloaded rendition of the track, preferring the requested quality.
    func bestLocalFile(for track: Track) -> URL? {
        if let exact = localFile(for: track, quality: .lossless) { return exact }
        for quality in PlaybackQuality.allCases {
            if let file = localFile(for: track, quality: quality) { return file }
        }
        return nil
    }

    func item(for track: Track, quality: PlaybackQuality) -> DownloadItem? {
        items.first { $0.id == identifier(track: track, quality: quality) }
    }

    func enqueue(track: Track, quality: PlaybackQuality, api: BiliAPI) {
        let id = identifier(track: track, quality: quality)
        if let existing = items.first(where: { $0.id == id }),
           existing.state == .downloading || existing.state == .queued {
            ToastCenter.shared.show("这首歌曲已经在下载了")
            return
        }
        if let existing = items.first(where: { $0.id == id }),
           existing.state == .completed,
           let path = existing.filePath,
           FileManager.default.fileExists(atPath: path) {
            ToastCenter.shared.show("已下载到本地")
            return
        }

        let item = DownloadItem(
            id: id,
            track: track,
            quality: quality,
            state: .queued,
            progress: 0,
            filePath: nil,
            bytes: 0,
            message: nil,
            createdAt: Date()
        )
        items.removeAll { $0.id == id }
        items.insert(item, at: 0)
        persist()

        tasks[id] = Task { [weak self] in
            await self?.runDownload(id: id, api: api)
        }
    }

    func cancel(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        update(id) { item in
            item.state = .failed
            item.message = "已取消"
        }
    }

    func remove(id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        if let item = items.first(where: { $0.id == id }), let path = item.filePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        items.removeAll { $0.id == id }
        persist()
    }

    func retry(id: String, api: BiliAPI) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        enqueue(track: item.track, quality: item.quality, api: api)
    }

    func clearCompleted() {
        for item in items where item.state == .completed {
            if let path = item.filePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        items.removeAll { $0.state == .completed }
        persist()
    }

    func reveal(_ item: DownloadItem) {
        guard let path = item.filePath else { return }
        PlatformActions.reveal(URL(fileURLWithPath: path))
    }

    // MARK: - Downloading

    private func runDownload(id: String, api: BiliAPI) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        update(id) {
            $0.state = .downloading
            $0.progress = 0.12
            $0.message = nil
        }

        do {
            let stream = try await api.resolveStream(for: item.track, quality: item.quality)
            var request = URLRequest(url: stream.url)
            request.timeoutInterval = 60
            for (key, value) in stream.headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                throw BiliError.network("音频下载失败")
            }
            try Task.checkCancellation()

            let filename = "\(item.track.bvid)_\(item.track.cid.isEmpty ? "0" : item.track.cid)_\(item.quality.rawValue).m4a"
            let fileURL = directory.appendingPathComponent(filename)
            try data.write(to: fileURL, options: .atomic)

            update(id) {
                $0.state = .completed
                $0.progress = 1
                $0.filePath = fileURL.path
                $0.bytes = Int64(data.count)
                $0.message = nil
            }
            tasks[id] = nil
        } catch is CancellationError {
            update(id) {
                $0.state = .failed
                $0.message = "已取消"
            }
        } catch {
            update(id) {
                $0.state = .failed
                $0.progress = 0
                $0.message = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func identifier(track: Track, quality: PlaybackQuality) -> String {
        "\(track.queueKey)#\(quality.rawValue)"
    }

    private func update(_ id: String, mutate: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let archive = try? JSONDecoder().decode(DownloadArchive.self, from: data)
        else { return }
        items = archive.items.map { item in
            var copy = item
            if copy.state == .downloading || copy.state == .queued {
                copy.state = .failed
                copy.message = "上次下载中断"
            }
            if copy.state == .completed,
               let path = copy.filePath,
               !FileManager.default.fileExists(atPath: path) {
                copy.state = .failed
                copy.message = "本地文件已丢失"
            }
            return copy
        }
        pruneOrphanFiles()
    }

    private func persist() {
        let archive = DownloadArchive(items: items)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(archive)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            NSLog("[BMusic] download manifest failed: \(error.localizedDescription)")
        }
    }

    private func pruneOrphanFiles() {
        let known = Set(items.compactMap { $0.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } })
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "m4a" && !known.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

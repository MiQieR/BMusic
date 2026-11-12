import Foundation

@MainActor
final class LyricsService: ObservableObject {
    @Published private(set) var lyrics: Lyrics = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var currentTrackID: String?

    private let api: BiliAPI
    private let cacheDirectory: URL
    private var memory: [String: Lyrics] = [:]
    private var task: Task<Void, Never>?
    private var currentTrack: Track?

    init(api: BiliAPI, cacheDirectory: URL = AppPaths.lyrics) {
        self.api = api
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func load(for track: Track) {
        guard currentTrackID != track.id || lyrics.isEmpty else { return }
        currentTrack = track
        currentTrackID = track.id
        errorText = nil
        task?.cancel()

        if let cached = memory[track.id] {
            lyrics = cached
            isLoading = false
            return
        }
        if let cached = readDisk(track.id) {
            memory[track.id] = cached
            lyrics = cached
            isLoading = false
            return
        }

        lyrics = .empty
        isLoading = true
        task = Task { [weak self] in
            await self?.fetch(track)
        }
    }

    func clear() {
        task?.cancel()
        currentTrackID = nil
        currentTrack = nil
        lyrics = .empty
        isLoading = false
        errorText = nil
    }

    func activeLineIndex(at time: TimeInterval) -> Int? {
        lyrics.activeIndex(at: time)
    }

    private func fetch(_ track: Track) async {
        var resolved = track
        if resolved.cid.isEmpty, let detailed = try? await api.ensureCID(for: track) {
            resolved = detailed
        }

        do {
            let subtitles = try await api.subtitles(bvid: resolved.bvid, cid: resolved.cid)
            if let subtitle = subtitles.first(where: { $0.language.hasPrefix("zh") }) ?? subtitles.first {
                let lines = try await api.subtitleLines(url: subtitle.url)
                if !lines.isEmpty {
                    guard !Task.isCancelled else { return }
                    let result = Lyrics(
                        lines: lines,
                        source: "B站字幕 · \(subtitle.languageLabel)",
                        isSynced: true
                    )
                    finish(result, for: track)
                    return
                }
            }
        } catch {
            // Subtitle failures are expected on most uploads; fall through to LRCLIB.
        }

        if let found = await api.searchLyrics(
            title: resolved.title,
            artist: resolved.artist.name,
            duration: resolved.duration
        ) {
            guard !Task.isCancelled else { return }
            finish(found, for: track)
            return
        }

        guard !Task.isCancelled, currentTrackID == track.id else { return }
        isLoading = false
        lyrics = .empty
        errorText = "暂无歌词"
        let empty = Lyrics(lines: [], source: "", isSynced: false)
        memory[track.id] = empty
    }

    private func finish(_ result: Lyrics, for track: Track) {
        guard !Task.isCancelled, currentTrackID == track.id else { return }
        lyrics = result
        isLoading = false
        errorText = nil
        memory[track.id] = result
        writeDisk(result, for: track.id)
    }

    // MARK: - Cache

    private func readDisk(_ id: String) -> Lyrics? {
        let url = cacheDirectory.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url),
              let lyrics = try? JSONDecoder().decode(Lyrics.self, from: data),
              !lyrics.isEmpty
        else { return nil }
        return lyrics
    }

    private func writeDisk(_ lyrics: Lyrics, for id: String) {
        guard !lyrics.isEmpty else { return }
        let url = cacheDirectory.appendingPathComponent("\(id).json")
        if let data = try? JSONEncoder().encode(lyrics) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

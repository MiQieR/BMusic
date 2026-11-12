import Foundation

struct LocalPlaylist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var tracks: [Track]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, tracks: [Track] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var track: Track
    var playedAt: Date

    init(id: UUID = UUID(), track: Track, playedAt: Date = Date()) {
        self.id = id
        self.track = track
        self.playedAt = playedAt
    }
}

private struct LibraryArchive: Codable {
    var liked: [Track]
    var playlists: [LocalPlaylist]
    var history: [HistoryEntry]
    var searches: [String]
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var playlists: [LocalPlaylist] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var recentSearches: [String] = []

    private var likedIDs: Set<String> = []
    private let fileURL: URL

    init(fileURL: URL = AppPaths.library) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - Likes

    func isLiked(_ track: Track) -> Bool {
        likedIDs.contains(track.bvid)
    }

    @discardableResult
    func toggleLike(_ track: Track) -> Bool {
        if likedIDs.contains(track.bvid) {
            likedIDs.remove(track.bvid)
            likedTracks.removeAll { $0.bvid == track.bvid }
            persist()
            return false
        }
        likedIDs.insert(track.bvid)
        likedTracks.insert(track, at: 0)
        persist()
        return true
    }

    func addLiked(_ track: Track) {
        guard !likedIDs.contains(track.bvid) else { return }
        likedIDs.insert(track.bvid)
        likedTracks.insert(track, at: 0)
        persist()
    }

    // MARK: - History

    func recordPlay(_ track: Track) {
        history.removeAll { $0.track.queueKey == track.queueKey }
        history.insert(HistoryEntry(track: track), at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
        persist()
    }

    func clearHistory() {
        history.removeAll()
        persist()
    }

    var recentlyPlayed: [Track] {
        var seen = Set<String>()
        return history.compactMap { entry in
            guard seen.insert(entry.track.bvid).inserted else { return nil }
            return entry.track
        }
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(name: String) -> LocalPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = LocalPlaylist(name: trimmed.isEmpty ? "新建歌单" : trimmed)
        playlists.insert(playlist, at: 0)
        persist()
        return playlist
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        persist()
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists[index].name = trimmed
        playlists[index].updatedAt = Date()
        persist()
    }

    func add(_ track: Track, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard !playlists[index].tracks.contains(where: { $0.queueKey == track.queueKey }) else {
            return
        }
        playlists[index].tracks.append(track)
        playlists[index].updatedAt = Date()
        persist()
    }

    func remove(_ track: Track, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].tracks.removeAll { $0.queueKey == track.queueKey }
        playlists[index].updatedAt = Date()
        persist()
    }

    func playlist(_ id: UUID) -> LocalPlaylist? {
        playlists.first { $0.id == id }
    }

    // MARK: - Search history

    func rememberSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 8 { recentSearches.removeLast(recentSearches.count - 8) }
        persist()
    }

    func clearSearches() {
        recentSearches.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(LibraryArchive.self, from: data)
        else { return }
        likedTracks = archive.liked
        likedIDs = Set(archive.liked.map(\.bvid))
        playlists = archive.playlists
        history = archive.history
        recentSearches = archive.searches
    }

    private func persist() {
        let archive = LibraryArchive(
            liked: likedTracks,
            playlists: playlists,
            history: history,
            searches: recentSearches
        )
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(archive)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            NSLog("[BMusic] library persistence failed: \(error.localizedDescription)")
        }
    }
}

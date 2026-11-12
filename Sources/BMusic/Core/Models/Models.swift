import Foundation

// MARK: - Artist

struct Artist: Codable, Hashable, Identifiable, Sendable {
    var mid: Int64
    var name: String
    var avatarURL: String

    var id: Int64 { mid }

    static let unknown = Artist(mid: 0, name: "未知创作者", avatarURL: "")

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知创作者" : trimmed
    }

    var profileURL: URL? {
        guard mid > 0 else { return nil }
        return URL(string: "https://space.bilibili.com/\(mid)")
    }
}

// MARK: - Video page

/// One part (分P) of a Bilibili video. A music upload can contain several
/// tracks, so a queue item identifies both `bvid` and `cid`.
struct VideoPage: Codable, Hashable, Identifiable, Sendable {
    var cid: String
    var title: String
    var duration: Int
    var index: Int

    var id: String { cid }

    var durationText: String { Formatters.duration(duration) }

    static func == (lhs: VideoPage, rhs: VideoPage) -> Bool {
        lhs.cid == rhs.cid && lhs.index == rhs.index
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cid)
        hasher.combine(index)
    }
}

// MARK: - Track

enum TrackOrigin: String, Codable, Sendable {
    case home, ranking, search, related, hot, favorites, history, downloads, artist, manual

    var title: String {
        switch self {
        case .home: return "推荐"
        case .ranking: return "排行榜"
        case .search: return "搜索"
        case .related: return "相似音乐"
        case .hot: return "热歌榜"
        case .favorites: return "收藏夹"
        case .history: return "最近播放"
        case .downloads: return "已下载"
        case .artist: return "UP 主投稿"
        case .manual: return "手动添加"
        }
    }
}

struct Track: Codable, Hashable, Identifiable, Sendable {
    var bvid: String
    var cid: String
    var title: String
    var artist: Artist
    var album: String
    var coverURL: String
    var duration: Int
    var publishedAt: Date?
    var playCount: Int
    var danmakuCount: Int
    var likeCount: Int
    var pages: [VideoPage]
    var origin: TrackOrigin

    /// Stable across a cid backfill when the cid was previously unknown.
    var id: String { bvid }

    /// Queue identity: a multi-part video contributes one entry per part.
    var queueKey: String { "\(bvid)#\(cid.isEmpty ? "0" : cid)" }

    var durationText: String { Formatters.duration(duration) }

    var subtitle: String {
        let album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        if album.isEmpty { return artist.displayName }
        return "\(artist.displayName) · \(album)"
    }

    var webURL: URL? { URL(string: "https://www.bilibili.com/video/\(bvid)") }

    var currentPage: VideoPage? {
        pages.first(where: { $0.cid == cid }) ?? pages.first
    }

    init(
        bvid: String,
        cid: String = "",
        title: String,
        artist: Artist = .unknown,
        album: String = "",
        coverURL: String = "",
        duration: Int = 0,
        publishedAt: Date? = nil,
        playCount: Int = 0,
        danmakuCount: Int = 0,
        likeCount: Int = 0,
        pages: [VideoPage] = [],
        origin: TrackOrigin = .manual
    ) {
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.artist = artist
        self.album = album
        self.coverURL = coverURL
        self.duration = duration
        self.publishedAt = publishedAt
        self.playCount = playCount
        self.danmakuCount = danmakuCount
        self.likeCount = likeCount
        self.pages = pages
        self.origin = origin
    }

    func with(
        cid: String? = nil,
        title: String? = nil,
        artist: Artist? = nil,
        album: String? = nil,
        coverURL: String? = nil,
        duration: Int? = nil,
        pages: [VideoPage]? = nil,
        origin: TrackOrigin? = nil
    ) -> Track {
        var copy = self
        if let cid { copy.cid = cid }
        if let title { copy.title = title }
        if let artist { copy.artist = artist }
        if let album { copy.album = album }
        if let coverURL { copy.coverURL = coverURL }
        if let duration { copy.duration = duration }
        if let pages { copy.pages = pages }
        if let origin { copy.origin = origin }
        return copy
    }
}

// MARK: - Search

enum SearchKind: String, CaseIterable, Identifiable, Sendable {
    case video
    case user
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "单曲"
        case .user: return "UP 主"
        case .media: return "影视"
        }
    }

    var searchType: String {
        switch self {
        case .video: return "video"
        case .user: return "bili_user"
        case .media: return "media_bangumi"
        }
    }
}

struct SearchItem: Identifiable, Hashable, Sendable {
    var id: String
    var kind: SearchKind
    var title: String
    var subtitle: String
    var coverURL: String
    var artist: Artist
    var duration: Int
    var playCount: Int
    var publishedAt: Date?

    var searchTrack: Track? {
        guard kind == .video else { return nil }
        return Track(
            bvid: id,
            title: title,
            artist: artist,
            album: "",
            coverURL: coverURL,
            duration: duration,
            publishedAt: publishedAt,
            playCount: playCount,
            origin: .search
        )
    }
}

// MARK: - Playlists / favourites

struct FavoriteFolder: Identifiable, Hashable, Codable, Sendable {
    var id: Int64
    var title: String
    var coverURL: String
    var mediaCount: Int
    var isCollected: Bool
    var ownerName: String
}

struct HotSong: Identifiable, Hashable, Sendable {
    var rank: Int
    var title: String
    var singer: String
    var album: String
    var coverURL: String
    var heat: Int
    var duration: Int
    var bvid: String
    var cid: String
    var rankDelta: Int?
    var achievements: [String]

    var id: String { bvid.isEmpty ? "\(rank)-\(title)-\(singer)" : bvid }

    var track: Track {
        Track(
            bvid: bvid,
            cid: cid,
            title: title,
            artist: Artist(mid: 0, name: singer, avatarURL: ""),
            album: album,
            coverURL: coverURL,
            duration: duration,
            origin: .hot
        )
    }

    var isPlayable: Bool { !bvid.isEmpty }
}

// MARK: - Account

struct Account: Codable, Hashable, Sendable {
    var mid: Int64
    var name: String
    var avatarURL: String
    var sign: String
    var level: Int
    var vipLabel: String
    var coins: Double
    var following: Int
    var follower: Int
}

// MARK: - Playback

enum PlaybackQuality: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard = "30216"
    case high = "30232"
    case lossless = "30280"
    case hiRes = "30251"
    case dolby = "30250"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "64K"
        case .high: return "132K"
        case .lossless: return "192K"
        case .hiRes: return "Hi-Res"
        case .dolby: return "杜比全景声"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "流畅，节省流量"
        case .high: return "标准音质"
        case .lossless: return "高品质立体声"
        case .hiRes: return "无损，需要大会员"
        case .dolby: return "空间音频，需要大会员"
        }
    }

    var badge: String {
        switch self {
        case .standard: return "64K"
        case .high: return "132K"
        case .lossless: return "192K"
        case .hiRes: return "Hi-Res"
        case .dolby: return "Dolby"
        }
    }
}

enum RepeatMode: String, Codable, Sendable {
    case off, all, one

    var symbol: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    mutating func advance() {
        switch self {
        case .off: self = .all
        case .all: self = .one
        case .one: self = .off
        }
    }
}

enum PlayerPanel: String, Sendable {
    case lyrics, queue
}

// MARK: - Lyrics

struct LyricLine: Identifiable, Hashable, Codable, Sendable {
    var id: Int
    var time: TimeInterval
    var text: String

    var timeText: String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct Lyrics: Hashable, Codable, Sendable {
    var lines: [LyricLine]
    var source: String
    var isSynced: Bool

    var isEmpty: Bool { lines.isEmpty }

    static let empty = Lyrics(lines: [], source: "", isSynced: false)

    func activeIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= time + 0.12 { result = index } else { break }
        }
        return result
    }
}

// MARK: - Subtitle

struct SubtitleTrack: Identifiable, Hashable, Sendable {
    var id: String
    var language: String
    var languageLabel: String
    var url: String
}

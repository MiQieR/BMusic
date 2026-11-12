import Foundation

struct StreamResolution {
    var url: URL
    var backupURLs: [URL]
    var quality: PlaybackQuality
    var headers: [String: String]
}

struct RankingResult {
    var note: String
    var items: [Track]
}

struct FavoritePage {
    var title: String
    var coverURL: String
    var total: Int
    var tracks: [Track]
    var hasMore: Bool
}

enum QRLoginStatus: Equatable {
    case waiting
    case scanned
    case success
    case expired
    case unknown
}

struct QRLoginTicket {
    var url: String
    var key: String
}

/// Bilibili web API semantics: cards, search, playback streams, favourites,
/// subtitles and passport QR login. All transport concerns stay in BiliClient.
@MainActor
final class BiliAPI {
    static let musicRankingRID = 1003
    static let musicRegionID = 1003

    let client: BiliClient
    var jar: CookieJar { client.jar }

    init(client: BiliClient) {
        self.client = client
    }

    func bootstrap() async {
        await client.bootstrapDeviceCookies()
    }

    // MARK: - Account

    func account() async -> Account? {
        do {
            let envelope = try await client.envelope(
                path: "/x/web-interface/nav",
                allowCodes: [-101]
            )
            guard let data = envelope["data"] as? [String: Any],
                  data.bool("isLogin"),
                  data.int64("mid") > 0
            else { return nil }
            let vip = data.dict("vip_label")
            let levelInfo = data.dict("level_info")
            let vipLabel: String
            if data.int("vipStatus") == 1 || data.int("vip_type") > 0 {
                vipLabel = vip?.string("text").isEmpty == false ? vip!.string("text") : "大会员"
            } else {
                vipLabel = ""
            }
            return Account(
                mid: data.int64("mid"),
                name: data.string("uname"),
                avatarURL: Self.imageURL(data.string("face")),
                sign: data.string("sign"),
                level: levelInfo?.int("current_level") ?? data.int("level"),
                vipLabel: vipLabel,
                coins: data.double("coins"),
                following: data.int("following"),
                follower: data.int("follower")
            )
        } catch {
            NSLog("[BMusic] account fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    func logout() async {
        do {
            _ = try await client.envelope(
                path: "/login/exit/v2",
                base: BiliClient.passportBase,
                method: "POST",
                form: ["biliCSRF": jar.csrf]
            )
        } catch {
            NSLog("[BMusic] server logout failed: \(error.localizedDescription)")
        }
        jar.clearSession()
    }

    // MARK: - Home / discover

    func regionFeed(page: Int = 1, count: Int = 20) async throws -> [Track] {
        do {
            let envelope = try await client.envelope(
                path: "/x/web-interface/region/feed/rcmd",
                query: [
                    "display_id": String(page),
                    "request_cnt": String(max(1, min(count, 20))),
                    "from_region": String(Self.musicRegionID),
                    "device": "web",
                    "plat": "30"
                ]
            )
            guard let data = envelope["data"] as? [String: Any] else { return [] }
            return data.dictionaries("archives").compactMap {
                Self.trackFromCard($0, origin: .home)
            }
        } catch let error as BiliError {
            if case .api(let code, _) = error, code == 62013 { return [] }
            throw error
        }
    }

    func ranking(limit: Int = 30) async throws -> RankingResult {
        let envelope = try await client.envelope(
            path: "/x/web-interface/ranking/v2",
            query: ["rid": String(Self.musicRankingRID), "type": "all"]
        )
        guard let data = envelope["data"] as? [String: Any] else {
            return RankingResult(note: "", items: [])
        }
        let items = data.dictionaries("list").prefix(limit).compactMap {
            Self.trackFromCard($0, origin: .ranking)
        }
        return RankingResult(note: data.string("note"), items: Array(items))
    }

    func hotSongs() async throws -> [HotSong] {
        let periods = try await client.envelope(
            path: "/x/copyright-music-publicity/toplist/all_period",
            query: ["list_type": "1"]
        )
        guard let data = periods["data"] as? [String: Any],
              let list = data["list"] as? [String: Any]
        else { return [] }

        var latest: [String: Any]?
        var latestTimestamp = -1
        for value in list.values {
            guard let entries = value as? [Any] else { continue }
            for raw in entries {
                guard let entry = raw as? [String: Any] else { continue }
                let timestamp = entry.int("publish_time")
                if timestamp > latestTimestamp {
                    latestTimestamp = timestamp
                    latest = entry
                }
            }
        }
        guard let latest, latest.int("ID") > 0 else { return [] }
        let listID = latest.int("ID")

        let detail = try await client.envelope(
            path: "/x/copyright-music-publicity/toplist/music_list",
            query: ["list_id": String(listID)]
        )
        guard let detailData = detail["data"] as? [String: Any] else { return [] }
        return detailData.dictionaries("list").compactMap { raw -> HotSong? in
            let rank = raw.int("rank")
            guard rank > 0 else { return nil }
            let mvCover = Self.imageURL(raw.string("mv_cover"))
            let creationCover = Self.imageURL(raw.string("creation_cover"))
            let lastRank = raw.int("last_rank")
            return HotSong(
                rank: rank,
                title: raw.string("music_title").isEmpty
                    ? raw.string("creation_title") : raw.string("music_title"),
                singer: raw.string("singer"),
                album: raw.string("album"),
                coverURL: mvCover.isEmpty ? creationCover : mvCover,
                heat: raw.int("heat"),
                duration: raw.int("creation_duration"),
                bvid: raw.string("creation_bvid"),
                cid: raw.int("creation_first_cid") > 0
                    ? String(raw.int("creation_first_cid")) : "",
                rankDelta: lastRank > 0 ? lastRank - rank : nil,
                achievements: (raw["achievements"] as? [Any])?.map {
                    String(describing: $0)
                } ?? []
            )
        }
        .sorted { $0.rank < $1.rank }
    }

    func related(to bvid: String, onlyMusic: Bool = true) async throws -> [Track] {
        let envelope = try await client.envelope(
            path: "/x/web-interface/archive/related",
            query: ["bvid": bvid]
        )
        guard let rows = envelope["data"] as? [Any] else { return [] }
        return rows.compactMap { raw -> Track? in
            guard let json = raw as? [String: Any] else { return nil }
            if onlyMusic {
                let tid = json.int("tid")
                if !Self.musicCategoryIDs.contains(tid) { return nil }
            }
            return Self.trackFromCard(json, origin: .related)
        }
    }

    // MARK: - Search

    func search(keyword: String, kind: SearchKind = .video, page: Int = 1) async throws -> [SearchItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let envelope = try await client.envelope(
            path: "/x/web-interface/search/type",
            query: [
                "search_type": kind.searchType,
                "keyword": trimmed,
                "page": String(max(1, page))
            ]
        )
        guard let data = envelope["data"] as? [String: Any],
              let rows = data["result"] as? [Any]
        else { return [] }
        return rows.compactMap { raw in
            guard let json = raw as? [String: Any] else { return nil }
            return Self.searchItem(from: json, kind: kind)
        }
    }

    func searchSuggestions(_ term: String) async -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            let envelope = try await client.envelope(
                path: "/main/suggest",
                base: BiliClient.suggestBase,
                query: ["term": trimmed, "main_ver": "v1", "highlight": ""]
            )
            guard let result = envelope["result"] as? [String: Any] else { return [] }
            return result.dictionaries("tag").compactMap { tag in
                let value = tag.string("value")
                return value.isEmpty ? nil : value
            }
        } catch {
            return []
        }
    }

    // MARK: - Video detail / stream

    func videoDetail(bvid: String) async throws -> Track {
        let data = try await client.data(
            path: "/x/web-interface/view",
            query: ["bvid": bvid]
        )
        guard !data.isEmpty, !data.string("bvid").isEmpty else {
            throw BiliError.unavailable("稿件不存在或已被删除")
        }
        return Self.trackFromView(data)
    }

    /// Fills the first page's cid if a list endpoint did not provide one.
    func ensureCID(for track: Track) async throws -> Track {
        if !track.cid.isEmpty { return track }
        let detail = try await videoDetail(bvid: track.bvid)
        return track.with(
            cid: detail.cid,
            artist: track.artist.mid == 0 ? detail.artist : track.artist,
            coverURL: track.coverURL.isEmpty ? detail.coverURL : track.coverURL,
            duration: track.duration == 0 ? detail.duration : track.duration,
            pages: detail.pages
        )
    }

    func resolveStream(for track: Track, quality: PlaybackQuality) async throws -> StreamResolution {
        let prepared = try await ensureCID(for: track)
        guard !prepared.cid.isEmpty else {
            throw BiliError.unavailable("无法获取该稿件的音频流")
        }
        let data = try await client.data(
            path: "/x/player/playurl",
            query: [
                "bvid": prepared.bvid,
                "cid": prepared.cid,
                "fnval": "4048",
                "fnver": "0",
                "fourk": "1"
            ]
        )
        guard let dash = data.dict("dash") else {
            throw BiliError.unavailable("该稿件没有可播放的音频")
        }

        var candidates: [[String: Any]] = []
        candidates.append(contentsOf: Self.streamList(dash["audio"]))
        if let flac = dash.dict("flac") {
            candidates.append(contentsOf: Self.streamList(flac["dash"] ?? flac["audio"]))
        }
        if let dolby = dash.dict("dolby") {
            candidates.append(contentsOf: Self.streamList(dolby["audio"] ?? dolby["dash"]))
        }

        // Prefer the requested quality, then degrade through the standard tiers.
        let order: [String] = [quality.rawValue, "30280", "30232", "30216"]
        var picked: [String: Any]?
        var pickedQuality = quality
        for wanted in order {
            if let match = candidates.first(where: {
                ($0.string("id") == wanted || ($0["id"] as? NSNumber)?.stringValue == wanted)
                    && !Self.baseURL(of: $0).isEmpty
            }) {
                picked = match
                pickedQuality = PlaybackQuality(rawValue: wanted) ?? quality
                break
            }
        }
        guard let picked, let url = URL(string: Self.baseURL(of: picked)) else {
            throw BiliError.unavailable("音频流地址为空")
        }
        let backups = (picked["backupUrl"] as? [Any] ?? picked["backup_url"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .compactMap(URL.init(string:))
        return StreamResolution(
            url: url,
            backupURLs: backups,
            quality: pickedQuality,
            headers: [
                "User-Agent": BiliClient.userAgent,
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com"
            ]
        )
    }

    // MARK: - Subtitles / lyrics

    func subtitles(bvid: String, cid: String) async throws -> [SubtitleTrack] {
        guard !bvid.isEmpty, !cid.isEmpty else { return [] }
        let data = try await client.data(
            path: "/x/player/v2",
            query: ["bvid": bvid, "cid": cid]
        )
        guard let subtitle = data.dict("subtitle") else { return [] }
        return subtitle.dictionaries("subtitles").compactMap { raw in
            let url = Self.urlString(raw.string("subtitle_url"))
            guard !url.isEmpty else { return nil }
            return SubtitleTrack(
                id: raw.string("id_str").isEmpty ? url : raw.string("id_str"),
                language: raw.string("lan"),
                languageLabel: raw.string("lan_doc"),
                url: url
            )
        }
    }

    func subtitleLines(url: String) async throws -> [LyricLine] {
        guard let parsed = URL(string: url) else { return [] }
        let data = try await client.fetchData(url: parsed)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let body = root["body"] as? [Any]
        else { return [] }
        return body.enumerated().compactMap { index, raw in
            guard let line = raw as? [String: Any] else { return nil }
            let text = line.string("content").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return LyricLine(id: index, time: line.double("from"), text: text)
        }
        .sorted { $0.time < $1.time }
    }

    /// 在线歌词检索：B 站字幕之外默认提供网易云与 LRCLIB 两个来源。
    /// B 站投稿标题往往带装饰词，先清洗出真正歌名，再逐个候选查询。
    func searchLyrics(title: String, artist: String, duration: Int) async -> Lyrics? {
        let queries = Self.lyricQueryCandidates(title: title, artist: artist)
        for (track, performer) in queries {
            if let found = await netEaseLyrics(track: track, artist: performer, duration: duration) {
                return found
            }
        }
        for (track, performer) in queries {
            if let found = await lrclibLyrics(track: track, artist: performer, duration: duration) {
                return found
            }
        }
        return nil
    }

    /// 网易云音乐公开接口：搜索拿候选，再按时长与歌名挑最接近的一条取 LRC。
    private func netEaseLyrics(track: String, artist: String, duration: Int) async -> Lyrics? {
        guard !track.isEmpty else { return nil }
        var components = URLComponents(string: "https://music.163.com/api/search/get/web")!
        components.queryItems = [
            URLQueryItem(name: "s", value: track),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url else { return nil }
        let songs: [[String: Any]]
        do {
            let data = try await client.fetchData(url: url, referer: URL(string: "https://music.163.com/")!)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let root = object as? [String: Any],
                  let result = root.dict("result")
            else { return nil }
            songs = result.dictionaries("songs")
        } catch {
            return nil
        }

        let scored = songs.compactMap { song -> (score: Int, id: Int)? in
            let id = song.int("id")
            guard id != 0 else { return nil }
            let name = song.string("name")
            var score = 0
            // 时长接近的优先（网易云是毫秒，视频是秒）。
            let songDuration = song.int("duration") / 1000
            if duration > 0, songDuration > 0 {
                let gap = abs(songDuration - duration)
                if gap <= 5 { score += 8 } else if gap <= 15 { score += 5 } else if gap > 45 { score -= 4 }
            }
            if !track.isEmpty, Self.normalizedText(name).contains(Self.normalizedText(track)) { score += 4 }
            if !artist.isEmpty {
                let names = song.array("artists")?
                    .compactMap { ($0 as? [String: Any])?.string("name") } ?? []
                if names.contains(where: { Self.normalizedText($0).contains(Self.normalizedText(artist)) }) {
                    score += 2
                }
            }
            return (score, id)
        }
        .sorted { $0.score > $1.score }

        for candidate in scored.prefix(3) {
            var lyricComponents = URLComponents(string: "https://music.163.com/api/song/lyric")!
            lyricComponents.queryItems = [
                URLQueryItem(name: "id", value: String(candidate.id)),
                URLQueryItem(name: "lv", value: "1"),
                URLQueryItem(name: "kv", value: "1"),
                URLQueryItem(name: "tv", value: "-1")
            ]
            guard let lyricURL = lyricComponents.url else { continue }
            do {
                let data = try await client.fetchData(
                    url: lyricURL,
                    referer: URL(string: "https://music.163.com/")!
                )
                let object = try JSONSerialization.jsonObject(with: data)
                guard let root = object as? [String: Any] else { continue }
                let raw = root.dict("lrc")?.string("lyric") ?? ""
                let lines = Self.parseLRC(raw)
                guard !lines.isEmpty else { continue }
                return Lyrics(lines: lines, source: "网易云", isSynced: true)
            } catch {
                continue
            }
        }
        return nil
    }

    /// LRCLIB：免费无钥歌词库。投稿者名常常不是歌手，因此带与不带
    /// artist 各查一次。
    private func lrclibLyrics(track: String, artist: String, duration: Int) async -> Lyrics? {
        guard !track.isEmpty else { return nil }
        let queries: [(String, String)] = [
            (track, artist),
            (track, "")
        ]
        for (candidate, performer) in queries {
            var components = URLComponents(string: "https://lrclib.net/api/search")!
            var items = [URLQueryItem(name: "track_name", value: candidate)]
            if !performer.isEmpty, performer != "未知创作者" {
                items.append(URLQueryItem(name: "artist_name", value: performer))
            }
            components.queryItems = items
            guard let url = components.url else { continue }
            do {
                let data = try await client.fetchData(
                    url: url,
                    referer: URL(string: "https://lrclib.net")!
                )
                let object = try JSONSerialization.jsonObject(with: data)
                let rows = object as? [[String: Any]] ?? []
                let scored = rows.compactMap { row -> (Int, Lyrics)? in
                    let synced = row.string("syncedLyrics")
                    let plain = row.string("plainLyrics")
                    guard !synced.isEmpty || !plain.isEmpty else { return nil }
                    let rowDuration = row.int("duration")
                    var score = 0
                    if !synced.isEmpty { score += 10 }
                    if duration > 0 && rowDuration > 0 {
                        score += max(0, 6 - abs(rowDuration - duration) / 8)
                    }
                    let lines = synced.isEmpty
                        ? Self.plainLyrics(plain)
                        : Self.parseLRC(synced)
                    guard !lines.isEmpty else { return nil }
                    return (score, Lyrics(
                        lines: lines,
                        source: "LRCLIB",
                        isSynced: !synced.isEmpty
                    ))
                }
                if let best = scored.max(by: { $0.0 < $1.0 })?.1 {
                    return best
                }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Favourites

    func createdFolders(mid: Int64) async throws -> [FavoriteFolder] {
        let data = try await client.data(
            path: "/x/v3/fav/folder/created/list-all",
            query: ["up_mid": String(mid)]
        )
        return data.dictionaries("list").compactMap { raw in
            guard raw.int64("id") > 0 else { return nil }
            return FavoriteFolder(
                id: raw.int64("id"),
                title: raw.string("title"),
                coverURL: Self.imageURL(raw.string("cover")),
                mediaCount: raw.int("media_count"),
                isCollected: false,
                ownerName: ""
            )
        }
    }

    func collectedFolders(mid: Int64) async throws -> [FavoriteFolder] {
        let data = try await client.data(
            path: "/x/v3/fav/folder/collected/list",
            query: [
                "up_mid": String(mid),
                "ps": "50",
                "pn": "1",
                "platform": "web"
            ]
        )
        return data.dictionaries("list").compactMap { raw in
            guard raw.int64("id") > 0 else { return nil }
            let upper = raw.dict("upper")
            return FavoriteFolder(
                id: raw.int64("id"),
                title: raw.string("title"),
                coverURL: Self.imageURL(raw.string("cover")),
                mediaCount: raw.int("media_count"),
                isCollected: true,
                ownerName: upper?.string("name") ?? ""
            )
        }
    }

    func folderPage(mediaID: Int64, page: Int = 1, pageSize: Int = 20) async throws -> FavoritePage {
        let envelope = try await client.envelope(
            path: "/x/v3/fav/resource/list",
            query: [
                "media_id": String(mediaID),
                "platform": "web",
                "pn": String(max(1, page)),
                "ps": String(max(1, pageSize))
            ]
        )
        guard let data = envelope["data"] as? [String: Any] else {
            return FavoritePage(title: "", coverURL: "", total: 0, tracks: [], hasMore: false)
        }
        let info = data.dict("info") ?? [:]
        let tracks = data.dictionaries("medias").compactMap { raw -> Track? in
            let type = raw.int("type")
            let attr = raw.int("attr")
            guard (type == 2 || type == 12), attr == 0 else { return nil }
            let bvid = raw.string("bvid").isEmpty ? raw.string("bv_id") : raw.string("bvid")
            guard !bvid.isEmpty else { return nil }
            let upper = raw.dict("upper")
            return Track(
                bvid: bvid,
                title: raw.string("title"),
                artist: Artist(
                    mid: upper?.int64("mid") ?? 0,
                    name: upper?.string("name") ?? "",
                    avatarURL: Self.imageURL(upper?.string("face") ?? "")
                ),
                album: info.string("title"),
                coverURL: Self.imageURL(raw.string("cover")),
                duration: raw.int("duration"),
                origin: .favorites
            )
        }
        return FavoritePage(
            title: info.string("title"),
            coverURL: Self.imageURL(info.string("cover")),
            total: info.int("media_count"),
            tracks: tracks,
            hasMore: data.bool("has_more")
        )
    }

    // MARK: - Artist

    func artistInfo(mid: Int64) async throws -> Artist {
        let data = try await client.data(
            path: "/x/space/wbi/acc/info",
            query: ["mid": String(mid)],
            signed: true
        )
        guard !data.isEmpty else { throw BiliError.unavailable("无法获取 UP 主信息") }
        return Artist(
            mid: data.int64("mid"),
            name: data.string("name"),
            avatarURL: Self.imageURL(data.string("face"))
        )
    }

    func artistVideos(mid: Int64, page: Int = 1, pageSize: Int = 30) async throws -> (tracks: [Track], total: Int) {
        let data = try await client.data(
            path: "/x/space/wbi/arc/search",
            query: [
                "mid": String(mid),
                "order": "pubdate",
                "pn": String(max(1, page)),
                "ps": String(max(1, pageSize)),
                "tid": "0",
                "platform": "web"
            ],
            signed: true
        )
        let list = data.dict("list") ?? [:]
        let tracks = list.dictionaries("vlist").compactMap { raw -> Track? in
            let bvid = raw.string("bvid")
            guard !bvid.isEmpty else { return nil }
            let length = raw.string("length")
            return Track(
                bvid: bvid,
                title: raw.string("title"),
                artist: Artist(mid: mid, name: raw.string("author"), avatarURL: ""),
                album: "投稿",
                coverURL: Self.imageURL(raw.string("pic")),
                duration: TextCleaner.durationSeconds(length),
                publishedAt: Date(timeIntervalSince1970: TimeInterval(raw.int("created"))),
                playCount: raw.int("play"),
                danmakuCount: raw.int("video_review"),
                origin: .artist
            )
        }
        return (tracks, data.dict("page")?.int("count") ?? 0)
    }

    // MARK: - QR login

    func qrGenerate() async throws -> QRLoginTicket {
        let data = try await client.data(
            path: "/x/passport-login/web/qrcode/generate",
            base: BiliClient.passportBase
        )
        let url = data.string("url")
        let key = data.string("qrcode_key")
        guard !url.isEmpty, !key.isEmpty else {
            throw BiliError.parse("二维码生成失败")
        }
        return QRLoginTicket(url: url, key: key)
    }

    func qrPoll(key: String) async throws -> (status: QRLoginStatus, refreshToken: String) {
        let data = try await client.data(
            path: "/x/passport-login/web/qrcode/poll",
            base: BiliClient.passportBase,
            query: ["qrcode_key": key]
        )
        let code = data.int("code")
        let status: QRLoginStatus
        switch code {
        case 86101: status = .waiting
        case 86090: status = .scanned
        case 0: status = .success
        case 86038: status = .expired
        default: status = .unknown
        }
        let refresh = data.string("refresh_token")
        if !refresh.isEmpty {
            jar.storeRefreshToken(refresh)
        }
        return (status, refresh)
    }

    // MARK: - Parsing helpers

    static let musicCategoryIDs: Set<Int> = [3, 28, 29, 30, 31, 59, 130, 193, 243, 244, 265, 266, 267]

    static func imageURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("//") { return "https:" + trimmed }
        if trimmed.hasPrefix("http://") {
            return "https://" + trimmed.dropFirst("http://".count)
        }
        return trimmed
    }

    static func urlString(_ raw: String) -> String {
        if raw.hasPrefix("//") { return "https:" + raw }
        return raw
    }

    static func baseURL(of stream: [String: Any]) -> String {
        stream.string("baseUrl").isEmpty ? stream.string("base_url") : stream.string("baseUrl")
    }

    static func streamList(_ raw: Any?) -> [[String: Any]] {
        if let dict = raw as? [String: Any] { return [dict] }
        if let rows = raw as? [Any] {
            return rows.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    static func artistFromCard(_ json: [String: Any]) -> Artist {
        if let owner = json["owner"] as? [String: Any] {
            return Artist(
                mid: owner.int64("mid"),
                name: owner.string("name"),
                avatarURL: imageURL(owner.string("face"))
            )
        }
        if let author = json["author"] as? [String: Any] {
            return Artist(
                mid: author.int64("mid"),
                name: author.string("name"),
                avatarURL: imageURL(json.string("upic"))
            )
        }
        return Artist(
            mid: json.int64("mid"),
            name: json.string("author"),
            avatarURL: imageURL(json.string("upic"))
        )
    }

    static func trackFromCard(_ json: [String: Any], origin: TrackOrigin) -> Track? {
        let bvid = json.string("bvid").isEmpty ? json.string("bv_id") : json.string("bvid")
        guard !bvid.isEmpty else { return nil }
        let stat = json.dict("stat") ?? [:]
        let cid = json.int("cid") > 0 ? String(json.int("cid")) : ""
        let pubdate = json.int("pubdate")
        return Track(
            bvid: bvid,
            cid: cid,
            title: TextCleaner.searchTitle(json.string("title")),
            artist: artistFromCard(json),
            album: json.string("tname"),
            coverURL: imageURL(json.string("pic").isEmpty ? json.string("cover") : json.string("pic")),
            duration: json.int("duration"),
            publishedAt: pubdate > 0 ? Date(timeIntervalSince1970: TimeInterval(pubdate)) : nil,
            playCount: stat.int("view").nonzero ?? json.int("play"),
            danmakuCount: stat.int("danmaku"),
            likeCount: stat.int("like"),
            origin: origin
        )
    }

    static func trackFromView(_ data: [String: Any]) -> Track {
        let owner = data.dict("owner") ?? [:]
        let pages = data.dictionaries("pages").map { raw in
            VideoPage(
                cid: String(raw.int("cid")),
                title: raw.string("part"),
                duration: raw.int("duration"),
                index: raw.int("page")
            )
        }
        let stat = data.dict("stat") ?? [:]
        let pubdate = data.int("pubdate")
        let firstPage = pages.first
        return Track(
            bvid: data.string("bvid"),
            cid: firstPage?.cid ?? "",
            title: data.string("title"),
            artist: Artist(
                mid: owner.int64("mid"),
                name: owner.string("name"),
                avatarURL: imageURL(owner.string("face"))
            ),
            album: data.string("tname"),
            coverURL: imageURL(data.string("pic")),
            duration: data.int("duration") > 0 ? data.int("duration") : (firstPage?.duration ?? 0),
            publishedAt: pubdate > 0 ? Date(timeIntervalSince1970: TimeInterval(pubdate)) : nil,
            playCount: stat.int("view"),
            danmakuCount: stat.int("danmaku"),
            likeCount: stat.int("like"),
            pages: pages,
            origin: .manual
        )
    }

    static func searchItem(from json: [String: Any], kind: SearchKind) -> SearchItem? {
        switch kind {
        case .video:
            let bvid = json.string("bvid")
            guard !bvid.isEmpty else { return nil }
            let pubdate = json.int("pubdate")
            return SearchItem(
                id: bvid,
                kind: .video,
                title: TextCleaner.searchTitle(json.string("title")),
                subtitle: json.string("author"),
                coverURL: imageURL(json.string("pic")),
                artist: Artist(
                    mid: json.int64("mid"),
                    name: json.string("author"),
                    avatarURL: imageURL(json.string("upic"))
                ),
                duration: TextCleaner.durationSeconds(json.string("duration")),
                playCount: json.int("play"),
                publishedAt: pubdate > 0 ? Date(timeIntervalSince1970: TimeInterval(pubdate)) : nil
            )
        case .user:
            let mid = json.int64("mid")
            guard mid > 0 else { return nil }
            let fans = json.int("fans")
            let videos = json.int("videos")
            return SearchItem(
                id: String(mid),
                kind: .user,
                title: TextCleaner.searchTitle(json.string("uname")),
                subtitle: "\(Formatters.compactCount(fans)) 粉丝 · \(Formatters.compactCount(videos)) 投稿",
                coverURL: imageURL(json.string("upic")),
                artist: Artist(
                    mid: mid,
                    name: TextCleaner.searchTitle(json.string("uname")),
                    avatarURL: imageURL(json.string("upic"))
                ),
                duration: 0,
                playCount: fans,
                publishedAt: nil
            )
        case .media:
            let title = TextCleaner.searchTitle(json.string("title"))
            let seasonID = json.string("season_id")
            let mediaID = json.string("media_id")
            guard !title.isEmpty, !seasonID.isEmpty || !mediaID.isEmpty else { return nil }
            return SearchItem(
                id: seasonID.isEmpty ? mediaID : seasonID,
                kind: .media,
                title: title,
                subtitle: json.string("season_type_name").isEmpty
                    ? "影视" : json.string("season_type_name"),
                coverURL: imageURL(json.string("cover")),
                artist: .unknown,
                duration: 0,
                playCount: 0,
                publishedAt: nil
            )
        }
    }

    static func lyricSearchTitle(_ raw: String) -> String {
        var text = raw
        // 装饰性方括号整段去掉：【4K】【无损】【官方MV】
        for pattern in ["【[^】]*】", "\\[[^\\]]*\\]"] {
            text = text.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }
        // 《》「」『』里通常是歌名本身，只去括号保留内容。
        for (open, close) in [("《", "》"), ("「", "」"), ("『", "』")] {
            text = text.replacingOccurrences(of: open, with: " ")
            text = text.replacingOccurrences(of: close, with: " ")
        }
        // 全半角括号里多为版本/音质说明，整段去掉。
        for pattern in ["（[^）]*）", "\\([^)]*\\)"] {
            text = text.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }
        for junk in [
            "完整版", "现场版", "现场", "直拍", "高清", "修复", "收藏",
            "无损", "音质", "纯享", "官方", "全曲", "歌词", "字幕",
            "Live", "MV", "4K", "8K", "1080P", "720P", "60FPS", "HD", "HQ"
        ] {
            text = text.replacingOccurrences(
                of: junk,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 B 站标题里推导歌词查询候选；"歌手 - 歌名" 形式会展开成两种顺序。
    static func lyricQueryCandidates(title: String, artist: String) -> [(String, String)] {
        var results: [(String, String)] = []
        let cleaned = lyricSearchTitle(title)

        if let range = cleaned.range(of: " - ") {
            let left = cleaned[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = cleaned[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !left.isEmpty, !right.isEmpty {
                results.append((right, left))
                results.append((left, right))
            }
        }
        if !cleaned.isEmpty {
            results.append((cleaned, artist))
            results.append((cleaned, ""))
        }
        var seen = Set<String>()
        return results.filter { entry in
            guard !entry.0.isEmpty else { return false }
            let key = Self.normalizedText(entry.0) + "|" + Self.normalizedText(entry.1)
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    static func normalizedText(_ raw: String) -> String {
        raw.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
    }

    static func parseLRC(_ raw: String) -> [LyricLine] {
        let timestampRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")
        var result: [LyricLine] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let regex = timestampRegex else { continue }
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var text = ns
            for match in matches.reversed() {
                text = text.replacingCharacters(in: match.range, with: "") as NSString
            }
            let content = (text as String).trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            for match in matches {
                let minutes = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Int(ns.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let frac = ns.substring(with: match.range(at: 3))
                    fraction = (Double(frac) ?? 0) / pow(10, Double(frac.count))
                }
                let time = Double(minutes * 60 + seconds) + fraction
                result.append(LyricLine(id: result.count, time: time, text: content))
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    static func plainLyrics(_ raw: String) -> [LyricLine] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                LyricLine(id: index, time: Double(index) * 4, text: text)
            }
    }
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}

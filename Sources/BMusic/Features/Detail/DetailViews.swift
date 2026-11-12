#if os(macOS)
import AppKit
import SwiftUI

struct DetailRouterView: View {
    let destination: DetailDestination

    var body: some View {
        switch destination {
        case .liked:
            LikedDetailView()
        case .history:
            HistoryDetailView()
        case .folder(let id, let title):
            FavoriteFolderDetailView(mediaID: id, folderTitle: title)
        case .artist(let mid, let name, let avatar):
            ArtistDetailView(mid: mid, fallbackName: name, fallbackAvatar: avatar)
        case .playlist(let id):
            LocalPlaylistDetailView(playlistID: id)
        }
    }
}

// MARK: - Hero

private struct DetailHero: View {
    let title: String
    let subtitle: String
    let meta: String
    let coverURLs: [String]
    var badge: String?
    var symbol: String?
    var onPlay: () -> Void
    var onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ZStack {
                if let symbol {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accentGradient)
                    Image(systemName: symbol)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    MosaicCover(urls: coverURLs, cornerRadius: 16)
                }
            }
            .frame(width: 164, height: 164)
            .shadow(color: .black.opacity(0.22), radius: 18, y: 9)

            VStack(alignment: .leading, spacing: 7) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(Theme.accent.opacity(0.11), in: Capsule())
                }
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button(action: onShuffle) {
                        Label("随机播放", systemImage: "shuffle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

private struct TrackList: View {
    let tracks: [Track]
    let source: String
    var onDelete: ((Track) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.queueKey) { index, track in
                TrackRow(
                    track: track,
                    index: index + 1,
                    source: source,
                    showCover: true,
                    showAlbum: false,
                    onDelete: onDelete.map { delete in { delete(track) } }
                )
            }
        }
    }
}

// MARK: - Liked

private struct LikedDetailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                DetailHero(
                    title: "我喜欢的音乐",
                    subtitle: "把心动的声音留在这里",
                    meta: "\(state.library.likedTracks.count) 首歌曲 · 仅保存在本机",
                    coverURLs: [],
                    badge: "收藏",
                    symbol: "heart.fill",
                    onPlay: {
                        state.play(state.library.likedTracks, startingAt: 0, source: "我喜欢的音乐")
                    },
                    onShuffle: {
                        guard !state.library.likedTracks.isEmpty else { return }
                        state.settings.shuffle = true
                        let index = Int.random(in: 0..<state.library.likedTracks.count)
                        state.play(state.library.likedTracks, startingAt: index, source: "我喜欢的音乐")
                    }
                )

                if state.library.likedTracks.isEmpty {
                    EmptyStateView(
                        symbol: "heart",
                        title: "还没有收藏的音乐",
                        message: "在歌曲上点右键，或者点击播放器上的爱心即可收藏。",
                        actionTitle: "去推荐逛逛"
                    ) {
                        state.select(.home)
                    }
                } else {
                    TrackList(tracks: state.library.likedTracks, source: "我喜欢的音乐")
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.bottom, 110)
        }
    }
}

// MARK: - History

private struct HistoryDetailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                DetailHero(
                    title: "最近播放",
                    subtitle: "最近听过的音乐，按时间倒序排列",
                    meta: "\(state.library.history.count) 条记录",
                    coverURLs: Array(state.library.recentlyPlayed.prefix(4).map(\.coverURL)),
                    badge: "历史",
                    onPlay: {
                        state.play(state.library.recentlyPlayed, startingAt: 0, source: "最近播放")
                    },
                    onShuffle: {
                        let tracks = state.library.recentlyPlayed
                        guard !tracks.isEmpty else { return }
                        state.settings.shuffle = true
                        state.play(tracks, startingAt: Int.random(in: 0..<tracks.count), source: "最近播放")
                    }
                )

                if !state.library.history.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            state.library.clearHistory()
                            ToastCenter.shared.show("已清空播放记录")
                        } label: {
                            Label("清空记录", systemImage: "trash")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                if state.library.history.isEmpty {
                    EmptyStateView(
                        symbol: "clock",
                        title: "暂无播放记录",
                        message: "播放过的音乐会出现在这里。",
                        actionTitle: "去推荐看看"
                    ) {
                        state.select(.home)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(state.library.history.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 0) {
                                TrackRow(
                                    track: entry.track,
                                    index: index + 1,
                                    source: "最近播放",
                                    showCover: true,
                                    showAlbum: false
                                )
                                Text(Formatters.relativeDate(entry.playedAt))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 68, alignment: .trailing)
                                    .padding(.trailing, 10)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.bottom, 110)
        }
    }
}

// MARK: - Remote favourite folder

private struct FavoriteFolderDetailView: View {
    let mediaID: Int64
    let folderTitle: String

    @EnvironmentObject private var state: AppState
    @State private var tracks: [Track] = []
    @State private var coverURL = ""
    @State private var total = 0
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                DetailHero(
                    title: folderTitle,
                    subtitle: "来自哔哩哔哩收藏夹",
                    meta: total > 0 ? "\(total) 个视频" : "",
                    coverURLs: coverURL.isEmpty ? Array(tracks.prefix(4).map(\.coverURL)) : [coverURL],
                    badge: "B站收藏夹",
                    onPlay: {
                        state.play(tracks, startingAt: 0, source: folderTitle)
                    },
                    onShuffle: {
                        guard !tracks.isEmpty else { return }
                        state.settings.shuffle = true
                        state.play(tracks, startingAt: Int.random(in: 0..<tracks.count), source: folderTitle)
                    }
                )

                if isLoading && tracks.isEmpty {
                    LoadingRows(count: 8)
                } else if let errorText, tracks.isEmpty {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "收藏夹加载失败",
                        message: errorText,
                        actionTitle: "重试"
                    ) {
                        Task { await load(reset: true) }
                    }
                } else if tracks.isEmpty {
                    EmptyStateView(
                        symbol: "rectangle.stack",
                        title: "收藏夹是空的",
                        message: "在 B 站收藏音乐视频后，它们会出现在这里。"
                    )
                } else {
                    TrackList(tracks: tracks, source: folderTitle)
                    if hasMore {
                        loadMoreButton
                    }
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.bottom, 110)
        }
        .task { await load(reset: true) }
        .onReceive(NotificationCenter.default.publisher(for: .bmusicRefreshContent)) { _ in
            Task { await load(reset: true) }
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await load(reset: false) }
        } label: {
            HStack(spacing: 6) {
                if isLoading { ProgressView().controlSize(.mini) }
                Text(isLoading ? "加载中…" : "加载更多")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(isLoading)
        .padding(.top, 8)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        if reset {
            page = 1
            tracks = []
        }
        do {
            let result = try await state.api.folderPage(mediaID: mediaID, page: page)
            coverURL = result.coverURL
            total = result.total
            if reset {
                tracks = result.tracks
            } else {
                let existing = Set(tracks.map(\.queueKey))
                tracks.append(contentsOf: result.tracks.filter { !existing.contains($0.queueKey) })
            }
            hasMore = result.hasMore
            if result.hasMore { page += 1 }
        } catch {
            if tracks.isEmpty { errorText = error.localizedDescription }
        }
        isLoading = false
    }
}

// MARK: - Artist

private struct ArtistDetailView: View {
    let mid: Int64
    let fallbackName: String
    let fallbackAvatar: String

    @EnvironmentObject private var state: AppState
    @State private var artist: Artist?
    @State private var tracks: [Track] = []
    @State private var total = 0
    @State private var page = 1
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header

                if isLoading && tracks.isEmpty {
                    LoadingRows(count: 8)
                } else if let errorText, tracks.isEmpty {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "投稿加载失败",
                        message: errorText,
                        actionTitle: "重试"
                    ) {
                        Task { await load(reset: true) }
                    }
                } else if tracks.isEmpty {
                    EmptyStateView(symbol: "music.note.list", title: "还没有投稿")
                } else {
                    TrackList(tracks: tracks, source: displayName)
                    if tracks.count < total {
                        Button {
                            Task { await load(reset: false) }
                        } label: {
                            HStack(spacing: 6) {
                                if isLoading { ProgressView().controlSize(.mini) }
                                Text(isLoading ? "加载中…" : "加载更多")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isLoading)
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.bottom, 110)
        }
        .task { await load(reset: true) }
    }

    private var displayName: String {
        artist?.name ?? fallbackName
    }

    private var avatarURL: String {
        let url = artist?.avatarURL ?? fallbackAvatar
        return url
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 22) {
            CachedAsyncImage(url: avatarURL)
                .frame(width: 154, height: 154)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 9)

            VStack(alignment: .leading, spacing: 7) {
                Text("UP 主")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Theme.accent.opacity(0.11), in: Capsule())
                Text(displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("哔哩哔哩音乐创作者")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(total) 个投稿")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 10) {
                    Button {
                        state.play(tracks, startingAt: 0, source: displayName)
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(tracks.isEmpty)
                    if let url = artist?.profileURL, mid > 0 {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("空间主页", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        if reset {
            page = 1
            tracks = []
        }
        do {
            if artist == nil {
                artist = try? await state.api.artistInfo(mid: mid)
            }
            let result = try await state.api.artistVideos(mid: mid, page: page)
            if reset {
                tracks = result.tracks
            } else {
                let existing = Set(tracks.map(\.queueKey))
                tracks.append(contentsOf: result.tracks.filter { !existing.contains($0.queueKey) })
            }
            total = result.total
            page += 1
        } catch {
            if tracks.isEmpty { errorText = error.localizedDescription }
        }
        isLoading = false
    }
}

// MARK: - Local playlist

private struct LocalPlaylistDetailView: View {
    let playlistID: UUID

    @EnvironmentObject private var state: AppState

    private var playlist: LocalPlaylist? {
        state.library.playlist(playlistID)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let playlist {
                    DetailHero(
                        title: playlist.name,
                        subtitle: "本地歌单 · 只在你的 Mac 上",
                        meta: "\(playlist.tracks.count) 首歌曲",
                        coverURLs: playlist.tracks.prefix(4).map(\.coverURL),
                        badge: "自建歌单",
                        onPlay: {
                            state.play(playlist.tracks, startingAt: 0, source: playlist.name)
                        },
                        onShuffle: {
                            guard !playlist.tracks.isEmpty else { return }
                            state.settings.shuffle = true
                            state.play(
                                playlist.tracks,
                                startingAt: Int.random(in: 0..<playlist.tracks.count),
                                source: playlist.name
                            )
                        }
                    )

                    if playlist.tracks.isEmpty {
                        EmptyStateView(
                            symbol: "music.note.list",
                            title: "歌单里还没有音乐",
                            message: "在歌曲右键菜单里选择「添加到歌单」即可。",
                            actionTitle: "去推荐看看"
                        ) {
                            state.select(.home)
                        }
                    } else {
                        TrackList(tracks: playlist.tracks, source: playlist.name) { track in
                            state.library.remove(track, from: playlist.id)
                            ToastCenter.shared.show("已从歌单移除")
                        }
                    }
                } else {
                    EmptyStateView(
                        symbol: "questionmark.folder",
                        title: "歌单不存在",
                        message: "它可能已经被删除。"
                    )
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.bottom, 110)
        }
    }
}
#endif

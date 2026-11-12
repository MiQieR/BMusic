#if os(iOS)
import SwiftUI

private struct IOSTrackCollection: View {
    let title: String
    var subtitle: String?
    let tracks: [Track]
    var loading = false
    var errorText: String?
    var onRefresh: (() -> Void)?

    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    if let first = tracks.first {
                        CoverArt(url: first.coverURL, cornerRadius: 13)
                            .frame(width: 76, height: 76)
                            .shadow(color: .black.opacity(0.16), radius: 9, y: 4)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        Text(subtitle ?? "\(tracks.count) 首歌曲")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        if !tracks.isEmpty {
                            Button {
                                state.playAll(tracks, source: title)
                            } label: {
                                Label("播放全部", systemImage: "play.fill")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .controlSize(.small)
                            .padding(.top, 2)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                if loading {
                    IOSLoadingRows(count: 8)
                } else if let errorText {
                    IOSEmptyState(
                        symbol: "exclamationmark.circle",
                        title: "加载失败",
                        message: errorText,
                        actionTitle: "重试",
                        action: onRefresh
                    )
                } else if tracks.isEmpty {
                    IOSEmptyState(symbol: "music.note", title: "这里还没有歌曲")
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.queueKey) { index, track in
                        IOSTrackRow(track: track, index: index + 1)
                        if index < tracks.count - 1 {
                            Divider().opacity(0.35).padding(.leading, 58)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 130)
        }
        .background(IOSBackdrop())
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IOSLikedView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        IOSTrackCollection(
            title: "我喜欢的音乐",
            subtitle: "\(state.library.likedTracks.count) 首",
            tracks: state.library.likedTracks
        )
    }
}

struct IOSHistoryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        IOSTrackCollection(
            title: "最近播放",
            subtitle: "\(state.library.history.count) 条记录",
            tracks: state.library.history.map(\.track)
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空") { state.library.clearHistory() }
                    .foregroundStyle(.secondary)
                    .disabled(state.library.history.isEmpty)
            }
        }
    }
}

struct IOSPlaylistView: View {
    let playlistID: UUID
    @EnvironmentObject private var state: AppState

    private var playlist: LocalPlaylist? { state.library.playlist(playlistID) }

    var body: some View {
        IOSTrackCollection(
            title: playlist?.name ?? "歌单",
            subtitle: "\(playlist?.tracks.count ?? 0) 首歌曲",
            tracks: playlist?.tracks ?? []
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let playlist {
                    Menu {
                        Button("播放全部") { state.playAll(playlist.tracks, source: playlist.name) }
                        Button("删除歌单", role: .destructive) {
                            state.library.deletePlaylist(playlist.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

struct IOSFolderView: View {
    let folder: FavoriteFolder
    @EnvironmentObject private var state: AppState
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        IOSTrackCollection(
            title: folder.title,
            subtitle: "\(max(folder.mediaCount, tracks.count)) 个视频",
            tracks: tracks,
            loading: loading,
            errorText: errorText,
            onRefresh: { Task { await load() } }
        )
        .task { await load() }
    }

    private func load() async {
        guard tracks.isEmpty else { return }
        loading = true
        errorText = nil
        do {
            tracks = try await state.api.folderPage(mediaID: folder.id, pageSize: 100).tracks
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

struct IOSArtistView: View {
    let artist: Artist
    @EnvironmentObject private var state: AppState
    @State private var profile: Artist
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var errorText: String?

    init(artist: Artist) {
        self.artist = artist
        _profile = State(initialValue: artist)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    CachedAsyncImage(url: profile.avatarURL)
                        .frame(width: 74, height: 74)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        Text("哔哩哔哩音乐创作者")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 4)

                if loading {
                    IOSLoadingRows(count: 8)
                } else if let errorText {
                    IOSEmptyState(symbol: "person.crop.circle.badge.exclamationmark", title: "加载失败", message: errorText)
                } else if tracks.isEmpty {
                    IOSEmptyState(symbol: "music.note.list", title: "暂无作品")
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.queueKey) { index, track in
                        IOSTrackRow(track: track, index: index + 1)
                        if index < tracks.count - 1 {
                            Divider().opacity(0.35).padding(.leading, 58)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 130)
        }
        .background(IOSBackdrop())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard tracks.isEmpty else { return }
        loading = true
        errorText = nil
        do {
            if artist.mid > 0 {
                profile = try await state.api.artistInfo(mid: artist.mid)
                tracks = try await state.api.artistVideos(mid: artist.mid, pageSize: 50).tracks
            }
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

struct IOSDownloadsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    downloadStat("\(state.downloads.activeCount)", "进行中")
                    downloadStat("\(state.downloads.completedCount)", "已完成")
                    if state.downloads.totalBytes > 0 {
                        downloadStat(Formatters.fileSize(state.downloads.totalBytes), "占用")
                    }
                    Spacer()
                }
                .padding(.vertical, 8)

                if state.downloads.items.isEmpty {
                    IOSEmptyState(
                        symbol: "arrow.down.circle",
                        title: "还没有下载",
                        message: "在歌曲菜单里选择「下载」，即可离线播放。"
                    )
                } else {
                    ForEach(state.downloads.items) { item in
                        HStack(spacing: 11) {
                            CoverArt(url: item.track.coverURL, cornerRadius: 8)
                                .frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.track.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(downloadDetail(item))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(item.state == .failed ? .red : .secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if item.state == .completed {
                                Button {
                                    player.play(item.track, sourceTitle: "本地下载")
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 25))
                                        .foregroundStyle(Theme.accent)
                                }
                                .buttonStyle(.plain)
                            } else if item.state == .downloading || item.state == .queued {
                                Text("\(Int(item.progress * 100))%")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 5)
                        .contextMenu {
                            if item.state == .failed {
                                Button("重试") { state.downloads.retry(id: item.id, api: state.api) }
                            }
                            Button("删除", role: .destructive) { state.downloads.remove(id: item.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 130)
        }
        .background(IOSBackdrop())
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func downloadStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func downloadDetail(_ item: DownloadItem) -> String {
        switch item.state {
        case .queued: return "等待下载"
        case .downloading: return "正在下载 \(Int(item.progress * 100))%"
        case .completed: return "\(item.quality.badge) · \(Formatters.fileSize(item.bytes))"
        case .failed: return item.message ?? "下载失败"
        }
    }
}
#endif

#if os(iOS)
import SwiftUI

struct IOSLibraryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileCard
                quickGrid
                playlistsSection
                foldersSection
                if !state.library.history.isEmpty {
                    historySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 130)
        }
        .background(IOSBackdrop())
        .navigationTitle("音乐库")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("新建歌单") { showCreate = true }
                    Button("设置") { state.showSettings = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("新建歌单", isPresented: $showCreate) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                state.createPlaylist(named: name)
                newName = ""
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 13) {
            if let account = state.account {
                if !account.avatarURL.isEmpty {
                    CachedAsyncImage(url: account.avatarURL)
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Theme.accent.opacity(0.16))
                        .frame(width: 54, height: 54)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.accent))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(account.sign.isEmpty ? "欢迎回到 BMusic" : account.sign)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 9) {
                        stat("\(account.following)", "关注")
                        stat("\(account.follower)", "粉丝")
                        stat("Lv.\(account.level)", "等级")
                    }
                }
                Spacer()
                Button("设置") { state.showSettings = true }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("登录哔哩哔哩")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("同步收藏夹、关注动态和云端歌单")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("扫码登录") { state.showLogin = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
            }
        }
        .padding(15)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.system(size: 10.5, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var quickGrid: some View {
        HStack(spacing: 11) {
            quickCard(symbol: "heart.fill", title: "喜欢", detail: "\(state.library.likedTracks.count) 首", tint: Theme.accent) {
                IOSLikedView()
            }
            quickCard(symbol: "clock.arrow.circlepath", title: "最近", detail: "\(state.library.history.count) 首", tint: Theme.blue) {
                IOSHistoryView()
            }
            quickCard(symbol: "arrow.down.circle.fill", title: "下载", detail: "\(state.downloads.completedCount) 首", tint: Theme.mint) {
                IOSDownloadsView()
            }
        }
    }

    private func quickCard<Destination: View>(
        symbol: String, title: String, detail: String, tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.095), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            IOSSectionHeader(
                title: "我的歌单",
                subtitle: state.library.playlists.isEmpty ? "还没有创建歌单" : "\(state.library.playlists.count) 个歌单",
                actionTitle: "新建"
            ) { showCreate = true }

            if state.library.playlists.isEmpty {
                Button {
                    showCreate = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("创建第一个歌单")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(state.library.playlists) { playlist in
                    NavigationLink(destination: IOSPlaylistView(playlistID: playlist.id)) {
                        HStack(spacing: 11) {
                            MosaicCover(urls: playlist.tracks.prefix(4).map(\.coverURL), cornerRadius: 9)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("\(playlist.tracks.count) 首歌曲")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            IOSSectionHeader(title: "B站收藏夹", subtitle: state.account == nil ? "登录后同步" : "\(state.favoriteFolders.count) 个收藏夹")
            if state.account == nil {
                Button {
                    state.showLogin = true
                } label: {
                    HStack {
                        Image(systemName: "person.badge.key")
                            .foregroundStyle(Theme.accent)
                        Text("登录以同步收藏夹")
                            .font(.system(size: 12.5))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            } else if state.isLoadingFolders && state.favoriteFolders.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else {
                ForEach(state.favoriteFolders) { folder in
                    NavigationLink(destination: IOSFolderView(folder: folder)) {
                        HStack(spacing: 11) {
                            CoverArt(url: folder.coverURL, cornerRadius: 9)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.title)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(folder.mediaCount) 首")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            IOSSectionHeader(title: "最近播放", actionTitle: "全部") { state.showNowPlaying = true }
            ForEach(Array(state.library.history.prefix(4).enumerated()), id: \.element.id) { index, entry in
                IOSTrackRow(track: entry.track, index: index + 1, showCover: true)
            }
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var state: AppState

    @State private var showNewPlaylist = false
    @State private var newName = ""
    @State private var renameTarget: LocalPlaylist?
    @State private var renameName = ""

    private let columns = [
        GridItem(.adaptive(minimum: 152, maximum: 208), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                featureCards

                if state.account == nil {
                    loginBanner
                }

                localPlaylists
                remoteFolders

                if !state.library.recentlyPlayed.isEmpty {
                    recentSection
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, 6)
            .padding(.bottom, 110)
        }
        .alert("新建歌单", isPresented: $showNewPlaylist) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                state.createPlaylist(named: newName)
                newName = ""
            }
        }
        .alert(
            "重命名歌单",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("歌单名称", text: $renameName)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let target = renameTarget {
                    state.library.renamePlaylist(target.id, to: renameName)
                }
                renameTarget = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bmusicRefreshContent)) { _ in
            Task { await state.loadFavoriteFolders() }
        }
    }

    // MARK: - Feature cards

    private var featureCards: some View {
        HStack(spacing: 16) {
            LibraryFeatureCard(
                symbol: "heart.fill",
                title: "我喜欢的音乐",
                subtitle: "\(state.library.likedTracks.count) 首歌曲",
                colors: [Color(hex: 0xFB7299), Color(hex: 0xE5487C)]
            ) {
                state.open(.liked)
            }
            LibraryFeatureCard(
                symbol: "clock.fill",
                title: "最近播放",
                subtitle: "\(state.library.history.count) 条记录",
                colors: [Color(hex: 0x8E9BFF), Color(hex: 0x6C7BFF)]
            ) {
                state.open(.history)
            }
            LibraryFeatureCard(
                symbol: "arrow.down.circle.fill",
                title: "本地下载",
                subtitle: "\(state.downloads.completedCount) 首 · \(Formatters.fileSize(state.downloads.totalBytes))",
                colors: [Color(hex: 0x5AC8B0), Color(hex: 0x2FA98F)]
            ) {
                state.select(.downloads)
            }
        }
    }

    private var loginBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("登录后同步 B 站收藏夹")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("扫码登录，只会读取你的公开收藏与账号信息。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("扫码登录") { state.showLogin = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.accent.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: - Playlists

    private var localPlaylists: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "自建歌单", subtitle: "保存在这台 Mac 上") {
                Button {
                    showNewPlaylist = true
                } label: {
                    Label("新建歌单", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if state.library.playlists.isEmpty {
                Button {
                    showNewPlaylist = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18, weight: .light))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("创建第一个歌单")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("把喜欢的音乐整理到一起")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.primary.opacity(0.78))
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(state.library.playlists) { playlist in
                        PlaylistCard(
                            title: playlist.name,
                            subtitle: "\(playlist.tracks.count) 首歌曲",
                            urls: playlist.tracks.prefix(4).map(\.coverURL),
                            badge: "本地"
                        ) {
                            state.open(.playlist(id: playlist.id))
                        }
                        .contextMenu {
                            Button("播放") {
                                guard !playlist.tracks.isEmpty else { return }
                                state.play(playlist.tracks, startingAt: 0, source: playlist.name)
                            }
                            Button("重命名") {
                                renameTarget = playlist
                                renameName = playlist.name
                            }
                            Divider()
                            Button("删除歌单", role: .destructive) {
                                state.library.deletePlaylist(playlist.id)
                                ToastCenter.shared.show("已删除歌单")
                            }
                        }
                    }

                    Button {
                        showNewPlaylist = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("新建歌单")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(
                                    Color.primary.opacity(0.12),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var remoteFolders: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "B站收藏夹",
                subtitle: state.account == nil ? "登录后显示" : "共 \(state.favoriteFolders.count) 个收藏夹"
            ) {
                if state.account != nil {
                    Button {
                        Task { await state.loadFavoriteFolders() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(state.isLoadingFolders)
                }
            }

            if state.account == nil {
                Text("登录账号后，这里会显示你在哔哩哔哩创建的收藏夹。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else if state.isLoadingFolders && state.favoriteFolders.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 16)
            } else if state.favoriteFolders.isEmpty {
                EmptyStateView(
                    symbol: "rectangle.stack",
                    title: "还没有收藏夹",
                    message: "在 B 站收藏音乐视频后，它们会出现在这里。"
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(state.favoriteFolders) { folder in
                        PlaylistCard(
                            title: folder.title,
                            subtitle: "\(folder.mediaCount) 个视频",
                            urls: folder.coverURL.isEmpty ? [] : [folder.coverURL],
                            badge: folder.isCollected ? "收藏" : "创建"
                        ) {
                            state.open(.folder(id: folder.id, title: folder.title))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "最近播放", subtitle: "从上次停下的地方继续") {
                Button("全部记录") { state.open(.history) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(Array(state.library.recentlyPlayed.prefix(6))) { track in
                    TrackCard(track: track, source: "最近播放")
                }
            }
        }
    }
}

private struct LibraryFeatureCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let colors: [Color]
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: colors[0].opacity(0.22), radius: 12, y: 5)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.84), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
#endif

#if os(macOS)
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @State private var showNewPlaylist = false
    @State private var playlistName = ""

    var body: some View {
        VStack(spacing: 0) {
            logo
                .padding(.top, 44)
                .padding(.horizontal, 18)
                .padding(.bottom, 22)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    navigation
                    myMusic
                    if !state.favoriteFolders.isEmpty {
                        favoriteFolders
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 8)
            accountCard
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .background {
            ZStack {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
                LinearGradient(
                    colors: [
                        Theme.accent.opacity(0.055),
                        Color.clear,
                        Theme.violet.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .alert("新建歌单", isPresented: $showNewPlaylist) {
            TextField("歌单名称", text: $playlistName)
            Button("取消", role: .cancel) { playlistName = "" }
            Button("创建") {
                state.createPlaylist(named: playlistName)
                playlistName = ""
            }
        } message: {
            Text("歌单只保存在这台 Mac 上。")
        }
    }

    private var logo: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accentGradient)
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .shadow(color: Theme.accent.opacity(0.28), radius: 7, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text("BMusic")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("哔哩哔哩音乐")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SidebarSection.allCases) { section in
                SidebarRow(
                    symbol: state.section == section && state.path.isEmpty
                        ? section.selectedSymbol
                        : section.symbol,
                    title: section.title,
                    isActive: state.section == section && state.path.isEmpty,
                    count: section == .downloads && state.downloads.activeCount > 0
                        ? "\(state.downloads.activeCount)"
                        : nil
                ) {
                    state.select(section)
                }
            }
        }
    }

    private var myMusic: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("我的音乐")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    showNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .help("新建歌单")
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 5)

            SidebarRow(
                symbol: "heart.fill",
                title: "喜欢的音乐",
                isActive: isDestination(.liked),
                count: state.library.likedTracks.isEmpty ? nil : "\(state.library.likedTracks.count)",
                tint: Theme.accent
            ) {
                state.open(.liked)
            }

            SidebarRow(
                symbol: "clock",
                title: "最近播放",
                isActive: isDestination(.history)
            ) {
                state.open(.history)
            }

            ForEach(state.library.playlists) { playlist in
                SidebarRow(
                    symbol: "music.note.list",
                    title: playlist.name,
                    isActive: isDestination(.playlist(id: playlist.id)),
                    count: playlist.tracks.isEmpty ? nil : "\(playlist.tracks.count)"
                ) {
                    state.open(.playlist(id: playlist.id))
                }
            }
        }
    }

    private var favoriteFolders: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("B站收藏夹")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                if state.isLoadingFolders {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 5)

            ForEach(state.favoriteFolders.prefix(4)) { folder in
                SidebarRow(
                    symbol: "rectangle.stack",
                    title: folder.title,
                    isActive: isDestination(.folder(id: folder.id, title: folder.title)),
                    count: folder.mediaCount > 0 ? "\(folder.mediaCount)" : nil
                ) {
                    state.open(.folder(id: folder.id, title: folder.title))
                }
            }
        }
    }

    private var accountCard: some View {
        HStack(spacing: 9) {
            Button {
                if state.account == nil {
                    state.showLogin = true
                }
            } label: {
                HStack(spacing: 9) {
                    if let account = state.account {
                        CachedAsyncImage(url: account.avatarURL)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    } else {
                        ZStack {
                            Circle().fill(Color.primary.opacity(0.08))
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 32, height: 32)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.account?.name ?? "未登录")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(state.account == nil ? "点击登录 B 站账号" : "Lv.\(state.account?.level ?? 0) · 已同步")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            IconButton(symbol: "gearshape", size: 13, help: "设置") {
                state.showSettings = true
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func isDestination(_ destination: DetailDestination) -> Bool {
        state.path.last == destination
    }
}

private struct SidebarRow: View {
    let symbol: String
    let title: String
    var isActive = false
    var count: String?
    var tint: Color?
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 17)
                Text(title)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.78))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text(count)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? Theme.accent.opacity(0.12) : Color.primary.opacity(hovering ? 0.045 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var iconColor: Color {
        if isActive { return tint ?? Theme.accent }
        return tint ?? Color.primary.opacity(0.52)
    }
}
#endif

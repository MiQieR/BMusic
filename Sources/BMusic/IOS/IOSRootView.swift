#if os(iOS)
import SwiftUI

enum IOSTab: String, CaseIterable, Identifiable {
    case home, discover, search, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "推荐"
        case .discover: return "发现"
        case .search: return "搜索"
        case .library: return "音乐库"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "sparkles"
        case .discover: return "chart.line.uptrend.xyaxis"
        case .search: return "magnifyingglass"
        case .library: return "rectangle.stack"
        }
    }
}

struct IOSRootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab: IOSTab = .home

    var body: some View {
        shell
            .safeAreaInset(edge: .bottom) {
                if player.hasCurrentTrack {
                    IOSMiniPlayer()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            .overlay {
                if state.showNowPlaying {
                    IOSPlayerView()
                        .environmentObject(state)
                        .environmentObject(player)
                        .transition(.move(edge: .bottom))
                        .zIndex(20)
                }
            }
            .sheet(isPresented: $state.showSettings) {
                IOSSettingsView()
                    .environmentObject(state)
            }
            .sheet(isPresented: $state.showLogin) {
                IOSLoginView()
                    .environmentObject(state)
            }
            .task { await state.bootstrap() }
    }

    @ViewBuilder
    private var shell: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 248)
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
                content(for: tab)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemBackground))
        } else {
            tabs
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("BMusic")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ForEach(IOSTab.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { tab = item }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 22)
                        Text(item.title)
                            .font(.system(size: 14, weight: tab == item ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(tab == item ? Theme.accent : Color.primary.opacity(0.78))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        tab == item ? Theme.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 16)
            Divider().padding(.horizontal, 14)
            Button {
                if state.account == nil { state.showLogin = true }
                else { state.showSettings = true }
            } label: {
                HStack(spacing: 10) {
                    if let account = state.account, !account.avatarURL.isEmpty {
                        CachedAsyncImage(url: account.avatarURL)
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.accent.opacity(0.8))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.account?.name ?? "未登录")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(state.account == nil ? "点击登录" : "查看账户")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                state.showSettings = true
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 22)
                    Text("设置")
                        .font(.system(size: 14, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(0.78))
            .padding(.bottom, 12)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func content(for item: IOSTab) -> some View {
        switch item {
        case .home: NavigationStack { IOSHomeView() }
        case .discover: NavigationStack { IOSDiscoverView() }
        case .search: NavigationStack { IOSSearchView() }
        case .library: NavigationStack { IOSLibraryView() }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack { IOSHomeView() }
                .tabItem { Label(IOSTab.home.title, systemImage: IOSTab.home.symbol) }
                .tag(IOSTab.home)
            NavigationStack { IOSDiscoverView() }
                .tabItem { Label(IOSTab.discover.title, systemImage: IOSTab.discover.symbol) }
                .tag(IOSTab.discover)
            NavigationStack { IOSSearchView() }
                .tabItem { Label(IOSTab.search.title, systemImage: IOSTab.search.symbol) }
                .tag(IOSTab.search)
            NavigationStack { IOSLibraryView() }
                .tabItem { Label(IOSTab.library.title, systemImage: IOSTab.library.symbol) }
                .tag(IOSTab.library)
        }
    }
}

#endif

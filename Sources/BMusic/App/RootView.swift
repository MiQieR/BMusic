#if os(macOS)
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var toast = ToastCenter.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            AmbientBackdrop()

            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: Theme.sidebarWidth)
                Rectangle()
                    .fill(Color.primary.opacity(0.065))
                    .frame(width: 1)
                VStack(spacing: 0) {
                    HeaderView()
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if state.player.hasCurrentTrack {
                PlayerBarView(player: state.player)
                    .padding(.leading, Theme.sidebarWidth + 1 + 22)
                    .padding(.trailing, 22)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if state.showNowPlaying {
                NowPlayingView(player: state.player)
                    .transition(.opacity)
                    .zIndex(10)
            }

            if let toast = toast.current {
                VStack {
                    ToastView(message: toast)
                        .padding(.top, 18)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(WindowConfigurator())
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: state.player.hasCurrentTrack)
        .animation(.easeInOut(duration: 0.25), value: state.showNowPlaying)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: toast.current?.id)
        .task { await state.bootstrap() }
        .sheet(isPresented: $state.showLogin) {
            LoginView()
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(state.settings.colorScheme)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bmusicRefresh)) { _ in
            NotificationCenter.default.post(name: .bmusicRefreshContent, object: nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let destination = state.path.last {
                DetailRouterView(destination: destination)
            } else {
                switch state.section {
                case .home:
                    HomeView()
                case .discover:
                    DiscoverView()
                case .search:
                    SearchView()
                case .library:
                    LibraryView()
                case .downloads:
                    DownloadsView()
                }
            }
        }
        .id(contentIdentity)
        .transition(.opacity)
    }

    private var contentIdentity: String {
        if let destination = state.path.last {
            return "detail-\(destination)"
        }
        return "section-\(state.section.rawValue)"
    }
}
#endif

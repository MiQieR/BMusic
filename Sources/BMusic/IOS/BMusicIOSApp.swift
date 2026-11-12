#if os(iOS)
import SwiftUI

@main
struct BMusicIOSApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(state)
                .environmentObject(state.player)
                .environmentObject(state.settings)
                .preferredColorScheme(state.settings.colorScheme)
                .tint(Theme.accent)
        }
    }
}
#endif

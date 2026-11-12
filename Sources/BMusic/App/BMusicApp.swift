#if os(macOS)
import AppKit
import SwiftUI

@main
struct BMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(state.settings.colorScheme)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1220, height: 790)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("播放") {
                Button(state.player.isPlaying ? "暂停" : "播放") {
                    state.player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("下一首") { state.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("上一首") { state.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("增大音量") { state.player.setVolume(state.player.volume + 0.05) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("减小音量") { state.player.setVolume(state.player.volume - 0.05) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Button("打开正在播放") { state.showNowPlaying = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("搜索") {
                    state.section = .search
                    state.path.removeAll()
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("刷新") {
                    NotificationCenter.default.post(name: .bmusicRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.setContentSize(NSSize(width: 1220, height: 790))
            window.title = "BMusic"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.minSize = NSSize(width: 980, height: 680)
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.toolbarStyle = .unifiedCompact
            window.standardWindowButton(.zoomButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

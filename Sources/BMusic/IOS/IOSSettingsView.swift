#if os(iOS)
import SwiftUI

struct IOSSettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var player: PlayerService
    @Environment(\.dismiss) private var dismiss
    @State private var cacheBytes: Int64 = 0

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                playbackSection
                appearanceSection
                storageSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(IOSBackdrop())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                cacheBytes = await Task.detached(priority: .utility) {
                    Self.directorySize(AppPaths.caches)
                }.value
            }
        }
    }

    private var accountSection: some View {
        Section("账号") {
            if let account = state.account {
                HStack(spacing: 12) {
                    if !account.avatarURL.isEmpty {
                        CachedAsyncImage(url: account.avatarURL)
                            .frame(width: 46, height: 46)
                            .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.system(size: 14, weight: .semibold))
                        Text("UID \(account.mid) · Lv.\(account.level)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Button("退出登录", role: .destructive) {
                    state.logout()
                    dismiss()
                }
            } else {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        state.showLogin = true
                    }
                } label: {
                    Label("扫码登录哔哩哔哩", systemImage: "qrcode")
                }
            }
        }
    }

    private var playbackSection: some View {
        Section("播放") {
            Picker("音质", selection: $settings.quality) {
                ForEach(PlaybackQuality.allCases) { quality in
                    VStack(alignment: .leading) {
                        Text(quality.title)
                        Text(quality.detail)
                    }
                    .tag(quality)
                }
            }
            .pickerStyle(.navigationLink)

            Toggle("自动播放下一首", isOn: $settings.autoPlayNext)
            Toggle("无缝衔接", isOn: $settings.gaplessPlayback)
            Toggle("显示歌词", isOn: $settings.lyricsEnabled)
            
            Toggle("系统锁屏控制", isOn: $settings.systemNowPlaying)
            Toggle("显示播放次数", isOn: $settings.showPlayCount)
        }
    }

    private var appearanceSection: some View {
        Section("外观") {
            Picker("主题", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var storageSection: some View {
        Section("存储") {
            HStack {
                Text("图片与歌词缓存")
                Spacer()
                Text(cacheBytes > 0 ? Formatters.fileSize(cacheBytes) : "0 KB")
                    .foregroundStyle(.secondary)
            }
            Button("清理缓存", role: .destructive) {
                Task {
                    await Task.detached(priority: .utility) {
                        try? FileManager.default.removeItem(at: AppPaths.caches)
                        try? FileManager.default.createDirectory(at: AppPaths.caches, withIntermediateDirectories: true)
                    }.value
                    cacheBytes = 0
                    ToastCenter.shared.show("缓存已清理")
                }
            }
            NavigationLink("下载管理") {
                IOSDownloadsView()
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("BMusic")
                    .font(.system(size: 13, weight: .semibold))
                Text("非官方哔哩哔哩音乐客户端，仅用于学习与个人使用。音乐、封面与歌词版权归哔哩哔哩及相应创作者所有。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding(.vertical, 3)
            Link("哔哩哔哩", destination: URL(string: "https://www.bilibili.com")!)
                .font(.system(size: 12))
        }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
#endif

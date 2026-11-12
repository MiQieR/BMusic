#if os(macOS)
import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, playback, storage, about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "通用"
        case .playback: return "播放"
        case .storage: return "存储"
        case .about: return "关于"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .playback: return "waveform"
        case .storage: return "internaldrive"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: SettingsTab = .general
    @State private var imageCacheSize: Int64 = 0
    @State private var dataSize: Int64 = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.55)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case .general: generalContent
                    case .playback: playbackContent
                    case .storage: storageContent
                    case .about: aboutContent
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 760, height: 560)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blending: .behindWindow)
                Theme.pageGradient
            }
            .ignoresSafeArea()
        }
        .task {
            imageCacheSize = directorySize(AppPaths.images)
            dataSize = directorySize(AppPaths.root)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    state.showSettings = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 16)
                            Text(item.title)
                                .font(.system(size: 12.5, weight: tab == item ? .semibold : .regular))
                            Spacer()
                        }
                        .foregroundStyle(tab == item ? Color.primary : Color.primary.opacity(0.68))
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(tab == item ? Theme.accent.opacity(0.12) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("BMusic 1.0.0")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 19)
                .padding(.bottom, 18)
        }
        .frame(width: 168)
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsTitle("通用", "外观、账户与系统集成")

            SettingsCard(title: "账户") {
                if let account = state.account {
                    HStack(spacing: 11) {
                        CachedAsyncImage(url: account.avatarURL)
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("Lv.\(account.level) · 已登录")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("退出登录") {
                            state.logout()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("未登录")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("登录后同步 B 站收藏夹")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("扫码登录") { state.showLogin = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }

            SettingsCard(title: "外观") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("主题")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("跟随系统或固定浅色 / 深色")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: settingBinding(\.appearance)) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                }

                Divider().opacity(0.5)

                SettingsToggleRow(
                    title: "显示播放量",
                    detail: "在歌曲与视频信息中显示播放次数",
                    isOn: settingBinding(\.showPlayCount)
                )
                SettingsToggleRow(
                    title: "系统媒体控制",
                    detail: "在控制中心与媒体键中显示正在播放",
                    isOn: settingBinding(\.systemNowPlaying)
                )
            }

            SettingsCard(title: "睡眠定时") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("停止播放")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(state.player.sleepRemainingText.map { "剩余 \($0)" } ?? "到点后自动暂停播放")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { state.settings.sleepMinutes },
                        set: { minutes in
                            state.settings.sleepMinutes = minutes
                            state.player.setSleepTimer(minutes: minutes)
                        }
                    )) {
                        Text("关闭").tag(0)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("60 分钟").tag(60)
                        Text("90 分钟").tag(90)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
        }
    }

    // MARK: - Playback

    private var playbackContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsTitle("播放", "音质与播放行为")

            SettingsCard(title: "音质") {
                VStack(spacing: 2) {
                    ForEach(PlaybackQuality.allCases) { quality in
                        Button {
                            let settings = state.settings
                            settings.quality = quality
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: state.settings.quality == quality ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(state.settings.quality == quality ? Theme.accent : Color.secondary.opacity(0.55))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(quality.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text(quality.detail)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(quality.badge)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(state.settings.quality == quality ? Theme.accent.opacity(0.06) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Hi-Res 与杜比需要对应的大会员权益；不可用时会自动回落到高品质。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }

            SettingsCard(title: "播放行为") {
                SettingsToggleRow(
                    title: "自动播放下一首",
                    detail: "当前歌曲结束后继续播放队列",
                    isOn: settingBinding(\.autoPlayNext)
                )
                SettingsToggleRow(
                    title: "显示歌词",
                    detail: "优先使用视频字幕，其次网易云与 LRCLIB",
                    isOn: settingBinding(\.lyricsEnabled)
                )
            }

            SettingsCard(title: "音量") {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { state.player.volume },
                            set: { state.player.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(Theme.accent)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(Int(state.player.volume * 100))%")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Storage

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsTitle("存储", "下载与缓存")

            SettingsCard(title: "下载") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(state.downloads.completedCount) 首已下载")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(Formatters.fileSize(state.downloads.totalBytes) + " · " + String(state.downloads.activeCount) + " 个任务进行中")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.downloads])
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if state.downloads.completedCount > 0 {
                    Divider().opacity(0.5)
                    HStack {
                        Text("删除已下载的音频文件，不会删除歌单记录。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清理下载") {
                            state.downloads.clearCompleted()
                            dataSize = directorySize(AppPaths.root)
                            ToastCenter.shared.show("已清理下载")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }

            SettingsCard(title: "图片缓存") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("封面与头像缓存")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(Formatters.fileSize(imageCacheSize))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清除缓存") {
                        ImageStore.shared.clearDiskCache()
                        imageCacheSize = 0
                        ToastCenter.shared.show("图片缓存已清除")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            SettingsCard(title: "应用数据") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本地数据")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("账号状态、歌单、播放记录 · \(Formatters.fileSize(dataSize))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Text(AppPaths.root.path)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("打开文件夹") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.root])
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: - About

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsTitle("关于", "BMusic 桌面音乐播放器")

            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.accentGradient)
                    Image(systemName: "music.note")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 84, height: 84)
                .shadow(color: Theme.accent.opacity(0.32), radius: 16, y: 7)

                VStack(spacing: 3) {
                    Text("BMusic")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("版本 1.0.0")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            SettingsCard(title: "说明") {
                Text("BMusic 是一个非官方的哔哩哔哩音乐客户端，使用 SwiftUI 构建，音频解码与输出由 libmpv 完成。所有音乐内容版权归原作者与哔哩哔哩所有。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "技术") {
                techRow("界面", "SwiftUI · macOS 15+")
                Divider().opacity(0.5)
                techRow("播放引擎", "libmpv / MPVKit")
                Divider().opacity(0.5)
                techRow("账号安全", "应用内 Cookie · 不使用钥匙串")
                Divider().opacity(0.5)
                techRow("网络", "哔哩哔哩 Web API")
            }

            HStack {
                Text("非官方项目 · 仅供学习与个人使用")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func settingBinding<Value>(
        _ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>
    ) -> Binding<Value> {
        Binding(
            get: { state.settings[keyPath: keyPath] },
            set: { newValue in
                let settings = state.settings
                settings[keyPath: keyPath] = newValue
            }
        )
    }

    private func settingsTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func techRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}

// MARK: - Building blocks

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: 12)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .controlSize(.small)
        }
    }
}
#endif

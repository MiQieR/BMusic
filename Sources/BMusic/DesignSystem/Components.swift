import SwiftUI

// MARK: - Images

struct CachedAsyncImage: View {
    let url: String
    var contentMode: ContentMode = .fill

    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            image = nil
            failed = false
            guard !url.isEmpty else { return }
            let loaded = await ImageStore.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.25)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Theme.accent.opacity(0.20),
                    Theme.violet.opacity(0.12),
                    Color.primary.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: failed ? "music.note" : "waveform")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

struct CoverArt: View {
    let url: String
    var cornerRadius: CGFloat = Theme.coverRadius
    var symbolSize: CGFloat = 22

    var body: some View {
        Color.clear
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                    CachedAsyncImage(url: url)
                        .overlay {
                            if url.isEmpty {
                                Image(systemName: "music.note")
                                    .font(.system(size: symbolSize, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

struct MosaicCover: View {
    var urls: [String]
    var cornerRadius: CGFloat = Theme.coverRadius

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let half = (proxy.size.width - spacing) / 2
            ZStack {
                Color.primary.opacity(0.05)
                if urls.isEmpty {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                } else if urls.count == 1 {
                    CachedAsyncImage(url: urls[0])
                } else {
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            CachedAsyncImage(url: urls[0]).frame(width: half, height: half)
                            CachedAsyncImage(url: urls.count > 1 ? urls[1] : urls[0]).frame(width: half, height: half)
                        }
                        HStack(spacing: spacing) {
                            CachedAsyncImage(url: urls.count > 2 ? urls[2] : "").frame(width: half, height: half)
                            CachedAsyncImage(url: urls.count > 3 ? urls[3] : "").frame(width: half, height: half)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Buttons

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 15
    var active = false
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Color.primary.opacity(hovering ? 0.92 : 0.66))
                .frame(width: size + 18, height: size + 18)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(hovering ? 0.07 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule().fill(Theme.accentGradient)
            )
            .shadow(color: Theme.accent.opacity(0.28), radius: 10, y: 4)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.86))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    var placeholder = "搜索音乐、UP 主"
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if focused {
                Text("⏎")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(focused ? 0.065 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.07), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.16), value: focused)
        .frame(width: 236)
    }
}

// MARK: - Headers

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

// MARK: - Segmented tabs

struct SegmentedTabs<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selection = item
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(PlatformColor.controlBackground)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Color.primary.opacity(0.055))
        )
    }
}

// MARK: - Track card

struct TrackCard: View {
    let track: Track
    var source: String
    var width: CGFloat? = nil

    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                CoverArt(url: track.coverURL, cornerRadius: 13)
                    .aspectRatio(1, contentMode: .fit)
                Button {
                    state.play(track, source: source)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.accentGradient))
                        .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(9)
                .opacity(hovering ? 1 : 0)
                .scaleEffect(hovering ? 1 : 0.86)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .hoverLift(hovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(track.artist.displayName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .onHover { hovering = $0 }
        .onTapGesture { state.play(track, source: source) }
        .contextMenu { TrackContextMenu(track: track) }
    }
}

// MARK: - Track row

struct TrackRow: View {
    let track: Track
    var index: Int?
    var source: String
    var showCover = true
    var showAlbum = true
    var onDelete: (() -> Void)?

    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    private var isCurrent: Bool { state.player.currentTrack?.queueKey == track.queueKey }
    private var isLiked: Bool { state.library.isLiked(track) }

    var body: some View {
        HStack(spacing: 12) {
            if let index {
                Group {
                    if isCurrent && state.player.isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(isCurrent ? Theme.accent : Color.secondary.opacity(0.75))
                    }
                }
                .frame(width: 24, alignment: .trailing)
            }

            if showCover {
                ZStack {
                    CoverArt(url: track.coverURL, cornerRadius: 7)
                        .frame(width: 42, height: 42)
                    if hovering {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.black.opacity(0.38))
                        Button {
                            state.play(track, source: source)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Theme.accent : .primary)
                        .lineLimit(1)
                    if track.pages.count > 1 {
                        Text("\(track.pages.count)P")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(track.artist.displayName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showAlbum, !track.album.isEmpty {
                Text(track.album)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }

            if hovering {
                IconButton(symbol: isLiked ? "heart.fill" : "heart", size: 12, active: isLiked) {
                    let liked = state.library.toggleLike(track)
                    ToastCenter.shared.show(liked ? "已收藏" : "已取消收藏")
                }
                .transition(.opacity)
            }

            Text(track.durationText)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.045) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { state.play(track, source: source) }
        .contextMenu {
            TrackContextMenu(track: track)
            if let onDelete {
                Divider()
                Button("从列表中移除", role: .destructive, action: onDelete)
            }
        }
    }
}

// MARK: - Context menu

struct TrackContextMenu: View {
    let track: Track

    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            Button("播放") { state.play(track, source: track.origin.title) }
            Button("下一首播放") {
                state.player.addToQueue(track, playNext: true)
                ToastCenter.shared.show("已加入下一首播放")
            }
            Button("添加到播放队列") {
                state.player.addToQueue(track)
                ToastCenter.shared.show("已添加到播放队列")
            }
            Divider()
            Button(state.library.isLiked(track) ? "取消收藏" : "收藏到喜欢的音乐") {
                let liked = state.library.toggleLike(track)
                ToastCenter.shared.show(liked ? "已收藏" : "已取消收藏")
            }
            Menu("添加到歌单") {
                if state.library.playlists.isEmpty {
                    Text("暂无自建歌单")
                } else {
                    ForEach(state.library.playlists) { playlist in
                        Button(playlist.name) {
                            state.library.add(track, to: playlist.id)
                            ToastCenter.shared.show("已添加到「\(playlist.name)」")
                        }
                    }
                }
            }
            Button("下载") {
                state.downloads.enqueue(track: track, quality: state.settings.quality, api: state.api)
                ToastCenter.shared.show("已加入下载队列")
            }
            if track.currentPage != nil, track.pages.count > 1 {
                Menu("选择分P") {
                    ForEach(track.pages) { page in
                        Button(page.title) {
                            var copy = track
                            copy.cid = page.cid
                            copy.title = page.title
                            copy.duration = page.duration
                            state.play(copy, source: track.origin.title)
                        }
                    }
                }
            }
            Divider()
            if let url = track.webURL {
                Button("在浏览器中打开") { PlatformActions.open(url) }
            }
            Button("复制视频链接") {
                PlatformActions.copy("https://www.bilibili.com/video/\(track.bvid)")
                ToastCenter.shared.show("链接已复制")
            }
        }
    }
}

// MARK: - Playlist card

struct PlaylistCard: View {
    let title: String
    let subtitle: String
    let urls: [String]
    var badge: String?
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                MosaicCover(urls: Array(urls.prefix(4)))
                    .aspectRatio(1, contentMode: .fit)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.34)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.28), in: Capsule())
                        .padding(9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .hoverLift(hovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

// MARK: - Misc

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String = ""
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.8))
                .frame(width: 72, height: 72)
                .background(Theme.accent.opacity(0.08), in: Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

struct LoadingRows: View {
    var count = 6

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.055))
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Color.primary.opacity(0.07)).frame(width: 220, height: 10)
                        Capsule().fill(Color.primary.opacity(0.045)).frame(width: 120, height: 8)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 56)
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: message.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(message.text)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 38)
        .background(
            Capsule()
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
    }

    private var color: Color {
        switch message.style {
        case .info: return Theme.accent
        case .success: return Theme.mint
        case .error: return Color(hex: 0xFF6B6B)
        }
    }
}

struct PlayingBars: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2.5, height: animating ? CGFloat(7 + index * 3) : CGFloat(3 + index))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

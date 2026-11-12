#if os(macOS)
import AppKit
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var player: PlayerService
    @State private var panel: PlayerPanel?
    @State private var spin = false

    init(player: PlayerService) {
        _player = ObservedObject(wrappedValue: player)
    }

    private var track: Track? { player.currentTrack }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1120
            let horizontalPadding: CGFloat = compact ? 26 : 56
            let contentWidth = min(1020, max(0, proxy.size.width - horizontalPadding * 2))
            let artworkSize = min(compact ? 238 : 286, max(210, contentWidth * 0.29))
            let columnGap: CGFloat = compact ? 30 : 52
            let lyricsWidth = max(240, contentWidth - artworkSize - columnGap)

            ZStack {
                background
                VStack(spacing: 0) {
                    topBar
                        .frame(width: max(0, proxy.size.width - 114), alignment: .leading)
                        .clipped()
                        .padding(.leading, 88)
                        .padding(.trailing, 26)
                        .padding(.top, 20)
                        .padding(.bottom, 6)

                    HStack(alignment: .center, spacing: columnGap) {
                        artworkColumn(size: artworkSize)
                            .frame(width: artworkSize)
                        lyricsColumn
                            .frame(width: lyricsWidth, alignment: .leading)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    bottomBar
                        .frame(width: contentWidth, alignment: .leading)
                        .clipped()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 22)
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .trailing) {
                if let panel {
                    HStack(spacing: 0) {
                        Color.black.opacity(panel == .queue ? 0.18 : 0)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation { self.panel = nil } }
                        panelView(panel)
                            .frame(width: min(348, proxy.size.width * 0.34))
                    }
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .preferredColorScheme(.dark)
        .onAppear {
            panel = state.nowPlayingPanel
            state.nowPlayingPanel = nil
            spin = true
        }
        .onExitCommand {
            if panel != nil {
                withAnimation { panel = nil }
            } else {
                state.showNowPlaying = false
            }
        }
        .onChange(of: player.currentTrack?.id) { _, _ in
            // Keep the queue open across automatic track changes.
            if panel != .queue { panel = nil }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(hex: 0x0D0B10)
            if let track {
                CachedAsyncImage(url: track.coverURL)
                    .scaleEffect(1.4)
                    .blur(radius: 84)
                    .opacity(0.42)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                Color.black.opacity(0.22)
                LinearGradient(
                    colors: [
                        Color(hex: 0x0D0B10).opacity(0.42),
                        Color(hex: 0x0D0B10).opacity(0.70),
                        Color(hex: 0x0D0B10).opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Theme.accent.opacity(0.20), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 700
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                state.showNowPlaying = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("收起播放页")
            .keyboardShortcut(.escape, modifiers: [])

            VStack(alignment: .leading, spacing: 1) {
                Text("正在播放")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                Text(player.sourceTitle.isEmpty ? "BMusic" : player.sourceTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }
            .frame(maxWidth: 180, alignment: .leading)

            Spacer(minLength: 8)

            if player.isOfflinePlayback {
                Label("本地播放", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                    .background(.white.opacity(0.08), in: Capsule())
            }

            Text(player.actualQuality.badge)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 7)
                .frame(height: 23)
                .background(.white.opacity(0.09), in: Capsule())

            Menu {
                if let track {
                    Button(player.isLiked ? "取消收藏" : "收藏到喜欢的音乐") {
                        player.toggleLikeCurrent()
                    }
                    Button("下载") { player.downloadCurrent() }
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
                    Divider()
                    if let url = track.webURL {
                        Button("在浏览器中打开") { NSWorkspace.shared.open(url) }
                    }
                    Button("复制视频链接") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "https://www.bilibili.com/video/\(track.bvid)",
                            forType: .string
                        )
                        ToastCenter.shared.show("链接已复制")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .clipped()
    }

    // MARK: - Artwork

    private func artworkColumn(size: CGFloat) -> some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.06))
                CoverArt(url: track?.coverURL ?? "", cornerRadius: 20)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.48), radius: 34, y: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(player.isPlaying ? 1 : 0.985)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: player.isPlaying)

            VStack(spacing: 5) {
                Text(track?.title ?? "未在播放")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(width: size)

                Text(track?.artist.displayName ?? "BMusic")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                    .frame(width: size)
            }
            .frame(width: size)

            HStack(spacing: 14) {
                Button {
                    player.toggleLikeCurrent()
                } label: {
                    Image(systemName: player.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(player.isLiked ? Theme.accent : .white.opacity(0.72))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help(player.isLiked ? "取消收藏" : "收藏")

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        panel = panel == .queue ? nil : .queue
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("播放队列")

                Button {
                    player.downloadCurrent()
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("下载")
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Lyrics

    private var lyricsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("歌词")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .textCase(.uppercase)
                Spacer()
                if !state.lyrics.lyrics.source.isEmpty {
                    Text(state.lyrics.lyrics.source)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.28))
                        .lineLimit(1)
                }
            }

            if !state.settings.lyricsEnabled {
                VStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.16))
                    Text("歌词已关闭")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.36))
                    Text("可在设置中重新开启")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.22))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ZStack {
                if state.lyrics.isLoading {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("正在寻找歌词…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.36))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if state.lyrics.lyrics.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.16))
                        Text(state.lyrics.errorText ?? "暂无歌词")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.36))
                        Text("纯音乐或未收录的投稿可能没有歌词")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    lyricsScroll
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lyricsScroll: some View {
        let lines = state.lyrics.lyrics.lines
        let active = state.lyrics.activeLineIndex(at: player.position)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(
                                size: index == active ? 24 : 17,
                                weight: index == active ? .bold : .medium,
                                design: .rounded
                            ))
                            .foregroundStyle(
                                index == active
                                    ? Color.white.opacity(0.98)
                                    : Color.white.opacity(index < (active ?? 0) ? 0.26 : 0.38)
                            )
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.seek(to: line.time)
                            }
                            .animation(.easeOut(duration: 0.2), value: active)
                    }
                    Color.clear.frame(height: 120)
                }
                .padding(.vertical, 130)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                if let active { proxy.scrollTo(active, anchor: .center) }
            }
            .onChange(of: active) { _, newValue in
                guard let newValue else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 14) {
            NowPlayingScrubber(
                progress: player.progress,
                duration: player.duration,
                position: player.position,
                onSeek: { player.seek(to: $0) }
            )
            .frame(maxWidth: 760)

            HStack(spacing: 18) {
                HStack(spacing: 10) {
                    Button {
                        player.toggleMute()
                    } label: {
                        Image(systemName: volumeSymbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .buttonStyle(.plain)
                    Slider(
                        value: Binding(
                            get: { player.volume },
                            set: { player.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(.white.opacity(0.72))
                    .frame(width: 92)
                    .controlSize(.mini)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 16) {
                    Button {
                        player.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(state.settings.shuffle ? Theme.accent : .white.opacity(0.52))
                    }
                    .buttonStyle(.plain)
                    .help("随机播放")

                    Button {
                        player.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 50, height: 50)
                                .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color(hex: 0x1A1014))
                                .offset(x: player.isPlaying ? 0 : 1.5)
                                .opacity(player.isLoading ? 0.72 : 1)
                            if player.isLoading {
                                Circle()
                                    .trim(from: 0, to: 0.3)
                                    .stroke(
                                        Color(hex: 0x1A1014).opacity(0.34),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                    )
                                    .frame(width: 38, height: 38)
                                    .rotationEffect(.degrees(spin ? 360 : 0))
                                    .animation(
                                        .linear(duration: 0.9).repeatForever(autoreverses: false),
                                        value: spin
                                    )
                            }
                        }
                        .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.cycleRepeatMode()
                    } label: {
                        Image(systemName: state.settings.repeatMode.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(state.settings.repeatMode == .off ? .white.opacity(0.52) : Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("循环模式")
                }

                HStack(spacing: 12) {
                    if let sleep = player.sleepRemainingText {
                        Text("睡眠 \(sleep)")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            panel = panel == .queue ? nil : .queue
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(panel == .queue ? Theme.accent : .white.opacity(0.56))
                    }
                    .buttonStyle(.plain)
                    .help("播放队列")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var volumeSymbol: String {
        if player.isMuted || player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 0.34 { return "speaker.fill" }
        if player.volume < 0.7 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Panels

    @ViewBuilder
    private func panelView(_ panel: PlayerPanel) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(panel == .queue ? "播放队列" : "歌词")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(panel == .queue ? "\(player.queue.count) 首歌曲" : state.lyrics.lyrics.source)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
                if panel == .queue && !player.queue.isEmpty {
                    Button("清空") {
                        player.clearQueue()
                        withAnimation { self.panel = nil }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                }
                Button {
                    withAnimation { self.panel = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider().overlay(.white.opacity(0.08))

            if panel == .queue {
                queueList
            } else {
                lyricsPanel
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectView(material: .hudWindow, blending: .withinWindow)
                Color(hex: 0x120E16).opacity(0.62)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
    }

    private var queueList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(Array(player.queue.enumerated()), id: \.element.queueKey) { index, item in
                    QueueRow(index: index, track: item, isCurrent: index == player.currentIndex)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .padding(.bottom, 80)
        }
    }

    private var lyricsPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(state.lyrics.lyrics.lines) { line in
                    Text(line.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.68))
                }
                if state.lyrics.lyrics.isEmpty {
                    Text("暂无歌词")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

// MARK: - Scrubber

private struct NowPlayingScrubber: View {
    let progress: Double
    let duration: Double
    let position: Double
    let onSeek: (Double) -> Void

    @State private var hovering = false
    @State private var dragging = false
    @State private var dragFraction: Double = 0

    private var displayFraction: Double {
        dragging ? dragFraction : progress
    }

    private var displayTime: Double {
        dragging ? duration * dragFraction : position
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(height: hovering || dragging ? 5 : 4)
                    Capsule()
                        .fill(.white.opacity(0.88))
                        .frame(width: max(0, width * displayFraction), height: hovering || dragging ? 5 : 4)
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.2), radius: 3)
                        .offset(x: max(0, width * displayFraction - 5))
                        .opacity(hovering || dragging ? 1 : 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            dragging = true
                            dragFraction = min(1, max(0, value.location.x / width))
                        }
                        .onEnded { value in
                            guard duration > 0 else {
                                dragging = false
                                return
                            }
                            let fraction = min(1, max(0, value.location.x / width))
                            onSeek(duration * fraction)
                            dragging = false
                        }
                )
            }
            .frame(height: 12)
            .onHover { hovering = $0 }

            HStack {
                Text(Formatters.duration(Int(displayTime.rounded())))
                    .monospacedDigit()
                Spacer()
                Text(Formatters.duration(Int(duration.rounded())))
                    .monospacedDigit()
            }
            .font(.system(size: 9.5, design: .rounded))
            .foregroundStyle(.white.opacity(0.38))
        }
    }
}

// MARK: - Queue row

private struct QueueRow: View {
    let index: Int
    let track: Track
    let isCurrent: Bool

    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if isCurrent && state.player.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(isCurrent ? 0.62 : 0.28))
                }
            }
            .frame(width: 18)

            CoverArt(url: track.coverURL, cornerRadius: 5)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accent : .white.opacity(0.82))
                    .lineLimit(1)
                Text(track.artist.displayName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if hovering {
                Button {
                    state.player.removeQueueItem(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? .white.opacity(0.07) : (hovering ? .white.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            state.player.play(at: index)
        }
    }
}
#endif

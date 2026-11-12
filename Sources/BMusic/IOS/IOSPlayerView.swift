#if os(iOS)
import SwiftUI

struct IOSPlayerView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var settings: SettingsStore
    @State private var panel: PlayerPanel?
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var showQuality = false

    private var track: Track? { player.currentTrack }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 760
            ZStack {
                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        VStack(spacing: 18) {
                            if wide {
                                HStack(alignment: .center, spacing: 46) {
                                    artwork(size: min(430, proxy.size.height * 0.44, proxy.size.width * 0.44))
                                    VStack(spacing: 22) {
                                        metadata(alignment: .leading)
                                        if settings.lyricsEnabled {
                                            lyricsPreview(alignment: .leading, limit: 3)
                                        }
                                        controls
                                    }
                                    .frame(maxWidth: 430)
                                }
                                .frame(maxWidth: 980)
                            } else {
                                artwork(size: min(proxy.size.width - 58, proxy.size.height * 0.34, 356))
                                metadata(alignment: .center)
                                if settings.lyricsEnabled {
                                    lyricsPreview(alignment: .center, limit: 2)
                                }
                                controls
                                    .padding(.top, 14)
                            }
                        }
                        .padding(.horizontal, wide ? 26 : 22)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                        .frame(minHeight: max(0, proxy.size.height - 96), alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                    bottomBar
                        .padding(.bottom, 4)
                }
                .foregroundStyle(.white)
            }
            .background {
                backdrop
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showLyrics) {
            IOSLyricsSheet()
                .environmentObject(state)
                .environmentObject(player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showQueue) {
            IOSQueueSheet()
                .environmentObject(state)
                .environmentObject(player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("音质", isPresented: $showQuality, titleVisibility: .visible) {
            ForEach(PlaybackQuality.allCases) { quality in
                Button {
                    state.settings.quality = quality
                    player.reloadForQuality(quality)
                } label: {
                    Text(quality.title)
                }
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            CachedAsyncImage(url: track?.coverURL ?? "")
                .scaleEffect(1.35)
                .blur(radius: 58)
                .opacity(0.72)
            LinearGradient(
                colors: [.black.opacity(0.34), .black.opacity(0.28), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                state.showNowPlaying = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(1.4)
                Text(player.sourceTitle.isEmpty ? "BMusic" : player.sourceTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button {
                    showQuality = true
                } label: {
                    Label("音质 · \(player.actualQuality.badge)", systemImage: "waveform")
                }
                Button {
                    player.downloadCurrent()
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                if let url = track?.webURL {
                    Button {
                        PlatformActions.open(url)
                    } label: {
                        Label("在哔哩哔哩打开", systemImage: "play.rectangle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func artwork(size: CGFloat) -> some View {
        CoverArt(url: track?.coverURL ?? "", cornerRadius: 20)
            .frame(width: size, height: size)
            .clipped()
            .shadow(color: .black.opacity(0.45), radius: 28, y: 18)
            .scaleEffect(player.isPlaying ? 1 : 0.96)
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: player.isPlaying)
            .overlay(alignment: .bottomTrailing) {
                if player.isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(9)
                        .background(.black.opacity(0.32), in: Circle())
                        .padding(12)
                }
            }
    }

    private func metadata(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(track?.title ?? "未在播放")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(track?.artist.displayName ?? "选择一首音乐")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
            if player.isOfflinePlayback {
                Label("本地下载", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func lyricsPreview(alignment: HorizontalAlignment, limit: Int) -> some View {
        let lines = state.lyrics.lyrics.lines
        let active = state.lyrics.lyrics.activeIndex(at: player.position)
        Button {
            showLyrics = true
        } label: {
            VStack(alignment: alignment, spacing: 7) {
                if lines.isEmpty {
                    Text(state.lyrics.isLoading ? "正在寻找歌词…" : "暂无歌词，点击查看")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.42))
                } else {
                    ForEach(visibleLines(lines, active: active, limit: limit), id: \.line.id) { entry in
                        Text(entry.line.text)
                            .font(.system(size: entry.isActive ? 15 : 12.5, weight: entry.isActive ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(entry.isActive ? 0.94 : 0.42))
                            .multilineTextAlignment(alignment == .center ? .center : .leading)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func visibleLines(_ lines: [LyricLine], active: Int?, limit: Int) -> [(line: LyricLine, isActive: Bool)] {
        guard let active else {
            return lines.prefix(limit).map { ($0, false) }
        }
        let start = max(0, min(active - (limit == 3 ? 1 : 1), lines.count - limit))
        return lines[start..<min(lines.count, start + limit)].map { ($0, $0.id == lines[active].id) }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            IOSScrubber(
                progress: player.progress,
                duration: player.duration,
                position: player.position,
                onSeek: { player.seek(to: $0) }
            )
            .frame(maxWidth: 520)

            HStack(spacing: 30) {
                Button {
                    player.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(state.settings.shuffle ? Theme.accent : .white.opacity(0.55))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)

                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 23, weight: .medium))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)

                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle().fill(.white).frame(width: 68, height: 68)
                            .shadow(color: .black.opacity(0.28), radius: 18, y: 7)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1A1014))
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                    .opacity(player.isLoading ? 0.8 : 1)
                }
                .buttonStyle(.plain)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 23, weight: .medium))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)

                Button {
                    player.cycleRepeatMode()
                } label: {
                    Image(systemName: state.settings.repeatMode.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(state.settings.repeatMode == .off ? .white.opacity(0.55) : Theme.accent)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                player.toggleLikeCurrent()
            } label: {
                Image(systemName: player.isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(player.isLiked ? Theme.accent : .white.opacity(0.68))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if settings.lyricsEnabled {
                Button {
                    showLyrics = true
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            Button {
                player.downloadCurrent()
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 46)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

struct IOSScrubber: View {
    let progress: Double
    let duration: Double
    let position: Double
    let onSeek: (Double) -> Void

    @State private var dragging = false
    @State private var dragFraction: Double = 0

    private var shownProgress: Double {
        dragging ? dragFraction : max(0, min(progress, 1))
    }

    private var shownPosition: Double {
        dragging ? dragFraction * duration : position
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                    Capsule().fill(.white.opacity(0.92))
                        .frame(width: max(0, width * shownProgress), height: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: dragging ? 13 : 9, height: dragging ? 13 : 9)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: max(0, min(width, width * shownProgress)) - (dragging ? 6.5 : 4.5))
                }
                .frame(height: 20, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            dragging = true
                            dragFraction = max(0, min(1, value.location.x / max(width, 1)))
                        }
                        .onEnded { _ in
                            guard duration > 0 else { dragging = false; return }
                            onSeek(dragFraction * duration)
                            dragging = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(Formatters.duration(Int(shownPosition)))
                Spacer()
                Text(duration > 0 ? Formatters.duration(Int(duration)) : "--:--")
            }
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.white.opacity(0.48))
            .monospacedDigit()
        }
    }
}

struct IOSLyricsSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            Color.clear.frame(height: 30)
                            if state.lyrics.lyrics.lines.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "quote.bubble")
                                        .font(.system(size: 30, weight: .light))
                                        .foregroundStyle(Theme.accent.opacity(0.6))
                                    Text(state.lyrics.isLoading ? "正在寻找歌词…" : "暂无歌词")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    Text("纯音乐或未收录的投稿可能没有歌词")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.top, 50)
                            }
                            ForEach(state.lyrics.lyrics.lines) { line in
                                let active = state.lyrics.lyrics.activeIndex(at: player.position) == line.id
                                Button {
                                    player.seek(to: line.time)
                                } label: {
                                    Text(line.text)
                                        .font(.system(size: active ? 19 : 15, weight: active ? .bold : .regular))
                                        .foregroundStyle(active ? Theme.accent : .primary.opacity(0.52))
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4)
                                        .padding(.horizontal, 20)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                            }
                            Color.clear.frame(height: 50)
                        }
                    }
                    .onChange(of: state.lyrics.lyrics.activeIndex(at: player.position)) { _, active in
                        guard let active else { return }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                            proxy.scrollTo(active, anchor: .center)
                        }
                    }
                    .onAppear {
                        if let active = state.lyrics.lyrics.activeIndex(at: player.position) {
                            proxy.scrollTo(active, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(player.currentTrack?.title ?? "歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct IOSQueueSheet: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.queueKey) { index, track in
                    Button {
                        player.play(at: index)
                    } label: {
                        HStack(spacing: 10) {
                            CoverArt(url: track.coverURL, cornerRadius: 6)
                                .frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 12.5, weight: player.currentTrack?.queueKey == track.queueKey ? .semibold : .regular))
                                    .foregroundStyle(player.currentTrack?.queueKey == track.queueKey ? Theme.accent : .primary)
                                    .lineLimit(1)
                                Text(track.artist.displayName)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if player.currentTrack?.queueKey == track.queueKey {
                                Image(systemName: player.isPlaying ? "waveform" : "pause")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("播放队列 · \(player.queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空", role: .destructive) { player.clearQueue() }
                        .disabled(player.queue.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
#endif

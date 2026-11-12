#if os(macOS)
import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var player: PlayerService
    @State private var showVolume = false

    init(player: PlayerService) {
        _player = ObservedObject(wrappedValue: player)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 12) {
                trackInfo
                Spacer(minLength: 10)
                controls
                Spacer(minLength: 10)
                trailingControls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .frame(height: Theme.playerHeight)

            progressBar
        }
        .frame(height: Theme.playerHeight)
        .background {
            ZStack {
                VisualEffectView(material: .sidebar, blending: .withinWindow)
                Color(nsColor: .windowBackgroundColor).opacity(0.24)
                LinearGradient(
                    colors: [Theme.accent.opacity(0.045), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 9)
    }

    private var trackInfo: some View {
        HStack(spacing: 10) {
            Button {
                state.showNowPlaying = true
            } label: {
                CoverArt(url: player.currentTrack?.coverURL ?? "", cornerRadius: 8)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.currentTrack?.title ?? "未在播放")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if player.isOfflinePlayback {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.mint)
                    }
                    Text(player.currentTrack?.artist.displayName ?? "选择一首音乐")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 180, alignment: .leading)

            IconButton(
                symbol: player.isLiked ? "heart.fill" : "heart",
                size: 13,
                active: player.isLiked,
                help: "收藏"
            ) {
                player.toggleLikeCurrent()
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            IconButton(
                symbol: "shuffle",
                size: 12,
                active: state.settings.shuffle,
                help: "随机播放"
            ) {
                player.toggleShuffle()
            }

            IconButton(symbol: "backward.fill", size: 13, help: "上一首") {
                player.previous()
            }

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 34, height: 34)
                        .shadow(color: Theme.accent.opacity(0.34), radius: 8, y: 3)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: player.isPlaying ? 0 : 1)
                        .opacity(player.isLoading ? 0.66 : 1)
                }
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "暂停" : "播放")
            .padding(.horizontal, 3)

            IconButton(symbol: "forward.fill", size: 13, help: "下一首") {
                player.next()
            }

            IconButton(
                symbol: state.settings.repeatMode.symbol,
                size: 12,
                active: state.settings.repeatMode != .off,
                help: "循环模式"
            ) {
                player.cycleRepeatMode()
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 1) {
            Menu {
                ForEach([PlaybackQuality.hiRes, .dolby, .lossless, .high, .standard], id: \.self) { quality in
                    Button {
                        state.settings.quality = quality
                    } label: {
                        if state.settings.quality == quality {
                            Label(quality.title, systemImage: "checkmark")
                        } else {
                            Text(quality.title)
                        }
                    }
                }
            } label: {
                Text(player.actualQuality.badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("播放音质")

            IconButton(symbol: "text.quote", size: 12, help: "歌词") {
                state.showNowPlayingPanel(.lyrics)
            }

            IconButton(symbol: "list.bullet", size: 12, help: "播放队列") {
                state.showNowPlayingPanel(.queue)
            }

            Button {
                showVolume.toggle()
            } label: {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.66))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("音量")
            .popover(isPresented: $showVolume, arrowEdge: .bottom) {
                HStack(spacing: 9) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { player.volume },
                            set: { player.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(Theme.accent)
                    .frame(width: 120)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }

            IconButton(symbol: "chevron.up", size: 12, help: "展开播放页") {
                state.showNowPlaying = true
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                Rectangle()
                    .fill(Theme.accentGradient)
                    .frame(width: max(0, width * player.progress))
            }
            .frame(height: 2.5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard player.duration > 0 else { return }
                        let fraction = min(1, max(0, value.location.x / width))
                        player.seek(to: player.duration * fraction)
                    }
            )
        }
        .frame(height: 2.5)
        .padding(.horizontal, 22)
        .padding(.bottom, 1)
    }

    private var volumeSymbol: String {
        if player.isMuted || player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 0.34 { return "speaker.fill" }
        if player.volume < 0.7 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
#endif

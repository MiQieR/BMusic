#if os(iOS)
import SwiftUI

struct IOSSectionHeader: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: sizeClass == .regular ? 23 : 20, weight: .bold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

struct IOSAlbumCard: View {
    let track: Track
    var width: CGFloat = 148

    @EnvironmentObject private var state: AppState

    var body: some View {
        Button {
            state.play(track, source: "推荐")
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                CoverArt(url: track.coverURL, cornerRadius: 12)
                    .frame(width: width, height: width)
                    .clipped()
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                Text(track.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
                Text(track.artist.displayName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(state.library.isLiked(track) ? "取消收藏" : "收藏") {
                let liked = state.library.toggleLike(track)
                ToastCenter.shared.show(liked ? "已收藏" : "已取消收藏")
            }
            Button("下一首播放") { state.player.addToQueue(track, playNext: true) }
            Button("下载") {
                state.downloads.enqueue(track: track, quality: state.settings.quality, api: state.api)
                ToastCenter.shared.show("已加入下载队列")
            }
        }
    }
}

struct IOSTrackRow: View {
    let track: Track
    var index: Int?
    var showCover = true

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService

    private var isCurrent: Bool { player.currentTrack?.queueKey == track.queueKey }

    var body: some View {
        Button {
            state.play(track, source: "推荐")
        } label: {
            HStack(spacing: 11) {
                if let index {
                    Text("\(index)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                        .frame(width: 18)
                }
                if showCover {
                    CoverArt(url: track.coverURL, cornerRadius: 7)
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Theme.accent : .primary)
                        .lineLimit(1)
                    Text(track.artist.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(Formatters.duration(track.duration))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(state.library.isLiked(track) ? "取消收藏" : "收藏") {
                let liked = state.library.toggleLike(track)
                ToastCenter.shared.show(liked ? "已收藏" : "已取消收藏")
            }
            Button("下一首播放") { state.player.addToQueue(track, playNext: true) }
            Button("下载") {
                state.downloads.enqueue(track: track, quality: state.settings.quality, api: state.api)
                ToastCenter.shared.show("已加入下载队列")
            }
            if let url = track.webURL {
                Button("在浏览器中打开") { PlatformActions.open(url) }
            }
        }
    }
}

struct IOSMiniPlayer: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        Button {
            state.showNowPlaying = true
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    CoverArt(url: player.currentTrack?.coverURL ?? "", cornerRadius: 8)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.currentTrack?.title ?? "未在播放")
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Text(player.currentTrack?.artist.displayName ?? "BMusic")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.75))
                            .frame(width: 32, height: 34)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(Theme.accent)
                            .frame(width: max(0, proxy.size.width * player.progress))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct IOSEmptyState: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct IOSLoadingRows: View {
    var count = 6
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)).frame(width: 180, height: 11)
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)).frame(width: 110, height: 9)
                    }
                    Spacer()
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}
#endif

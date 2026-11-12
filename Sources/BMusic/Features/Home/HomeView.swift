#if os(macOS)
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState

    @State private var feed: [Track] = []
    @State private var ranking: [Track] = []
    @State private var rankingNote = ""
    @State private var hotSongs: [HotSong] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 208), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if isLoading && feed.isEmpty {
                    loadingState
                } else if let errorText, feed.isEmpty {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "暂时没有加载出来",
                        message: errorText,
                        actionTitle: "重试"
                    ) {
                        Task { await load(force: true) }
                    }
                } else {
                    if let featured = ranking.first ?? feed.first {
                        hero(featured)
                    }

                    if !feed.isEmpty {
                        recommendSection
                    }

                    if !hotSongs.isEmpty {
                        hotSection
                    }

                    if !ranking.isEmpty {
                        rankingSection
                    }

                    if !state.library.recentlyPlayed.isEmpty {
                        recentSection
                    }
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .bmusicRefreshContent)) { _ in
            Task { await load(force: true) }
        }
    }

    // MARK: - Hero

    private func hero(_ track: Track) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x3A1D2A), Color(hex: 0x1E1720), Color(hex: 0x221725)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            CachedAsyncImage(url: track.coverURL)
                .scaleEffect(1.15)
                .blur(radius: 46)
                .opacity(0.42)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            LinearGradient(
                colors: [
                    Color(hex: 0x1B131A).opacity(0.62),
                    Color(hex: 0x1B131A).opacity(0.28),
                    Color(hex: 0x1B131A).opacity(0.48)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("编辑精选 · 每日更新")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(.white.opacity(0.10), in: Capsule())

                    Text(track.title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(track.artist.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    HStack(spacing: 14) {
                        Label(Formatters.playCount(track.playCount), systemImage: "play.fill")
                        Label(track.durationText, systemImage: "clock")
                        if let date = track.publishedAt {
                            Label(Formatters.relativeDate(date), systemImage: "calendar")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.52))

                    HStack(spacing: 10) {
                        Button {
                            state.play(feed, startingAt: 0, source: "推荐")
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("立即播放")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: 0x2A1520))
                            .padding(.horizontal, 17)
                            .frame(height: 36)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)

                        Button {
                            let liked = state.library.toggleLike(track)
                            ToastCenter.shared.show(liked ? "已收藏" : "已取消收藏")
                        } label: {
                            Image(systemName: state.library.isLiked(track) ? "heart.fill" : "heart")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 5)
                }
                .frame(maxWidth: 430, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 10)

                CoverArt(url: track.coverURL, cornerRadius: 16)
                    .frame(width: 172, height: 172)
                    .shadow(color: .black.opacity(0.36), radius: 22, y: 12)
                    .rotationEffect(.degrees(1.2))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(height: 244)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Sections

    private var recommendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "为你推荐", subtitle: "根据你的口味挑选") {
                Button {
                    Task { await load(force: true) }
                } label: {
                    Label("换一批", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLoading)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(Array(feed.dropFirst().prefix(10))) { track in
                    TrackCard(track: track, source: "推荐")
                }
            }
        }
    }

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "热门音乐", subtitle: "此刻大家都在听") {
                Button("查看完整榜单") {
                    state.select(.discover)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 18),
                    GridItem(.flexible(), spacing: 18)
                ],
                spacing: 4
            ) {
                ForEach(Array(hotSongs.prefix(8))) { song in
                    HotSongRow(song: song, allSongs: hotSongs)
                }
            }
        }
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "音乐排行榜",
                subtitle: rankingNote.isEmpty ? "全站音乐区热门稿件" : rankingNote
            ) {
                Button("查看全部") { state.select(.discover) }
                    .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 0) {
                ForEach(Array(ranking.prefix(6).enumerated()), id: \.element.queueKey) { index, track in
                    TrackRow(track: track, index: index + 1, source: "排行榜", showCover: true, showAlbum: false)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "继续聆听", subtitle: "最近播放过的音乐") {
                Button("全部记录") { state.open(.history) }
                    .buttonStyle(SecondaryButtonStyle())
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(Array(state.library.recentlyPlayed.prefix(5))) { track in
                    TrackCard(track: track, source: "最近播放")
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 28) {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(0.055))
                .frame(height: 244)
                .redacted(reason: .placeholder)
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Color.primary.opacity(0.055))
                            .aspectRatio(1, contentMode: .fit)
                        Capsule().fill(Color.primary.opacity(0.06)).frame(height: 10)
                        Capsule().fill(Color.primary.opacity(0.04)).frame(width: 80, height: 8)
                    }
                }
            }
            .redacted(reason: .placeholder)
        }
    }

    // MARK: - Data

    private func load(force: Bool = false) async {
        if isLoading { return }
        if !force && !feed.isEmpty { return }
        isLoading = true
        errorText = nil
        async let feedTask = state.api.regionFeed(page: 1, count: 20)
        async let rankingTask = state.api.ranking(limit: 20)
        async let hotTask = state.api.hotSongs()

        do {
            let (newFeed, newRanking, newHot) = try await (feedTask, rankingTask, hotTask)
            if !newFeed.isEmpty { feed = newFeed }
            if !newRanking.items.isEmpty {
                ranking = newRanking.items
                rankingNote = newRanking.note
            }
            if !newHot.isEmpty { hotSongs = newHot }
        } catch {
            if feed.isEmpty { errorText = error.localizedDescription }
        }
        isLoading = false
    }
}

private struct HotSongRow: View {
    let song: HotSong
    let allSongs: [HotSong]

    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Text("\(song.rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(rankColor)
                .frame(width: 22, alignment: .leading)
            CoverArt(url: song.coverURL, cornerRadius: 6)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(song.singer)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let delta = song.rankDelta, delta != 0 {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(delta > 0 ? Theme.accent : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? Color.primary.opacity(0.045) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard song.isPlayable else { return }
            let tracks = allSongs.filter(\.isPlayable).map(\.track)
            let index = tracks.firstIndex(where: { $0.bvid == song.bvid }) ?? 0
            state.play(tracks, startingAt: index, source: "热歌榜")
        }
    }

    private var rankColor: Color {
        switch song.rank {
        case 1: return Theme.accent
        case 2...3: return Color(hex: 0xFFA94D)
        default: return Color.secondary.opacity(0.72)
        }
    }
}
#endif

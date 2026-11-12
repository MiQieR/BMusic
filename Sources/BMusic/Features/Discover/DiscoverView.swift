#if os(macOS)
import SwiftUI

private enum DiscoverTab: String, CaseIterable, Identifiable {
    case ranking, hot, region

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ranking: return "排行榜"
        case .hot: return "热歌榜"
        case .region: return "分区精选"
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var state: AppState

    @State private var tab: DiscoverTab = .ranking
    @State private var rankingResult: RankingResult?
    @State private var hotSongs: [HotSong] = []
    @State private var regionTracks: [Track] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var regionPage = 1
    @Namespace private var tabNamespace

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 208), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    SegmentedTabs(
                        items: DiscoverTab.allCases,
                        title: \.title,
                        selection: $tab,
                        namespace: tabNamespace
                    )
                    Spacer()
                    if tab == .region {
                        Button {
                            regionPage += 1
                            Task { await loadRegion(force: true) }
                        } label: {
                            Label("换一批", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isLoading)
                    }
                }

                switch tab {
                case .ranking:
                    rankingContent
                case .hot:
                    hotContent
                case .region:
                    regionContent
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .task(id: tab) { await loadCurrent() }
        .onReceive(NotificationCenter.default.publisher(for: .bmusicRefreshContent)) { _ in
            Task { await loadCurrent(force: true) }
        }
    }

    // MARK: - Ranking

    @ViewBuilder
    private var rankingContent: some View {
        if isLoading && rankingResult == nil {
            LoadingRows(count: 8)
        } else if let errorText, rankingResult == nil {
            errorState(errorText)
        } else if let result = rankingResult {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("全站音乐排行榜")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(result.note.isEmpty ? "每天更新，发现正在流行的声音" : result.note)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.play(result.items, startingAt: 0, source: "排行榜")
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                if result.items.count >= 3 {
                    HStack(spacing: 18) {
                        ForEach(Array(result.items.prefix(3).enumerated()), id: \.element.queueKey) { index, track in
                            PodiumCard(track: track, rank: index + 1, items: result.items)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(result.items.dropFirst(3).enumerated()), id: \.element.queueKey) { index, track in
                        TrackRow(
                            track: track,
                            index: index + 4,
                            source: "排行榜",
                            showCover: true,
                            showAlbum: false
                        )
                    }
                }
            }
        } else {
            EmptyStateView(symbol: "chart.bar", title: "榜单准备中")
        }
    }

    // MARK: - Hot

    @ViewBuilder
    private var hotContent: some View {
        if isLoading && hotSongs.isEmpty {
            LoadingRows(count: 8)
        } else if let errorText, hotSongs.isEmpty {
            errorState(errorText)
        } else if !hotSongs.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("B站热歌榜")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("综合播放、收藏与讨论热度")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        let tracks = hotSongs.filter(\.isPlayable).map(\.track)
                        state.play(tracks, startingAt: 0, source: "热歌榜")
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                VStack(spacing: 2) {
                    ForEach(hotSongs) { song in
                        HotSongListRow(song: song)
                    }
                }
            }
        } else {
            EmptyStateView(symbol: "flame", title: "热歌榜暂时为空")
        }
    }

    // MARK: - Region

    @ViewBuilder
    private var regionContent: some View {
        if isLoading && regionTracks.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 9) {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Color.primary.opacity(0.055))
                            .aspectRatio(1, contentMode: .fit)
                        Capsule().fill(Color.primary.opacity(0.06)).frame(height: 10)
                    }
                    .redacted(reason: .placeholder)
                }
            }
        } else if let errorText, regionTracks.isEmpty {
            errorState(errorText)
        } else if !regionTracks.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("音乐区精选")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("来自哔哩哔哩音乐区的编辑推荐")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.play(regionTracks, startingAt: 0, source: "分区推荐")
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(regionTracks) { track in
                        TrackCard(track: track, source: "分区推荐")
                    }
                }
            }
        } else {
            EmptyStateView(symbol: "square.grid.2x2", title: "暂时没有推荐")
        }
    }

    private func errorState(_ message: String) -> some View {
        EmptyStateView(
            symbol: "wifi.exclamationmark",
            title: "加载失败",
            message: message,
            actionTitle: "重试"
        ) {
            Task { await loadCurrent(force: true) }
        }
    }

    // MARK: - Data

    private func loadCurrent(force: Bool = false) async {
        if isLoading { return }
        switch tab {
        case .ranking:
            if rankingResult != nil && !force { return }
            isLoading = true
            errorText = nil
            do {
                rankingResult = try await state.api.ranking(limit: 30)
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        case .hot:
            if !hotSongs.isEmpty && !force { return }
            isLoading = true
            errorText = nil
            do {
                hotSongs = try await state.api.hotSongs()
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        case .region:
            await loadRegion(force: force)
        }
    }

    private func loadRegion(force: Bool = false) async {
        if isLoading { return }
        if !regionTracks.isEmpty && !force { return }
        isLoading = true
        errorText = nil
        do {
            regionTracks = try await state.api.regionFeed(page: max(1, regionPage), count: 24)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Ranking card

private struct PodiumCard: View {
    let track: Track
    let rank: Int
    let items: [Track]

    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                CoverArt(url: track.coverURL, cornerRadius: 13)
                    .aspectRatio(1.5, contentMode: .fit)
                Text("\(rank)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(rankColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
                    .padding(10)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            state.play(items, startingAt: rank - 1, source: "排行榜")
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.black.opacity(0.36)))
                        }
                        .buttonStyle(.plain)
                        .padding(9)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .hoverLift(hovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .padding(.top, 8)
                Text(track.artist.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            state.play(items, startingAt: rank - 1, source: "排行榜")
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Theme.accent
        case 2: return Color(hex: 0xFFA94D)
        default: return Color(hex: 0x8E9BFF)
        }
    }
}

// MARK: - Hot row

private struct HotSongListRow: View {
    let song: HotSong

    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(song.rank)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(rankColor)
                .frame(width: 30)

            CoverArt(url: song.coverURL, cornerRadius: 7)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(song.singer)
                    if !song.album.isEmpty {
                        Text("·")
                        Text(song.album)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let tag = song.achievements.first {
                Text(tag)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Theme.accent.opacity(0.10), in: Capsule())
                    .lineLimit(1)
            }

            if let delta = song.rankDelta, delta != 0 {
                HStack(spacing: 1) {
                    Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(abs(delta))")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundStyle(delta > 0 ? Theme.accent : Color.secondary)
                .frame(width: 34, alignment: .trailing)
            }

            Text(Formatters.playCount(song.heat))
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

            Button {
                guard song.isPlayable else { return }
                state.play(song.track, source: "热歌榜")
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.accentGradient))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .disabled(!song.isPlayable)
        }
        .padding(.horizontal, 10)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(hovering ? Color.primary.opacity(0.045) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard song.isPlayable else { return }
            state.play(song.track, source: "热歌榜")
        }
        .contextMenu {
            if song.isPlayable {
                TrackContextMenu(track: song.track)
            }
        }
    }

    private var rankColor: Color {
        switch song.rank {
        case 1: return Theme.accent
        case 2...3: return Color(hex: 0xFFA94D)
        default: return Color.secondary.opacity(0.68)
        }
    }
}
#endif

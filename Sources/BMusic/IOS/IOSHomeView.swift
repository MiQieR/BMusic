#if os(iOS)
import SwiftUI

struct IOSHomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var player: PlayerService
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var feed: [Track] = []
    @State private var ranking: [Track] = []
    @State private var hot: [HotSong] = []
    @State private var loading = true
    @State private var errorText: String?

    private var hourlyGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var isWide: Bool { sizeClass == .regular }
    private var hero: Track? { ranking.first ?? feed.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isWide ? 34 : 26) {
                header
                if loading && feed.isEmpty && ranking.isEmpty {
                    IOSLoadingRows(count: 7)
                        .padding(.top, 8)
                } else if let errorText, feed.isEmpty {
                    IOSEmptyState(
                        symbol: "wifi.exclamationmark",
                        title: "没能连接到哔哩哔哩",
                        message: errorText,
                        actionTitle: "重试"
                    ) { Task { await load(force: true) } }
                } else {
                    if let hero {
                        heroCard(hero)
                    }
                    if !feed.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            IOSSectionHeader(title: "为你推荐", subtitle: "根据你的口味挑选")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 13) {
                                    ForEach(feed.prefix(12)) { track in
                                        IOSAlbumCard(track: track, width: isWide ? 188 : 148)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    if !hot.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            IOSSectionHeader(title: "热歌榜", subtitle: "此刻大家都在听")
                            ForEach(Array(hot.prefix(6).enumerated()), id: \.element.id) { index, song in
                                IOSTrackRow(track: song.track, index: index + 1, showCover: false)
                                if index < min(hot.count, 6) - 1 {
                                    Divider().opacity(0.4).padding(.leading, 29)
                                }
                            }
                        }
                    }
                    if !ranking.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            IOSSectionHeader(title: "音乐排行榜", subtitle: "每日更新")
                            ForEach(Array(ranking.prefix(8).enumerated()), id: \.element.queueKey) { index, track in
                                IOSTrackRow(track: track, index: index + 1, showCover: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: isWide ? 980 : .infinity)
            .padding(.horizontal, isWide ? 24 : 16)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .background(IOSBackdrop())
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hourlyGreeting)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("发现好音乐")
                    .font(.system(size: isWide ? 34 : 27, weight: .bold, design: .rounded))
            }
            Spacer()
            Button {
                state.showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Button {
                if state.account != nil {
                    state.showSettings = true
                } else {
                    state.showLogin = true
                }
            } label: {
                if let account = state.account, !account.avatarURL.isEmpty {
                    CachedAsyncImage(url: account.avatarURL)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func heroCard(_ track: Track) -> some View {
        Button {
            state.play(track, source: "排行榜")
        } label: {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: track.coverURL)
                    .frame(height: isWide ? 300 : 178)
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.08), .black.opacity(0.66)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.55), .black.opacity(0.05), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .overlay(alignment: .trailing) {
                        Image(systemName: "music.note")
                            .font(.system(size: 96, weight: .black))
                            .foregroundStyle(.white.opacity(0.09))
                            .offset(x: 12, y: 18)
                    }
                HStack(alignment: .bottom, spacing: 12) {
                    CoverArt(url: track.coverURL, cornerRadius: 11)
                        .frame(width: isWide ? 132 : 92, height: isWide ? 132 : 92)
                        .clipped()
                        .shadow(color: .black.opacity(0.3), radius: 9, y: 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("今日推荐")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                            .textCase(.uppercase)
                            .tracking(1.2)
                        Text(track.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(track.artist.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.18), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func load(force: Bool) async {
        if !force, !feed.isEmpty { return }
        loading = true
        errorText = nil
        do {
            async let a = state.api.regionFeed(page: 1, count: 24)
            async let b = state.api.ranking(limit: 24)
            async let c = state.api.hotSongs()
            let (feedResult, rankingResult, hotResult) = try await (a, b, c)
            feed = feedResult
            ranking = rankingResult.items
            hot = hotResult
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

struct IOSBackdrop: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [Theme.accent.opacity(0.08), .clear, Theme.blue.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
#endif

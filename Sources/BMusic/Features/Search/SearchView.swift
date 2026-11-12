#if os(macOS)
import AppKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var state: AppState

    @State private var kind: SearchKind = .video
    @State private var results: [SearchItem] = []
    @State private var suggestions: [String] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var page = 1
    @State private var hasMore = false
    @State private var errorText: String?
    @State private var directLoading = false
    @FocusState private var fieldFocused: Bool
    @Namespace private var kindNamespace

    private let userColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16, alignment: .top)
    ]
    private let mediaColumns = [
        GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 18, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
                .padding(.horizontal, Theme.contentPadding)
                .padding(.top, 4)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if !suggestions.isEmpty && !hasSearched {
                        suggestionRow
                    }
                    content
                }
                .padding(.horizontal, Theme.contentPadding)
                .padding(.bottom, 110)
            }
        }
        .task(id: state.searchSubmission) {
            guard state.searchSubmission > 0 else { return }
            await performSearch(reset: true)
        }
        .task(id: state.searchQuery) {
            await loadSuggestions()
        }
        .onChange(of: kind) { _, _ in
            guard hasSearched else { return }
            Task { await performSearch(reset: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bmusicRefreshContent)) { _ in
            guard hasSearched else { return }
            Task { await performSearch(reset: true) }
        }
    }

    // MARK: - Header

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(fieldFocused ? Theme.accent : Color.secondary)
                    TextField("搜索音乐、UP 主或影视", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($fieldFocused)
                        .onSubmit(submit)
                    if !state.searchQuery.isEmpty {
                        Button {
                            state.searchQuery = ""
                            results = []
                            hasSearched = false
                            errorText = nil
                            fieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(fieldFocused ? 0.065 : 0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            fieldFocused ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.07),
                            lineWidth: 1
                        )
                )
                .animation(.easeOut(duration: 0.15), value: fieldFocused)

                Button {
                    submit()
                } label: {
                    Text("搜索")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 84)
                .disabled(state.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)

                if directLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26)
                }
            }

            HStack {
                SegmentedTabs(
                    items: SearchKind.allCases,
                    title: \.title,
                    selection: $kind,
                    namespace: kindNamespace
                )
                Spacer()
                if hasSearched && !results.isEmpty {
                    Text("共 \(results.count) 个结果")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var suggestionRow: some View {
        HStack(spacing: 7) {
            Text("猜你想搜")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(suggestions.prefix(5), id: \.self) { suggestion in
                Button {
                    state.searchQuery = suggestion
                    submit()
                } label: {
                    Text(suggestion)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.84))
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && results.isEmpty {
            LoadingRows(count: 7)
        } else if let errorText, results.isEmpty {
            EmptyStateView(
                symbol: "wifi.exclamationmark",
                title: "搜索没有完成",
                message: errorText,
                actionTitle: "重试"
            ) {
                Task { await performSearch(reset: true) }
            }
        } else if hasSearched && results.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "没有找到相关结果",
                message: "换个关键词，或者切换到其他类型试试。"
            )
        } else if !hasSearched {
            discovery
        } else {
            switch kind {
            case .video:
                videoResults
            case .user:
                userResults
            case .media:
                mediaResults
            }
        }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 26) {
            if !state.library.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("最近搜索")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("清除") {
                            state.library.clearSearches()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(state.library.recentSearches, id: \.self) { query in
                                Button {
                                    state.searchQuery = query
                                    submit()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 9))
                                        Text(query)
                                            .font(.system(size: 12))
                                    }
                                    .foregroundStyle(.primary.opacity(0.82))
                                    .padding(.horizontal, 11)
                                    .frame(height: 30)
                                    .background(Color.primary.opacity(0.05), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("搜索技巧")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 14) {
                    SearchTipCard(
                        symbol: "music.note",
                        title: "直接搜索歌名",
                        detail: "例如「富士山下」或「周杰伦」"
                    )
                    SearchTipCard(
                        symbol: "link",
                        title: "粘贴 BV / av 号",
                        detail: "粘贴视频编号即可直接播放"
                    )
                    SearchTipCard(
                        symbol: "person.2",
                        title: "找 UP 主",
                        detail: "切换到 UP 主查看全部投稿"
                    )
                }
            }

            if !state.library.recentlyPlayed.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("继续聆听")
                        .font(.system(size: 14, weight: .semibold))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 208), spacing: 20)],
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(Array(state.library.recentlyPlayed.prefix(5))) { track in
                            TrackCard(track: track, source: "最近播放")
                        }
                    }
                }
            }
        }
    }

    private var videoResults: some View {
        VStack(spacing: 0) {
            if let first = results.compactMap(\.searchTrack).first {
                HStack(spacing: 10) {
                    Button {
                        let tracks = results.compactMap(\.searchTrack)
                        state.play(tracks, startingAt: 0, source: "搜索 · \(state.searchQuery)")
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Text("包含 \(results.count) 首音乐")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        state.play(first, source: "搜索 · \(state.searchQuery)")
                    } label: {
                        Label("先听第一首", systemImage: "play.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.bottom, 10)
            }

            ForEach(results) { item in
                if let track = item.searchTrack {
                    SearchTrackRow(item: item, track: track)
                }
            }
        }
    }

    private var userResults: some View {
        LazyVGrid(columns: userColumns, alignment: .leading, spacing: 16) {
            ForEach(results) { item in
                UserResultCard(item: item)
            }
        }
    }

    private var mediaResults: some View {
        LazyVGrid(columns: mediaColumns, alignment: .leading, spacing: 18) {
            ForEach(results) { item in
                MediaResultCard(item: item)
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        fieldFocused = false
        state.searchQuery = query
        state.library.rememberSearch(query)
        state.searchSubmission += 1
    }

    private func loadSuggestions() async {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        do {
            try await Task.sleep(nanoseconds: 280_000_000)
        } catch {
            return
        }
        let newSuggestions = await state.api.searchSuggestions(query)
        guard !Task.isCancelled, state.searchQuery == query else { return }
        suggestions = newSuggestions
    }

    private func performSearch(reset: Bool) async {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let bvid = AVBV.directBVID(from: query) {
            directLoading = true
            defer { directLoading = false }
            do {
                let track = try await state.api.videoDetail(bvid: bvid)
                state.play(track, source: "搜索 · \(query)")
            } catch {
                errorText = error.localizedDescription
                hasSearched = true
                results = []
            }
            return
        }

        if isLoading { return }
        isLoading = true
        hasSearched = true
        errorText = nil
        if reset {
            page = 1
            results = []
        }
        do {
            let newItems = try await state.api.search(keyword: query, kind: kind, page: page)
            if reset {
                results = newItems
            } else {
                let existing = Set(results.map(\.id))
                results.append(contentsOf: newItems.filter { !existing.contains($0.id) })
            }
            hasMore = newItems.count >= 20
        } catch {
            if results.isEmpty { errorText = error.localizedDescription }
        }
        isLoading = false
    }

    private func loadMore() {
        guard !isLoading, hasMore else { return }
        page += 1
        Task { await performSearch(reset: false) }
    }
}

// MARK: - Video row

private struct SearchTrackRow: View {
    let item: SearchItem
    let track: Track

    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                CoverArt(url: item.coverURL, cornerRadius: 8)
                    .frame(width: 56, height: 56)
                if hovering {
                    RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.36))
                    Button {
                        state.play(track, source: "搜索 · \(state.searchQuery)")
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.subtitle)
                    Text("·")
                    Text(Formatters.playCount(item.playCount) + " 播放")
                    if let date = item.publishedAt {
                        Text("·")
                        Text(Formatters.relativeDate(date))
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Text(Formatters.duration(item.duration))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(hovering ? Color.primary.opacity(0.045) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            state.play(track, source: "搜索 · \(state.searchQuery)")
        }
        .contextMenu {
            TrackContextMenu(track: track)
            Button("在浏览器中打开") {
                if let url = track.webURL { NSWorkspace.shared.open(url) }
            }
        }
    }
}

// MARK: - User card

private struct UserResultCard: View {
    let item: SearchItem
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 13) {
            CachedAsyncImage(url: item.coverURL)
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .panelBackground(cornerRadius: 11)
        .contentShape(Rectangle())
        .onTapGesture {
            state.open(.artist(mid: item.artist.mid, name: item.title, avatar: item.coverURL))
        }
    }
}

// MARK: - Media card

private struct MediaResultCard: View {
    let item: SearchItem
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArt(url: item.coverURL, cornerRadius: 10)
                .aspectRatio(0.72, contentMode: .fit)
            Text(item.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
            HStack {
                Text(item.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("找相关视频") {
                    state.searchQuery = item.title
                    state.submitSearch()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.accent)
            }
        }
    }
}

private struct SearchTipCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: 11)
    }
}
#endif

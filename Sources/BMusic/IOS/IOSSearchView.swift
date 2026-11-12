#if os(iOS)
import SwiftUI

struct IOSSearchView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var kind: SearchKind = .video
    @State private var items: [SearchItem] = []
    @State private var suggestions: [String] = []
    @State private var loading = false
    @State private var searched = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                searchField
                    .padding(.bottom, 4)

                Picker("类型", selection: $kind) {
                    ForEach(SearchKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                if !focused, !suggestions.isEmpty, !searched {
                    suggestionList
                }

                if loading {
                    IOSLoadingRows(count: 7)
                } else if let errorText {
                    IOSEmptyState(symbol: "magnifyingglass", title: "搜索失败", message: errorText)
                } else if !searched {
                    recentSearches
                    explore
                } else if items.isEmpty {
                    IOSEmptyState(
                        symbol: "music.note.list",
                        title: "没有找到结果",
                        message: "换一个关键词试试，或直接粘贴 BV 号。"
                    )
                } else {
                    ForEach(items) { item in
                        resultRow(item)
                        Divider().opacity(0.35).padding(.leading, 58)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 130)
        }
        .background(IOSBackdrop())
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard query.isEmpty, !state.searchQuery.isEmpty else { return }
            query = state.searchQuery
            runSearch(query)
        }
        .onChange(of: query) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searched = false
                items = []
                suggestions = []
            }
            Task { await refreshSuggestions(value) }
        }
        .onChange(of: kind) { _, _ in
            if searched { runSearch(query) }
        }
        .onChange(of: state.searchQuery) { _, value in
            guard !value.isEmpty, value != query else { return }
            query = value
            runSearch(value)
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索音乐、UP 主", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { runSearch(query) }
            if !query.isEmpty {
                Button {
                    query = ""
                    searched = false
                    items = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    query = suggestion
                    focused = false
                    runSearch(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(suggestion)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.35).padding(.leading, 22)
            }
        }
    }

    private var recentSearches: some View {
        Group {
            if !state.library.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近搜索")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("清空") { state.library.clearSearches() }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    FlowChips(values: state.library.recentSearches) { value in
                        query = value
                        runSearch(value)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var explore: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("试试这些")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 8)
            FlowChips(values: ["崩坏：星穹铁道", "原神", "明日方舟", "洛天依", "周深", "春日影"]) { value in
                query = value
                runSearch(value)
            }
        }
    }

    private func resultRow(_ item: SearchItem) -> some View {
        Button {
            switch item.kind {
            case .video:
                if let track = item.searchTrack {
                    state.play(track, source: "搜索")
                    state.library.rememberSearch(query)
                }
            case .user:
                state.library.rememberSearch(query)
                ToastCenter.shared.show("长按可复制 UP 主空间链接")
            case .media:
                ToastCenter.shared.show("影视内容暂不支持播放")
            }
        } label: {
            HStack(spacing: 11) {
                CoverArt(url: item.coverURL, cornerRadius: 7)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if item.kind == .video {
                    Text(Formatters.duration(item.duration))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runSearch(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        query = trimmed
        searched = true
        focused = false
        state.library.rememberSearch(trimmed)
        loading = true
        errorText = nil
        Task {
            do {
                items = try await state.api.search(keyword: trimmed, kind: kind)
            } catch {
                errorText = error.localizedDescription
                items = []
            }
            loading = false
        }
    }

    private func refreshSuggestions(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !searched else {
            suggestions = []
            return
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !Task.isCancelled else { return }
        suggestions = await state.api.searchSuggestions(trimmed)
    }
}

struct FlowChips: View {
    let values: [String]
    var action: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button {
                    action(value)
                } label: {
                    Text(value)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
#endif

#if os(iOS)
import SwiftUI

private enum IOSDiscoverTab: String, CaseIterable, Identifiable {
    case ranking = "排行榜"
    case hot = "热歌"
    case region = "推荐"
    var id: String { rawValue }
}

struct IOSDiscoverView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: IOSDiscoverTab = .ranking
    @State private var tracks: [Track] = []
    @State private var hot: [HotSong] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                Picker("分类", selection: $tab) {
                    ForEach(IOSDiscoverTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)

                if loading {
                    IOSLoadingRows(count: 9)
                } else if let errorText {
                    IOSEmptyState(
                        symbol: "exclamationmark.triangle",
                        title: "加载失败",
                        message: errorText,
                        actionTitle: "重试"
                    ) { Task { await load() } }
                } else if tab == .hot {
                    ForEach(Array(hot.enumerated()), id: \.element.id) { index, song in
                        IOSTrackRow(track: song.track, index: index + 1)
                        if index < hot.count - 1 { Divider().opacity(0.4).padding(.leading, 58) }
                    }
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.queueKey) { index, track in
                        IOSTrackRow(track: track, index: index + 1)
                        if index < tracks.count - 1 { Divider().opacity(0.4).padding(.leading, 58) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 130)
        }
        .background(IOSBackdrop())
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    state.showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .task { await load() }
        .onChange(of: tab) { _, _ in Task { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            switch tab {
            case .ranking:
                tracks = try await state.api.ranking(limit: 50).items
            case .hot:
                hot = try await state.api.hotSongs()
            case .region:
                tracks = try await state.api.regionFeed(page: 1, count: 50)
            }
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}
#endif

#if os(macOS)
import SwiftUI

struct HeaderView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if !state.path.isEmpty {
                Button {
                    state.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.78))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .help("返回")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            if state.section != .search || !state.path.isEmpty {
                SearchField(text: $state.searchQuery, onSubmit: state.submitSearch)
            }
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.top, 24)
        .padding(.bottom, 10)
        .frame(height: 78)
    }

    private var title: String {
        if let destination = state.path.last {
            switch destination {
            case .liked: return "喜欢的音乐"
            case .history: return "最近播放"
            case .folder(_, let title): return title
            case .artist(_, let name, _): return name
            case .playlist(let id): return state.library.playlist(id)?.name ?? "歌单"
            }
        }
        switch state.section {
        case .home: return greeting
        case .discover: return "发现音乐"
        case .search: return "搜索"
        case .library: return "音乐库"
        case .downloads: return "已下载"
        }
    }

    private var subtitle: String {
        if let destination = state.path.last {
            switch destination {
            case .liked: return "\(state.library.likedTracks.count) 首歌曲"
            case .history: return "按播放时间排列"
            case .folder: return "来自哔哩哔哩收藏夹"
            case .artist: return "UP 主投稿"
            case .playlist(let id):
                let count = state.library.playlist(id)?.tracks.count ?? 0
                return "本地歌单 · \(count) 首歌曲"
            }
        }
        switch state.section {
        case .home: return "今天想听点什么？"
        case .discover: return "排行榜、热歌与分区精选"
        case .search: return "搜索视频音乐、UP 主与影视"
        case .library: return "收藏、歌单与最近播放"
        case .downloads: return "离线也能听的音乐"
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }
}
#endif

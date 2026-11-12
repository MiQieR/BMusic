#if os(macOS)
import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var state: AppState

    private var active: [DownloadItem] {
        state.downloads.items.filter { $0.state == .downloading || $0.state == .queued }
    }

    private var failed: [DownloadItem] {
        state.downloads.items.filter { $0.state == .failed }
    }

    private var completed: [DownloadItem] {
        state.downloads.items.filter { $0.state == .completed }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if state.downloads.items.isEmpty {
                    EmptyStateView(
                        symbol: "arrow.down.circle",
                        title: "还没有下载的音乐",
                        message: "在歌曲的右键菜单或正在播放页选择下载，即可离线收听。",
                        actionTitle: "去推荐看看"
                    ) {
                        state.select(.home)
                    }
                } else {
                    summary
                    if !active.isEmpty {
                        section(title: "正在下载", items: active)
                    }
                    if !failed.isEmpty {
                        section(title: "下载失败", items: failed)
                    }
                    if !completed.isEmpty {
                        section(title: "已完成", items: completed)
                    }
                }
            }
            .padding(.horizontal, Theme.contentPadding)
            .padding(.top, 6)
            .padding(.bottom, 110)
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.mint)
                    .frame(width: 42, height: 42)
                    .background(Theme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(completed.count) 首已下载")
                        .font(.system(size: 13, weight: .semibold))
                    Text("占用 \(Formatters.fileSize(state.downloads.totalBytes)) 空间")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !completed.isEmpty {
                Button {
                    state.downloads.clearCompleted()
                    ToastCenter.shared.show("已清理下载文件")
                } label: {
                    Label("清理已完成", systemImage: "trash")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(15)
        .panelBackground(cornerRadius: 14)
    }

    private func section(title: String, items: [DownloadItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Spacer()
            }
            VStack(spacing: 2) {
                ForEach(items) { item in
                    DownloadRow(item: item)
                }
            }
        }
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(url: item.track.coverURL, cornerRadius: 7)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.track.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.track.artist.displayName)
                    Text("·")
                    Text(item.quality.title)
                    if item.state == .completed {
                        Text("·")
                        Text(Formatters.fileSize(item.bytes))
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if item.state == .downloading || item.state == .queued {
                    ProgressView(value: item.progress)
                        .tint(Theme.accent)
                        .frame(width: 180)
                        .controlSize(.small)
                } else if let message = item.message, item.state == .failed {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                        .lineLimit(1)
                }
            }

            Spacer()

            stateBadge

            if hovering {
                if item.state == .failed {
                    IconButton(symbol: "arrow.clockwise", size: 12, help: "重试") {
                        state.downloads.retry(id: item.id, api: state.api)
                    }
                }
                if item.state == .completed {
                    IconButton(symbol: "play.fill", size: 12, help: "播放") {
                        state.play(item.track, source: "已下载")
                    }
                    IconButton(symbol: "folder", size: 12, help: "在 Finder 中显示") {
                        state.downloads.reveal(item)
                    }
                }
                if item.state == .downloading || item.state == .queued {
                    IconButton(symbol: "xmark", size: 11, help: "取消") {
                        state.downloads.cancel(id: item.id)
                    }
                }
                IconButton(symbol: "trash", size: 12, help: "删除") {
                    state.downloads.remove(id: item.id)
                }
            }
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
            if item.state == .completed {
                state.play(item.track, source: "已下载")
            }
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch item.state {
        case .completed:
            Label("已下载", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.mint)
        case .failed:
            Text("失败")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: 0xFF6B6B))
        case .downloading, .queued:
            Text(item.state == .queued ? "等待中" : "下载中")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
#endif

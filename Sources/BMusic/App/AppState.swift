import Combine
import Foundation
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case home, discover, search, library, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "推荐"
        case .discover: return "发现"
        case .search: return "搜索"
        case .library: return "音乐库"
        case .downloads: return "已下载"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .discover: return "safari"
        case .search: return "magnifyingglass"
        case .library: return "rectangle.stack"
        case .downloads: return "arrow.down.circle"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .discover: return "safari.fill"
        case .search: return "magnifyingglass"
        case .library: return "rectangle.stack.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }
}

enum DetailDestination: Hashable {
    case liked
    case history
    case folder(id: Int64, title: String)
    case artist(mid: Int64, name: String, avatar: String)
    case playlist(id: UUID)
}

@MainActor
final class AppState: ObservableObject {
    let client: BiliClient
    let api: BiliAPI
    let settings: SettingsStore
    let library: LibraryStore
    let downloads: DownloadStore
    let lyrics: LyricsService
    let player: PlayerService

    private var cancellables = Set<AnyCancellable>()

    @Published var section: SidebarSection = .home
    @Published var path: [DetailDestination] = []
    @Published var account: Account?
    @Published var favoriteFolders: [FavoriteFolder] = []
    @Published var isLoadingFolders = false
    @Published var isBootstrapping = true
    @Published var showLogin = false
    @Published var showSettings = false
    @Published var showNowPlaying = false
    @Published var searchQuery = ""
    @Published var searchSubmission = 0
    @Published var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        AppPaths.prepare()
        let jar = CookieJar(fileURL: AppPaths.cookies)
        let client = BiliClient(jar: jar)
        self.client = client
        let api = BiliAPI(client: client)
        self.api = api
        let settings = SettingsStore()
        self.settings = settings
        let library = LibraryStore()
        self.library = library
        let downloads = DownloadStore()
        self.downloads = downloads
        let lyrics = LyricsService(api: api)
        self.lyrics = lyrics
        self.player = PlayerService(
            api: api,
            library: library,
            downloads: downloads,
            settings: settings,
            lyrics: lyrics
        )

        let publishers: [ObservableObjectPublisher] = [
            settings.objectWillChange,
            library.objectWillChange,
            downloads.objectWillChange,
            lyrics.objectWillChange
        ]
        for publisher in publishers {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func bootstrap() async {
        guard isBootstrapping else { return }
        await api.bootstrap()
        account = await api.account()
        if account != nil {
            await loadFavoriteFolders()
        }
        isBootstrapping = false
    }

    func refreshAccount() async {
        account = await api.account()
        if account != nil {
            await loadFavoriteFolders()
        } else {
            favoriteFolders = []
        }
    }

    func loadFavoriteFolders() async {
        guard let account, !isLoadingFolders else { return }
        isLoadingFolders = true
        defer { isLoadingFolders = false }
        async let created = try? api.createdFolders(mid: account.mid)
        async let collected = try? api.collectedFolders(mid: account.mid)
        let all = ((await collected) ?? []) + ((await created) ?? [])
        var seen = Set<Int64>()
        favoriteFolders = all.filter { folder in
            seen.insert(folder.id).inserted
        }
    }

    func logout() {
        Task {
            await api.logout()
            account = nil
            favoriteFolders = []
            ToastCenter.shared.show("已退出登录")
        }
    }

    func select(_ section: SidebarSection) {
        if self.section != section {
            self.section = section
            path.removeAll()
        }
    }

    func open(_ destination: DetailDestination) {
        path.append(destination)
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func submitSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchQuery = trimmed
        library.rememberSearch(trimmed)
        searchSubmission += 1
        section = .search
        path.removeAll()
    }

    func search(_ query: String) {
        searchQuery = query
        submitSearch()
    }

    func play(_ track: Track, source: String) {
        player.play(track, sourceTitle: source)
    }

    func playAll(_ tracks: [Track], source: String) {
        guard !tracks.isEmpty else { return }
        player.play(tracks: tracks, startingAt: 0, sourceTitle: source)
    }

    func play(_ tracks: [Track], startingAt index: Int, source: String) {
        player.play(tracks: tracks, startingAt: index, sourceTitle: source)
    }

    func showNowPlayingPanel(_ panel: PlayerPanel) {
        showNowPlaying = true
        nowPlayingPanel = panel
    }

    @Published var nowPlayingPanel: PlayerPanel?

    func createPlaylist(named name: String) {
        let playlist = library.createPlaylist(name: name)
        ToastCenter.shared.success("已创建歌单「\(playlist.name)」")
    }
}

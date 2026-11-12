import CryptoKit
import Foundation

/// In-memory + on-disk image cache for Bilibili CDN artwork.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private var memory: [String: PlatformImage] = [:]
    private var order: [String] = []
    private var inflight: [String: Task<PlatformImage?, Never>] = [:]
    private let directory: URL
    private let session: URLSession

    init(directory: URL = AppPaths.images) {
        self.directory = directory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .returnCacheDataElseLoad
        let httpCache = AppPaths.caches.appendingPathComponent("HTTP", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: httpCache,
            withIntermediateDirectories: true
        )
        config.urlCache = URLCache(
            memoryCapacity: 0,
            diskCapacity: 50 * 1024 * 1024,
            diskPath: httpCache.path
        )
        session = URLSession(configuration: config)
    }

    func cached(_ raw: String) -> PlatformImage? {
        guard !raw.isEmpty else { return nil }
        return memory[raw]
    }

    func image(for raw: String) async -> PlatformImage? {
        guard !raw.isEmpty else { return nil }
        if let cached = memory[raw] { return cached }
        if let task = inflight[raw] { return await task.value }

        let task = Task<PlatformImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.load(raw)
        }
        inflight[raw] = task
        let image = await task.value
        inflight[raw] = nil
        if let image {
            store(image, for: raw)
        }
        return image
    }

    func clearDiskCache() {
        memory.removeAll()
        order.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Loading

    private func load(_ raw: String) async -> PlatformImage? {
        let key = Self.hash(raw)
        let diskURL = directory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: diskURL), let image = PlatformImage(data: data) {
            return image
        }

        guard let original = URL(string: raw) else { return nil }
        let candidates = [Self.thumbnailURL(for: original), original].compactMap { $0 }
        for url in candidates {
            if let data = try? await download(url), let image = PlatformImage(data: data) {
                try? data.write(to: diskURL, options: .atomic)
                return image
            }
        }
        return nil
    }

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(BiliClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw BiliError.network("图片加载失败")
        }
        return data
    }

    private func store(_ image: PlatformImage, for raw: String) {
        memory[raw] = image
        order.removeAll { $0 == raw }
        order.append(raw)
        while order.count > 240 {
            let evicted = order.removeFirst()
            memory.removeValue(forKey: evicted)
        }
    }

    // MARK: - URL shaping

    private static func thumbnailURL(for url: URL) -> URL? {
        guard let host = url.host,
              host.contains("hdslb.com"),
              !url.absoluteString.contains("@")
        else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let suffix = url.path.contains("/bfs/face/")
            ? "@160w_160h_1e_1c"
            : "@672w_378h_1e_1c"
        components?.path += suffix
        return components?.url
    }

    private static func hash(_ string: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

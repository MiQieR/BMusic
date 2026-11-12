import Foundation

enum AppPaths {
    static let root: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return support.appendingPathComponent("BMusic", isDirectory: true)
    }()

    static let caches: URL = {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? root
        return caches.appendingPathComponent("BMusic", isDirectory: true)
    }()

    static var cookies: URL { root.appendingPathComponent("session/cookies.json") }
    static var library: URL { root.appendingPathComponent("library.json") }
    static var downloads: URL { root.appendingPathComponent("Downloads", isDirectory: true) }
    static var lyrics: URL { caches.appendingPathComponent("Lyrics", isDirectory: true) }
    static var images: URL { caches.appendingPathComponent("Images", isDirectory: true) }
    static var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }

    static func prepare() {
        for directory in [
            root, caches, downloads, lyrics, images, logs,
            cookies.deletingLastPathComponent(),
            library.deletingLastPathComponent()
        ] {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }
}

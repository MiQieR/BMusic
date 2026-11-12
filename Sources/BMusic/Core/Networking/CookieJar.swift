import Foundation

struct CookieRecord: Codable, Hashable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresAt: Date?
    var isSecure: Bool
    var isHTTPOnly: Bool

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let cookieDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cookieDomain.isEmpty else { return false }
        guard host == cookieDomain || host.hasSuffix("." + cookieDomain) else { return false }

        if isSecure && url.scheme?.lowercased() != "https" { return false }

        let requestPath = url.path.isEmpty ? "/" : url.path
        if path == "/" { return true }
        guard requestPath.hasPrefix(path) else { return false }
        if requestPath.count == path.count { return true }
        // /foo must not match /foobar
        return requestPath.dropFirst(path.count).first == "/"
    }
}

private struct CookieArchive: Codable {
    var cookies: [CookieRecord]
    var refreshToken: String?
    var savedAt: Date
}

/// A small RFC-6265-style cookie jar.
///
/// `URLSession` cookie handling is disabled on purpose: the app owns the
/// session, persists it in its own Application Support folder, and can clear
/// it without touching Safari or any other app. No Keychain access is used.
@MainActor
final class CookieJar {
    private let fileURL: URL
    private(set) var cookies: [CookieRecord] = []
    private(set) var refreshToken: String = ""

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    var isLoggedIn: Bool {
        !(value(for: "SESSDATA") ?? "").isEmpty
    }

    var csrf: String { value(for: "bili_jct") ?? "" }

    func value(for name: String) -> String? {
        cookies
            .filter { $0.name == name && !$0.isExpired }
            .max(by: { $0.path.count < $1.path.count })?
            .value
    }

    func header(for url: URL) -> String? {
        if pruneExpired() { save() }
        let matched = cookies
            .filter { $0.matches(url) && !$0.isExpired }
            .sorted {
                if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
                return $0.name < $1.name
            }
        guard !matched.isEmpty else { return nil }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func set(
        name: String,
        value: String,
        domain: String = ".bilibili.com",
        path: String = "/",
        expiresAt: Date? = nil,
        isSecure: Bool = true,
        isHTTPOnly: Bool = false
    ) {
        cookies.removeAll {
            $0.name == name && $0.domain == domain && $0.path == path
        }
        cookies.append(
            CookieRecord(
                name: name,
                value: value,
                domain: domain,
                path: path,
                expiresAt: expiresAt,
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly
            )
        )
        save()
    }

    func ingest(setCookieHeader: String?, for url: URL) {
        guard let setCookieHeader, !setCookieHeader.isEmpty else { return }
        let parts = Self.splitSetCookieHeader(setCookieHeader)
        var changed = false
        for part in parts {
            if let cookie = HTTPCookie.cookies(
                withResponseHeaderFields: ["Set-Cookie": part],
                for: url
            ).first {
                upsert(cookie)
                changed = true
            } else if let record = Self.parseSetCookie(part, url: url) {
                upsert(record)
                changed = true
            }
        }
        if changed { save() }
    }

    func clearSession() {
        // Keep device identity cookies: without them the next request looks
        // like a brand-new client and is more likely to hit risk control.
        let keep: Set<String> = [
            "buvid3", "buvid4", "b_nut", "bili_ticket", "bili_ticket_expires",
            "_uuid", "b_lsid", "sid", "fingerprint", "fingerprint3"
        ]
        cookies.removeAll { !keep.contains($0.name) }
        refreshToken = ""
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(CookieArchive.self, from: data)
        else { return }
        cookies = archive.cookies
        refreshToken = archive.refreshToken ?? ""
        _ = pruneExpired()
    }

    private func save() {
        _ = pruneExpired()
        let archive = CookieArchive(
            cookies: cookies,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            savedAt: Date()
        )
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(archive)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            NSLog("[BMusic] cookie persistence failed: \(error.localizedDescription)")
        }
    }

    func storeRefreshToken(_ token: String) {
        refreshToken = token
        save()
    }

    /// 登录响应可能把会话 Cookie 记在 passport 子域上；统一提升到
    /// .bilibili.com，保证后续 api/web 请求都能带上。
    func promoteSessionCookies() {
        let session = ["SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5", "sid"]
        var changed = false
        for index in cookies.indices where session.contains(cookies[index].name) {
            if cookies[index].domain != ".bilibili.com" {
                cookies[index].domain = ".bilibili.com"
                cookies[index].path = "/"
                changed = true
            }
        }
        if changed { save() }
    }

    @discardableResult
    private func pruneExpired() -> Bool {
        let before = cookies.count
        cookies.removeAll { $0.isExpired }
        return cookies.count != before
    }

    private func upsert(_ cookie: HTTPCookie) {
        let expires = cookie.expiresDate
        if let expires, expires <= Date() {
            cookies.removeAll {
                $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
            }
            return
        }
        upsert(
            CookieRecord(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain.isEmpty ? ".bilibili.com" : cookie.domain,
                path: cookie.path.isEmpty ? "/" : cookie.path,
                expiresAt: expires,
                isSecure: cookie.isSecure,
                isHTTPOnly: cookie.isHTTPOnly
            )
        )
    }

    private func upsert(_ record: CookieRecord) {
        cookies.removeAll {
            $0.name == record.name && $0.domain == record.domain && $0.path == record.path
        }
        cookies.append(record)
    }

    // MARK: - Set-Cookie parsing

    private static func splitSetCookieHeader(_ header: String) -> [String] {
        // Split at commas that start a new `name=`. Expires contains a comma
        // ("Wed, 21 Oct …"), but the text after it never looks like `name=`.
        let pattern = ",(?=\\s*[A-Za-z0-9_!#$%&'*+.^`|~\\-]+=)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [header]
        }
        let ns = header as NSString
        let matches = regex.matches(in: header, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [header] }

        var pieces: [String] = []
        var start = 0
        for match in matches {
            let range = NSRange(location: start, length: match.range.location - start)
            pieces.append(ns.substring(with: range))
            start = match.range.location + match.range.length
        }
        pieces.append(ns.substring(from: start))
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseSetCookie(_ raw: String, url: URL) -> CookieRecord? {
        let parts = raw.split(separator: ";", omittingEmptySubsequences: false)
        guard let first = parts.first else { return nil }
        let pair = first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2 else { return nil }
        let name = String(pair[0]).trimmingCharacters(in: .whitespaces)
        let value = String(pair[1]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        var domain = url.host ?? ".bilibili.com"
        var path = "/"
        var expires: Date?
        var secure = false
        var httpOnly = false

        for attribute in parts.dropFirst() {
            let trimmed = attribute.trimmingCharacters(in: .whitespaces)
            let split = trimmed.split(separator: "=", maxSplits: 1)
            let key = split.first.map(String.init)?.lowercased() ?? ""
            let val = split.count > 1 ? String(split[1]) : ""
            switch key {
            case "domain":
                if !val.isEmpty { domain = val }
            case "path":
                if !val.isEmpty { path = val }
            case "expires":
                expires = cookieDateFormatter.date(from: val)
            case "max-age":
                if let seconds = TimeInterval(val) {
                    expires = Date().addingTimeInterval(seconds)
                }
            case "secure":
                secure = true
            case "httponly":
                httpOnly = true
            default:
                break
            }
        }

        return CookieRecord(
            name: name,
            value: value,
            domain: domain,
            path: path,
            expiresAt: expires,
            isSecure: secure,
            isHTTPOnly: httpOnly
        )
    }

    private static let cookieDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

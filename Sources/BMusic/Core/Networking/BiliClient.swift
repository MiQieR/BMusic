import Foundation

/// HTTP transport for Bilibili's web APIs.
///
/// Responsibilities kept in one place: headers and Referer, manual cookies,
/// WBI signing, risk-control retry, and Bilibili's `{code, message, data}`
/// envelope. API semantics live in `BiliAPI`.
@MainActor
final class BiliClient {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:153.0) Gecko/20100101 Firefox/153.0"
    static let apiBase = URL(string: "https://api.bilibili.com")!
    static let passportBase = URL(string: "https://passport.bilibili.com")!
    static let suggestBase = URL(string: "https://s.search.bilibili.com")!
    static let webBase = URL(string: "https://www.bilibili.com")!

    let jar: CookieJar
    private let session: URLSession
    private var wbiCache: WBIKeys?
    private var wbiTask: Task<WBIKeys, Error>?
    private var transportFailureCount = 0

    init(jar: CookieJar) {
        self.jar = jar
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [:]
        session = URLSession(configuration: config)
    }

    // MARK: - Bootstrap

    /// Device cookies make anonymous requests look consistent. Failure is
    /// non-fatal; playback and browsing still work without them.
    func bootstrapDeviceCookies() async {
        guard (jar.value(for: "buvid3") ?? "").isEmpty else { return }
        do {
            let envelope = try await envelope(
                path: "/x/frontend/finger/spi",
                base: Self.apiBase
            )
            guard let data = envelope["data"] as? [String: Any] else { return }
            let b3 = data.string("b_3")
            let b4 = data.string("b_4")
            if !b3.isEmpty {
                jar.set(name: "buvid3", value: b3, domain: ".bilibili.com")
            }
            if !b4.isEmpty {
                jar.set(name: "buvid4", value: b4, domain: ".bilibili.com")
            }
        } catch {
            NSLog("[BMusic] device cookie bootstrap skipped: \(error.localizedDescription)")
        }
    }

    // MARK: - WBI

    func wbiKeys(force: Bool = false) async throws -> WBIKeys {
        if !force, let cached = wbiCache,
           Date().timeIntervalSince(cached.fetchedAt) < 6 * 3600,
           !cached.mixinKey.isEmpty {
            return cached
        }
        if let task = wbiTask {
            return try await task.value
        }
        let task = Task<WBIKeys, Error> { [weak self] in
            guard let self else { throw BiliError.cancelled }
            let envelope = try await self.envelope(path: "/x/web-interface/nav", base: Self.apiBase, allowCodes: [-101])
            guard let data = envelope["data"] as? [String: Any],
                  let image = data.dict("wbi_img")
            else { throw BiliError.parse("WBI 口令缺失") }
            let imgKey = WBI.key(fromURL: image.string("img_url"))
            let subKey = WBI.key(fromURL: image.string("sub_url"))
            guard !imgKey.isEmpty, !subKey.isEmpty else {
                throw BiliError.parse("WBI 口令无效")
            }
            let keys = WBIKeys(imgKey: imgKey, subKey: subKey)
            guard !keys.mixinKey.isEmpty else {
                throw BiliError.parse("WBI 口令长度不足")
            }
            return keys
        }
        wbiTask = task
        do {
            let keys = try await task.value
            wbiCache = keys
            wbiTask = nil
            return keys
        } catch {
            wbiTask = nil
            throw error
        }
    }

    func invalidateWBI() {
        wbiCache = nil
        wbiTask?.cancel()
        wbiTask = nil
    }

    // MARK: - Public requests

    func envelope(
        path: String,
        base: URL = BiliClient.apiBase,
        query: [String: String] = [:],
        method: String = "GET",
        form: [String: String]? = nil,
        signed: Bool = false,
        allowCodes: Set<Int> = []
    ) async throws -> [String: Any] {
        var useSignature = signed
        var signatureRetried = false
        var transportRetried = false

        while true {
            do {
                return try await perform(
                    path: path,
                    base: base,
                    query: query,
                    method: method,
                    form: form,
                    signed: useSignature,
                    allowCodes: allowCodes
                )
            } catch let error as BiliError {
                if error.isRiskControl && !useSignature && !signatureRetried {
                    signatureRetried = true
                    useSignature = true
                    invalidateWBI()
                    continue
                }
                if case .network = error, !transportRetried {
                    transportRetried = true
                    transportFailureCount += 1
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continue
                }
                throw error
            }
        }
    }

    /// Returns the `data` field when it is a dictionary.
    func data(
        path: String,
        base: URL = BiliClient.apiBase,
        query: [String: String] = [:],
        signed: Bool = false,
        allowCodes: Set<Int> = []
    ) async throws -> [String: Any] {
        let envelope = try await envelope(
            path: path,
            base: base,
            query: query,
            signed: signed,
            allowCodes: allowCodes
        )
        return envelope["data"] as? [String: Any] ?? [:]
    }

    func post(
        path: String,
        base: URL = BiliClient.apiBase,
        form: [String: String] = [:],
        signed: Bool = false
    ) async throws -> [String: Any] {
        var body = form
        if !body.keys.contains("csrf") { body["csrf"] = jar.csrf }
        return try await envelope(
            path: path,
            base: base,
            method: "POST",
            form: body,
            signed: signed
        )
    }

    func fetchData(
        url: URL,
        referer: URL = BiliClient.webBase
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        if let cookie = jar.header(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BiliError.network("无效响应")
            }
            jar.ingest(setCookieHeader: http.value(forHTTPHeaderField: "Set-Cookie"), for: url)
            guard (200..<300).contains(http.statusCode) else {
                throw BiliError.http(http.statusCode)
            }
            return data
        } catch let error as BiliError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw BiliError.cancelled
        } catch {
            throw BiliError.network(error.localizedDescription)
        }
    }

    // MARK: - Transport

    private func perform(
        path: String,
        base: URL,
        query: [String: String],
        method: String,
        form: [String: String]?,
        signed: Bool,
        allowCodes: Set<Int>
    ) async throws -> [String: Any] {
        var finalQuery = query
        if signed {
            let keys = try await wbiKeys()
            finalQuery = WBI.sign(params: finalQuery, mixinKey: keys.mixinKey)
        }

        let url = try makeURL(path: path, base: base, query: finalQuery, canonical: signed)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(referer(for: base), forHTTPHeaderField: "Referer")
        if method == "POST" {
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = (form ?? [:]).map { "\(WBI.encode($0.key))=\(WBI.encode($0.value))" }
                .joined(separator: "&")
            request.httpBody = Data(body.utf8)
        }
        if let cookie = jar.header(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            let result = try await session.data(for: request)
            guard let http = result.1 as? HTTPURLResponse else {
                throw BiliError.network("无效响应")
            }
            data = result.0
            response = http
        } catch let error as BiliError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw BiliError.cancelled
        } catch {
            throw BiliError.network(error.localizedDescription)
        }

        jar.ingest(setCookieHeader: response.value(forHTTPHeaderField: "Set-Cookie"), for: url)

        if response.statusCode == 412 {
            throw BiliError.riskControl
        }
        guard (200..<300).contains(response.statusCode) else {
            throw BiliError.http(response.statusCode)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BiliError.parse("响应不是 JSON")
        }
        guard let envelope = object as? [String: Any] else {
            if let array = object as? [Any] {
                return ["code": 0, "data": array]
            }
            throw BiliError.parse("响应结构异常")
        }

        let code = envelope.int("code")
        if code != 0 && !allowCodes.contains(code) {
            let message = envelope.string("message")
            switch code {
            case -101:
                throw BiliError.notLoggedIn
            case -352, -412:
                throw BiliError.riskControl
            default:
                throw BiliError.api(code: code, message: message)
            }
        }
        return envelope
    }

    private func makeURL(
        path: String,
        base: URL,
        query: [String: String],
        canonical: Bool
    ) throws -> URL {
        guard var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw BiliError.parse("无法构造请求地址")
        }
        if query.isEmpty {
            components.percentEncodedQuery = nil
        } else if canonical {
            let body = query.keys.sorted().map { key in
                "\(WBI.encode(key))=\(WBI.encode(query[key] ?? ""))"
            }.joined(separator: "&")
            components.percentEncodedQuery = body
        } else {
            components.queryItems = query.keys.sorted().map {
                URLQueryItem(name: $0, value: query[$0])
            }
        }
        guard let url = components.url else {
            throw BiliError.parse("无法构造请求地址")
        }
        return url
    }

    private func referer(for base: URL) -> String {
        if base.host == Self.suggestBase.host {
            return "https://search.bilibili.com/"
        }
        return "https://www.bilibili.com/"
    }
}

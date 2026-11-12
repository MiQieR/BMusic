import Foundation
import Security

// MARK: - Models

/// `/x/passport-login/captcha` 返回的极验参数。token 需要贴着短信/密码提交一起回传。
struct GeeTestChallenge: Equatable {
    var token: String
    var gt: String
    var challenge: String

    var isComplete: Bool {
        !token.isEmpty && !gt.isEmpty && !challenge.isEmpty
    }
}

/// 极验通过后拿到的校验结果，回传给 passport 登录接口。
struct GeeTestResult: Equatable {
    var token: String
    var challenge: String
    var validate: String
    var seccode: String
}

/// 短信登录的国际冠字码（来自 `/web/generic/country/list`）。
struct CountryRegion: Identifiable, Hashable {
    var id: Int
    var name: String
    var dialCode: String

    /// 列表接口不可用时的兜底，保持默认中国大陆 +86。
    static let fallback: [CountryRegion] = [
        CountryRegion(id: 1, name: "中国大陆", dialCode: "86"),
        CountryRegion(id: 5, name: "中国香港特别行政区", dialCode: "852"),
        CountryRegion(id: 2, name: "中国澳门特别行政区", dialCode: "853"),
        CountryRegion(id: 3, name: "中国台湾", dialCode: "886"),
        CountryRegion(id: 4, name: "美国", dialCode: "1"),
        CountryRegion(id: 17, name: "日本", dialCode: "81"),
        CountryRegion(id: 18, name: "韩国", dialCode: "82"),
        CountryRegion(id: 30, name: "新加坡", dialCode: "65"),
        CountryRegion(id: 31, name: "马来西亚", dialCode: "60"),
        CountryRegion(id: 32, name: "泰国", dialCode: "66")
    ]
}

// MARK: - RSA password encryption

/// 密码登录的 RSA-PKCS1 加密：`base64(RSA_PKCS1(盐 + 明文密码))`。
/// B 站服务端已不再接受旧的 sha256 方案；公钥与盐约 20 秒有效，
/// 因此取 key 后要立刻加密提交。
enum PassportCrypto {
    static func encryptPassword(publicKeyPEM: String, salt: String, password: String) throws -> String {
        let base64 = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let spki = Data(base64Encoded: base64) ?? Data(base64Encoded: cleaned(base64)) else {
            throw BiliError.parse("登录公钥格式异常")
        }
        let pkcs1 = try rsaPublicKeyBits(fromSPKI: spki)
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            pkcs1 as CFData,
            [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic
            ] as CFDictionary,
            &error
        ) else {
            throw BiliError.parse("登录公钥解析失败：\(error.map { String(describing: $0.takeRetainedValue()) } ?? "")")
        }
        let plain = Data((salt + password).utf8)
        guard let encrypted = SecKeyCreateEncryptedData(
            secKey,
            .rsaEncryptionPKCS1,
            plain as CFData,
            &error
        ) as Data? else {
            throw BiliError.parse("密码加密失败：\(error.map { String(describing: $0.takeRetainedValue()) } ?? "")")
        }
        return encrypted.base64EncodedString()
    }

    /// `Data(base64Encoded:)` 严格要求合法字符；这里先做一次保守清洗。
    private static func cleaned(_ base64: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        return String(base64.unicodeScalars.filter { allowed.contains($0) })
    }

    /// X.509 SubjectPublicKeyInfo 里剥出 PKCS#1 RSAPublicKey：
    /// `SEQUENCE { SEQUENCE(alg) BIT STRING(key) }`。
    private static func rsaPublicKeyBits(fromSPKI data: Data) throws -> Data {
        var parser = DERParser(data: data)
        let outer = try parser.readTLV(tag: 0x30)
        var inner = DERParser(data: outer)
        _ = try inner.readTLV(tag: 0x30) // AlgorithmIdentifier
        let bits = try inner.readTLV(tag: 0x03)
        guard let first = bits.first, first == 0 else {
            throw BiliError.parse("登录公钥位数异常")
        }
        return bits.dropFirst()
    }
}

/// 极小 DER TLV 读取器，只覆盖本文件用到的结构。
private struct DERParser {
    private let bytes: [UInt8]
    private var offset: Int

    init(data: Data) {
        bytes = [UInt8](data)
        offset = 0
    }

    mutating func readTLV(tag: UInt8) throws -> Data {
        guard offset < bytes.count, bytes[offset] == tag else {
            throw BiliError.parse("登录公钥 DER 结构异常")
        }
        offset += 1
        guard offset < bytes.count else {
            throw BiliError.parse("登录公钥 DER 长度异常")
        }
        let first = bytes[offset]
        offset += 1
        let length: Int
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard count > 0, count <= 4, offset + count <= bytes.count else {
                throw BiliError.parse("登录公钥 DER 长度异常")
            }
            length = bytes[offset..<(offset + count)].reduce(0) { $0 << 8 | Int($1) }
            offset += count
        }
        guard offset + length <= bytes.count else {
            throw BiliError.parse("登录公钥 DER 内容越界")
        }
        let content = Data(bytes[offset..<(offset + length)])
        offset += length
        return content
    }
}

// MARK: - Passport endpoints

extension BiliAPI {
    /// 拉取极验参数。随后的验证弹窗由 `GeeTestFlow` 驱动。
    func loginCaptcha() async throws -> GeeTestChallenge {
        let data = try await client.data(
            path: "/x/passport-login/captcha",
            base: BiliClient.passportBase,
            query: ["source": "main_web"]
        )
        let challenge = GeeTestChallenge(
            token: data.string("token"),
            gt: data.dict("geetest")?.string("gt") ?? "",
            challenge: data.dict("geetest")?.string("challenge") ?? ""
        )
        guard challenge.isComplete else {
            throw BiliError.parse("人机验证参数缺失")
        }
        return challenge
    }

    /// 国际冠字码列表；失败时回退到内置常用地区。
    func loginCountries() async -> [CountryRegion] {
        do {
            let data = try await client.data(
                path: "/web/generic/country/list",
                base: BiliClient.passportBase
            )
            let rows = (data.array("common") ?? []) + (data.array("others") ?? [])
            let parsed: [CountryRegion] = rows.compactMap { raw in
                guard let raw = raw as? [String: Any] else { return nil }
                let dial = raw.string("country_id")
                guard !dial.isEmpty else { return nil }
                return CountryRegion(
                    id: raw.int("id"),
                    name: raw.string("cname"),
                    dialCode: dial
                )
            }
            return parsed.isEmpty ? CountryRegion.fallback : parsed
        } catch {
            return CountryRegion.fallback
        }
    }

    /// 向手机发送短信验证码，返回后续登录要用的 captcha_key。
    func sendSMSCode(
        country: CountryRegion,
        phone: String,
        captcha: GeeTestResult
    ) async throws -> String {
        let data = try await passportPost(
            path: "/x/passport-login/web/sms/send",
            form: [
                "cid": country.dialCode,
                "tel": phone,
                "source": "main-fe-header",
                "token": captcha.token,
                "challenge": captcha.challenge,
                "validate": captcha.validate,
                "seccode": captcha.seccode
            ]
        )
        let key = data.string("captcha_key")
        guard !key.isEmpty else {
            throw BiliError.parse("验证码发送结果缺失")
        }
        return key
    }

    /// 短信验证码登录。成功后 Cookie 已由 CookieJar 收下。
    @discardableResult
    func loginBySMS(
        country: CountryRegion,
        phone: String,
        code: String,
        captchaKey: String
    ) async throws -> String {
        let data = try await passportPost(
            path: "/x/passport-login/web/login/sms",
            form: [
                "cid": country.dialCode,
                "tel": phone,
                "code": code,
                "source": "main-fe-header",
                "captcha_key": captchaKey,
                "go_url": "https://www.bilibili.com/"
            ]
        )
        finishLogin(data: data)
        return data.string("refresh_token")
    }

    /// 账号密码登录。密码在提交前一刻用下发的公钥加密。
    @discardableResult
    func loginByPassword(
        username: String,
        password: String,
        captcha: GeeTestResult
    ) async throws -> String {
        // 公钥与盐 20 秒有效，必须贴着提交取（极验已经在前面过完）。
        let key = try await client.data(
            path: "/x/passport-login/web/key",
            base: BiliClient.passportBase
        )
        let hash = key.string("hash")
        let publicKey = key.string("key")
        guard !hash.isEmpty, !publicKey.isEmpty else {
            throw BiliError.parse("登录公钥缺失")
        }
        let encrypted = try PassportCrypto.encryptPassword(
            publicKeyPEM: publicKey,
            salt: hash,
            password: password
        )
        let data = try await passportPost(
            path: "/x/passport-login/web/login",
            form: [
                "username": username,
                "password": encrypted,
                "keep": "0",
                "token": captcha.token,
                "challenge": captcha.challenge,
                "validate": captcha.validate,
                "seccode": captcha.seccode,
                "source": "main-fe-header"
            ]
        )
        // code == 0 但 status != 0 是风控分支：要求绑定手机验证，本端未接入。
        let status = data.int("status")
        if status != 0 {
            throw BiliError.unavailable(
                data.string("message").isEmpty
                    ? "本次登录环境存在风险，请改用扫码或短信登录"
                    : data.string("message")
            )
        }
        finishLogin(data: data)
        return data.string("refresh_token")
    }

    private func passportPost(path: String, form: [String: String]) async throws -> [String: Any] {
        // 登录前没有 bili_jct，不能让 post() 注入空 csrf。
        try await client.envelope(
            path: path,
            base: BiliClient.passportBase,
            method: "POST",
            form: form
        )["data"] as? [String: Any] ?? [:]
    }

    private func finishLogin(data: [String: Any]) {
        let refresh = data.string("refresh_token")
        if !refresh.isEmpty {
            jar.storeRefreshToken(refresh)
        }
        jar.promoteSessionCookies()
    }
}

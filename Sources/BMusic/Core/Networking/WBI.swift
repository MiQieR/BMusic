import CryptoKit
import Foundation

struct WBIKeys: Sendable {
    var imgKey: String
    var subKey: String
    var mixinKey: String
    var fetchedAt: Date

    init(imgKey: String, subKey: String, fetchedAt: Date = Date()) {
        self.imgKey = imgKey
        self.subKey = subKey
        self.mixinKey = WBI.mixinKey(imgKey: imgKey, subKey: subKey)
        self.fetchedAt = fetchedAt
    }
}

/// Bilibili's WBI query signature.
///
/// Only a subset of endpoints require it (notably `space/wbi/*`). Requests opt
/// in explicitly; the transport can also retry once with a signature after a
/// risk-control response.
enum WBI {
    /// The 64-entry permutation shared by every implementation of the scheme.
    static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    static func mixinKey(imgKey: String, subKey: String) -> String {
        let raw = imgKey + subKey
        guard raw.count >= 64 else { return "" }
        let chars = Array(raw)
        var result = ""
        result.reserveCapacity(32)
        for index in 0..<32 {
            result.append(chars[mixinKeyEncTab[index]])
        }
        return result
    }

    /// Extract the key filename from `https://i0.hdslb.com/bfs/wbi/<key>.png`.
    static func key(fromURL raw: String) -> String {
        guard let url = URL(string: raw) else { return "" }
        let name = url.deletingPathExtension().lastPathComponent
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sign(
        params: [String: String],
        mixinKey: String,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> [String: String] {
        var merged = params
        merged["wts"] = String(timestamp)
        let sortedKeys = merged.keys.sorted()
        let canonical = sortedKeys.map { key in
            let filtered = filterReserved(merged[key] ?? "")
            return "\(encode(key))=\(encode(filtered))"
        }.joined(separator: "&")
        let signature = md5(canonical + mixinKey)
        var result = merged
        result["w_rid"] = signature
        return result
    }

    /// `!'()*` are left unescaped by `encodeURIComponent`; Bilibili strips
    /// them from values before signing, so drop them here as well.
    static func filterReserved(_ value: String) -> String {
        value.replacingOccurrences(
            of: "[!'()*]",
            with: "",
            options: .regularExpression
        )
    }

    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

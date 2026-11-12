import Foundation

enum AVBV {
    private static let xorCode: UInt64 = 23_442_827_791_579
    private static let base: UInt64 = 58
    private static let table = Array("FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf")

    /// Convert a numeric `aid` to a `BV1…` identifier using the public
    /// transformation used by Bilibili's web front end.
    static func av2bv(_ aid: Int64) -> String {
        guard aid > 0 else { return "" }
        var bytes = Array("BV1000000000")
        var index = bytes.count - 1
        var value = (UInt64(1) << 51) | UInt64(aid)
        value ^= xorCode
        while value > 0 {
            let remainder = Int(value % base)
            bytes[index] = table[remainder]
            value /= base
            index -= 1
            if index < 0 { break }
        }
        bytes.swapAt(3, 9)
        bytes.swapAt(4, 7)
        return String(bytes)
    }

    static func bv2av(_ bvid: String) -> Int64? {
        guard bvid.count == 12, bvid.hasPrefix("BV") else { return nil }
        var chars = Array(bvid)
        chars.swapAt(3, 9)
        chars.swapAt(4, 7)
        var value: UInt64 = 0
        for character in chars.dropFirst(3) {
            guard let index = table.firstIndex(of: character) else { return nil }
            value = value * base + UInt64(index)
        }
        value ^= xorCode
        value &= (UInt64(1) << 51) - 1
        return Int64(value)
    }

    static func directBVID(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 12, trimmed.hasPrefix("BV") {
            return trimmed
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("av"), let aid = Int64(trimmed.dropFirst(2)), aid > 0 {
            return av2bv(aid)
        }
        return nil
    }
}

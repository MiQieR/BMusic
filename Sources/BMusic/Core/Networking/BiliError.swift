import Foundation

enum BiliError: LocalizedError {
    case network(String)
    case http(Int)
    case api(code: Int, message: String)
    case parse(String)
    case notLoggedIn
    case riskControl
    case cancelled
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "网络连接失败：\(message)"
        case .http(let status):
            return "服务器返回 HTTP \(status)"
        case .api(_, let message):
            return message.isEmpty ? "接口请求失败" : message
        case .parse(let detail):
            return "数据解析失败：\(detail)"
        case .notLoggedIn:
            return "请先登录哔哩哔哩账号"
        case .riskControl:
            return "请求被风控拦截，请稍后再试"
        case .cancelled:
            return "请求已取消"
        case .unavailable(let message):
            return message
        }
    }

    var isRiskControl: Bool {
        if case .riskControl = self { return true }
        if case .api(let code, _) = self { return code == -352 || code == -412 }
        return false
    }
}

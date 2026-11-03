import Foundation

struct UsageWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    var title: String {
        guard let minutes = windowDurationMins else { return "额度周期" }
        if minutes == 10080 { return "每周额度" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
}
struct UsageBucket: Codable, Equatable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let planType: String?
    let rateLimitReachedType: String?
    var windows: [UsageWindow] { [primary, secondary].compactMap { $0 } }
    var title: String { limitName ?? limitId ?? "Codex" }
}
struct RateLimitsResponse: Decodable {
    let rateLimits: UsageBucket
    let rateLimitsByLimitId: [String: UsageBucket]?
    var buckets: [UsageBucket] {
        guard let map = rateLimitsByLimitId, !map.isEmpty else { return [rateLimits] }
        return map.keys.sorted { a, b in a == "codex" ? b != "codex" : (b == "codex" ? false : a < b) }.compactMap { map[$0] }
    }
}
struct UsageSnapshot: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let accountLabel: String?
    let buckets: [UsageBucket]
}
enum UsageFailure: String, Codable, Error, Sendable {
    case cliMissing, authentication, rateLimited, timeout, unavailable, incompatible, storage
    var message: String {
        switch self {
        case .cliMissing: return "未找到 Codex CLI，请在设置中选择可执行文件。"
        case .authentication: return "Codex 登录已失效，请在 Codex 中恢复登录后重试。"
        case .rateLimited: return "查询被限流，请稍后重试。"
        case .timeout: return "查询超时，请检查网络后重试。"
        case .unavailable: return "暂时无法读取额度，请检查网络与 Codex 状态。"
        case .incompatible: return "Codex 返回了无法识别的数据，请检查 CLI 版本。"
        case .storage: return "本地缓存无法读写，请检查目录权限。"
        }
    }
}
struct UsageState: Codable, Equatable, Sendable {
    var snapshot: UsageSnapshot?
    var lastAttempt: Date?
    var failure: UsageFailure?
    var refreshingSince: Date?
    var isRefreshing: Bool { isRefreshing(at: Date()) }
    func isRefreshing(at date: Date) -> Bool { refreshingSince.map { date.timeIntervalSince($0) < 50 } ?? false }
    func isStale(at date: Date = Date()) -> Bool {
        guard let snapshot else { return true }
        return failure != nil || date.timeIntervalSince(snapshot.fetchedAt) >= 3600
            || snapshot.buckets.flatMap(\.windows).contains { $0.resetDate.map { $0 <= date } ?? false }
    }
}

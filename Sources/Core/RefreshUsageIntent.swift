import AppIntents

struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "刷新 Codex 额度"
    static let description = IntentDescription("打开额度监视器并通过本机 Codex 登录状态读取真实额度。")
    static let openAppWhenRun: Bool = true
    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await UsageRefreshManager.shared.refresh()
        #endif
        return .result()
    }
}

import Foundation
import WidgetKit
import AppKit
import Darwin
import OSLog

@MainActor
final class UsageRefreshManager: ObservableObject {
    static let shared = UsageRefreshManager()
    @Published private(set) var state: UsageState
    private let store: UsageStore
    private let provider: any UsageDataProvider
    private let reloadWidgets: () -> Void
    private let logger = Logger(subsystem: "com.daltan.codexusage", category: "refresh")
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var busy = false
    init(store: UsageStore = UsageStore(), provider: any UsageDataProvider = CodexUsageDataProvider(),
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: UsageStore.widgetKind) }) {
        self.store = store; self.provider = provider; self.reloadWidgets = reloadWidgets; state = store.load()
    }
    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refreshIfDue() } }
    }
    func refreshIfDue(now: Date = Date()) async {
        let latest = store.load()
        if !busy { state = latest }
        let reference = latest.lastAttempt ?? .distantPast
        if now.timeIntervalSince(reference) >= UsageStore.refreshInterval { await refresh() }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        // Serialize GUI and --refresh-once runs; flock is released even after a crash.
        do { try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700]) }
        catch { state.failure = .storage; return }
        let fd = open(store.directory.appendingPathComponent("refresh.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { state.failure = .storage; return }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { state = store.load(); return }
        state = store.load()
        if let last = state.lastAttempt, Date().timeIntervalSince(last) < (state.failure == .rateLimited ? 300 : 10) {
            // A manual request can repair a stale widget without another server query.
            reloadWidgets()
            return
        }
        state.lastAttempt = Date(); state.refreshingSince = Date()
        // Do not reload the timeline with the old snapshot while a query is in flight.
        guard persist() else { state.refreshingSince = nil; return }
        logger.notice("Usage query started")
        do {
            let snapshot = try await provider.fetch()
            state.snapshot = snapshot; state.failure = nil
        } catch { state.failure = (error as? UsageFailure) ?? .unavailable }
        state.refreshingSince = nil
        if persist() {
            logger.notice("Usage query completed; requesting widget reload, success=\(self.state.failure == nil)")
            reloadWidgets()
        }
    }
    private func persist() -> Bool {
        do { try store.save(state); return true }
        catch {
            state.failure = .storage
            logger.error("Cache write failed; widget reload withheld")
            return false
        }
    }
}

import Foundation
import WidgetKit
import AppKit
import Darwin

@MainActor
final class UsageRefreshManager: ObservableObject {
    static let shared = UsageRefreshManager()
    @Published private(set) var state: UsageState
    private let store: UsageStore
    private let provider: any UsageDataProvider
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var busy = false
    init(store: UsageStore = UsageStore(), provider: any UsageDataProvider = CodexUsageDataProvider()) {
        self.store = store; self.provider = provider; state = store.load()
    }
    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refreshIfDue() } }
    }
    func refreshIfDue(now: Date = Date()) async {
        let latest = store.load()
        if !busy { state = latest }
        let reference = latest.lastAttempt ?? .distantPast
        if now.timeIntervalSince(reference) >= 3600 { await refresh() }
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
        if let last = state.lastAttempt, Date().timeIntervalSince(last) < (state.failure == .rateLimited ? 300 : 10) { return }
        state.lastAttempt = Date(); state.refreshingSince = Date()
        persist()
        do {
            let snapshot = try await provider.fetch()
            state.snapshot = snapshot; state.failure = nil
        } catch { state.failure = (error as? UsageFailure) ?? .unavailable }
        state.refreshingSince = nil
        persist()
    }
    private func persist() {
        do { try store.save(state) } catch { state.failure = .storage }
        WidgetCenter.shared.reloadTimelines(ofKind: UsageStore.widgetKind)
    }
}

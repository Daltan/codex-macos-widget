import XCTest
@testable import CodexUsageCore

/// Synthetic test-only values. These are never included in the app or widget.
final class UsageTests: XCTestCase {
    private func snapshot(at date: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(fetchedAt: date, accountLabel: nil, buckets: [
            UsageBucket(limitId: "codex", limitName: nil,
                        primary: UsageWindow(usedPercent: 37, windowDurationMins: 10080, resetsAt: date.addingTimeInterval(7200).timeIntervalSince1970),
                        secondary: nil, planType: nil, rateLimitReachedType: nil)])
    }
    func testMultiBucketAndMissingSecondary() throws {
        let json = #"{"rateLimits":{"primary":null},"rateLimitsByLimitId":{"other":{"limitId":"other","primary":{"usedPercent":120,"windowDurationMins":15}},"codex":{"limitId":"codex","primary":{"usedPercent":37,"windowDurationMins":10080},"secondary":null}},"futureField":true}"#
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.buckets.map(\.limitId), ["codex", "other"])
        XCTAssertEqual(response.buckets[0].windows.count, 1)
        XCTAssertEqual(response.buckets[0].windows[0].remaining, 63)
        XCTAssertEqual(response.buckets[0].windows[0].windowDurationMins, 10080)
        XCTAssertEqual(response.buckets[1].windows[0].remaining, 0)
    }
    func testFreshnessExpiresAtHourAndReset() {
        let date = Date(timeIntervalSince1970: 2_000_000)
        var state = UsageState(snapshot: snapshot(at: date))
        XCTAssertFalse(state.isStale(at: date))
        XCTAssertTrue(state.isStale(at: date.addingTimeInterval(3600)))
        state.failure = .authentication
        XCTAssertTrue(state.isStale(at: date))
        let reset = UsageWindow(usedPercent: 50, windowDurationMins: 300, resetsAt: date.timeIntervalSince1970)
        state = UsageState(snapshot: UsageSnapshot(fetchedAt: date, accountLabel: nil, buckets: [UsageBucket(limitId: nil, limitName: nil, primary: reset, secondary: nil, planType: nil, rateLimitReachedType: nil)]))
        XCTAssertTrue(state.isStale(at: date))
    }
    func testAtomicPersistenceAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageStore(directory: directory)
        let state = UsageState(snapshot: snapshot())
        try store.save(state)
        XCTAssertEqual(store.load(), state)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try Data("broken".utf8).write(to: store.file)
        XCTAssertEqual(store.load().failure, .storage)
        XCTAssertNil(store.load().snapshot)
    }
    @MainActor
    func testFailurePreservesSnapshotAndRestartRestores() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageStore(directory: directory), previous = snapshot(at: .now.addingTimeInterval(-4000))
        try store.save(UsageState(snapshot: previous))
        let manager = UsageRefreshManager(store: store, provider: FailingProvider())
        await manager.refresh()
        XCTAssertEqual(manager.state.snapshot, previous)
        XCTAssertEqual(manager.state.failure, .authentication)
        XCTAssertFalse(manager.state.isRefreshing)
        XCTAssertEqual(UsageRefreshManager(store: store, provider: FailingProvider()).state, manager.state)
    }
    @MainActor
    func testReloadObservesCompletedPersistedSnapshotOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageStore(directory: directory)
        let previous = snapshot(at: .now.addingTimeInterval(-600)), updated = snapshot()
        try store.save(UsageState(snapshot: previous))
        var reloaded: [UsageState] = []
        let manager = UsageRefreshManager(store: store, provider: CountingProvider(value: updated),
                                          reloadWidgets: { reloaded.append(store.load()) })
        await manager.refresh()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.snapshot, updated)
        XCTAssertNil(reloaded.first?.refreshingSince)
        XCTAssertNil(reloaded.first?.failure)
        // Rapid manual requests still re-deliver the final cache to a stale desktop.
        await manager.refresh()
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.last, reloaded.first)
    }

    @MainActor
    func testFailedQueryReloadsPreservedSnapshotWithError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageStore(directory: directory), previous = snapshot()
        try store.save(UsageState(snapshot: previous))
        var reloaded: [UsageState] = []
        let manager = UsageRefreshManager(store: store, provider: FailingProvider(),
                                          reloadWidgets: { reloaded.append(store.load()) })
        await manager.refresh()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.snapshot, previous)
        XCTAssertEqual(reloaded.first?.failure, .authentication)
        XCTAssertNil(reloaded.first?.refreshingSince)
    }

    @MainActor
    func testAutomaticRefreshAtFiveMinuteBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageStore(directory: directory), now = Date()
        let provider = CountingProvider(value: snapshot())
        try store.save(UsageState(snapshot: snapshot(), lastAttempt: now.addingTimeInterval(-300)))
        let manager = UsageRefreshManager(store: store, provider: provider, reloadWidgets: {})
        await manager.refreshIfDue(now: now.addingTimeInterval(-1))
        let before = await provider.count
        XCTAssertEqual(before, 0)
        await manager.refreshIfDue(now: now)
        let after = await provider.count
        XCTAssertEqual(after, 1)
    }

    @MainActor
    func testRateLimitCooldownDoesNotQueryAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageStore(directory: directory)
        let provider = CountingProvider(value: snapshot())
        try store.save(UsageState(snapshot: snapshot(), lastAttempt: .now.addingTimeInterval(-60),
                                  failure: .rateLimited))
        let manager = UsageRefreshManager(store: store, provider: provider, reloadWidgets: {})
        await manager.refresh()
        let count = await provider.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.load().failure, .rateLimited)
    }

    @MainActor
    func testAutomaticDueAndDedupe() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UsageStore(directory: directory)
        let provider = CountingProvider(value: snapshot())
        try store.save(UsageState(snapshot: snapshot(), lastAttempt: .now))
        let manager = UsageRefreshManager(store: store, provider: provider)
        await manager.refreshIfDue()
        let first = await provider.count
        XCTAssertEqual(first, 0)
        try store.save(UsageState(snapshot: snapshot(), lastAttempt: .now.addingTimeInterval(-3601)))
        await manager.refreshIfDue()
        await manager.refresh()
        let final = await provider.count
        XCTAssertEqual(final, 1)
        XCTAssertNil(manager.state.failure)
        XCTAssertNotNil(store.load().snapshot)
    }
}
private struct FailingProvider: UsageDataProvider {
    func fetch() async throws -> UsageSnapshot { throw UsageFailure.authentication }
}
private actor CountingProvider: UsageDataProvider {
    let value: UsageSnapshot
    var count = 0
    init(value: UsageSnapshot) { self.value = value }
    func fetch() async throws -> UsageSnapshot { count += 1; return value }
}

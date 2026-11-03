import XCTest
@testable import CodexUsageCore

final class TransportTests: XCTestCase {
    // Deliberately synthetic protocol peers, isolated from the real Codex login.
    private func peer(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("peer.py")
        try ("#!/usr/bin/python3\nimport sys,json,time\n" + body).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    func testTimeoutTerminatesUnresponsivePeer() async throws {
        let file = try peer("time.sleep(30)\n")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let start = Date()
        do {
            _ = try await CodexUsageDataProvider(executableOverride: file, timeout: 0.2).fetch()
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? UsageFailure, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testRawServiceErrorsAreClassifiedNotExposed() async throws {
        for (message, expected) in [("401 authentication expired", UsageFailure.authentication), ("429 rate limit", .rateLimited), ("network unavailable", .unavailable)] {
            let file = try peer("for line in sys.stdin:\n r=json.loads(line)\n if 'id' in r:\n  print(json.dumps({'id':r['id'],'error':{'code':-32000,'message':'\(message)'}}),flush=True)\n")
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            do {
                _ = try await CodexUsageDataProvider(executableOverride: file, timeout: 5).fetch()
                XCTFail("Expected classified failure")
            } catch { XCTAssertEqual(error as? UsageFailure, expected) }
        }
    }
    func testMalformedResponseDoesNotProduceAQuota() async throws {
        let file = try peer("sys.stdin.readline()\nprint('invalid-json',flush=True)\ntime.sleep(3)\n")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        do {
            _ = try await CodexUsageDataProvider(executableOverride: file, timeout: 5).fetch()
            XCTFail("Expected incompatible response")
        } catch { XCTAssertEqual(error as? UsageFailure, .incompatible) }
    }
}

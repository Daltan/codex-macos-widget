import Foundation
import Darwin

protocol UsageDataProvider: Sendable {
    func fetch() async throws -> UsageSnapshot
}

struct CodexUsageDataProvider: UsageDataProvider {
    var executableOverride: URL?
    var timeout: TimeInterval = 40
    func fetch() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) { try Self.read(executable: executableOverride, timeout: timeout) }.value
    }
    private static func read(executable: URL?, timeout: TimeInterval) throws -> UsageSnapshot {
        let process = Process()
        process.executableURL = try executable ?? AuthenticationManager.executable()
        process.arguments = ["app-server", "--stdio"]
        // No shell, no token handling, no stdout/stderr logging.
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let input = Pipe(), output = Pipe()
        // A crashing CLI must become an error, not terminate the monitor with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UsageFailure.cliMissing }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let end = Date().addingTimeInterval(1)
                while process.isRunning && Date() < end { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "codex_usage_monitor", "version": "1.0.0"], "capabilities": [:]]])
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var label: String?
        while Date() < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; throw UsageFailure.unavailable }
            if ready == 0 { continue }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw UsageFailure.unavailable }
            buffer.append(chunk)
            guard buffer.count <= 4_194_304 else { throw UsageFailure.incompatible }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw UsageFailure.incompatible
                }
                guard let id = message["id"] as? Int else { continue }
                if let error = message["error"] as? [String: Any] {
                    // Classify in memory; never display or persist raw backend errors.
                    let text = (error["message"] as? String ?? "").lowercased()
                    if text.contains("401") || text.contains("auth") || text.contains("login") { throw UsageFailure.authentication }
                    if text.contains("429") || text.contains("rate limit") { throw UsageFailure.rateLimited }
                    throw UsageFailure.unavailable
                }
                guard let result = message["result"] as? [String: Any] else { throw UsageFailure.incompatible }
                switch id {
                case 1:
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
                case 2:
                    guard let account = result["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
                        throw UsageFailure.authentication
                    }
                    // Mask account email before writing a local snapshot.
                    if let email = account["email"] as? String, let at = email.firstIndex(of: "@") {
                        label = String(email.prefix(1)) + "•••" + String(email[at...])
                    }
                    try send(["id": 3, "method": "account/rateLimits/read"])
                case 3:
                    do {
                        let data = try JSONSerialization.data(withJSONObject: result)
                        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
                        guard !response.buckets.isEmpty,
                              response.buckets.flatMap(\.windows).allSatisfy({ $0.usedPercent.isFinite && $0.usedPercent >= 0 }) else {
                            throw UsageFailure.incompatible
                        }
                        return UsageSnapshot(fetchedAt: Date(), accountLabel: label, buckets: response.buckets)
                    } catch { throw UsageFailure.incompatible }
                default: continue
                }
            }
        }
        throw UsageFailure.timeout
    }
}

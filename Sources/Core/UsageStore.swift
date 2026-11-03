import Foundation
import Darwin
import OSLog

struct UsageStore: Sendable {
    static let widgetKind = "CodexUsageWidget"
    let directory: URL
    init(directory: URL? = nil) {
        let home = URL(fileURLWithPath: String(cString: getpwuid(getuid()).pointee.pw_dir))
        self.directory = directory ?? home.appendingPathComponent("Library/Application Support/CodexUsage", isDirectory: true)
    }
    var file: URL { directory.appendingPathComponent("usage.json") }
    func load() -> UsageState {
        do { return try JSONDecoder().decode(UsageState.self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return UsageState() }
        catch {
            let ns = error as NSError
            Logger(subsystem: "com.daltan.codexusage", category: "cache").error("Cache read failed: domain=\(ns.domain, privacy: .public), code=\(ns.code), path=\(file.path, privacy: .public)")
            return UsageState(failure: .storage)
        }
    }
    func save(_ state: UsageState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

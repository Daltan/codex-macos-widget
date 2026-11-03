import Foundation

/// Credentials stay entirely inside Codex. This type only locates its executable.
struct AuthenticationManager {
    static func executable() throws -> URL {
        let configured = UserDefaults.standard.string(forKey: "codexExecutable")
        let candidates = [configured, "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          "/Applications/Codex.app/Contents/Resources/codex",
                          "/Applications/ChatGPT.app/Contents/Resources/codex"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UsageFailure.cliMissing
        }
        return URL(fileURLWithPath: path)
    }
}

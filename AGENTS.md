# Repository Guidelines

## Project Structure & Module Organization

- `Sources/App/`: SwiftUI application, CLI discovery, Codex protocol adapter, and refresh coordination.
- `Sources/Core/`: shared models, cache storage, views, and refresh App Intent.
- `Sources/Widget/`: WidgetKit timeline provider and small, medium, and large layouts.
- `Tests/`: XCTest model, persistence, scheduling, and isolated transport tests.
- `Config/`: application and extension plists and entitlements.
- `Scripts/`: build, installation, project generation, LaunchAgent management, and secret scanning.
- `CodexUsage.xcodeproj`: application and extension targets; `Package.swift` builds the testable core. `Docs/VALIDATION.md` records verification evidence. No separate asset catalog currently exists.

## Build, Test, and Development Commands

Run from the repository root with full Xcode installed:

```sh
Scripts/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 Scripts/scan-secrets.py
```

These build and verify the Release app, run XCTest, and scan tracked/nonignored files for credential patterns. Build products are under `.build/DerivedData`.

`Scripts/install-app.sh` installs into `~/Applications` and launches the app; quit the existing instance first. Alternatively, open `CodexUsage.xcodeproj` and run the `CodexUsage` scheme.

When changing target membership or build settings, update `Scripts/generate-project.py`, run it, and commit the regenerated project together.

## Coding Style & Naming Conventions

Use four-space indentation for Swift and Python. Use `UpperCamelCase` for types and `lowerCamelCase` for methods and properties; name Swift files after their principal type. Prefer immutable values, explicit error categories, and `@MainActor` for observable UI state. Preserve the provider/storage/UI separation and existing Chinese interface copy. No dedicated formatter or linter is configured; keep builds warning-free and run `git diff --check`.

## Testing Guidelines

Name XCTest methods `test<Behavior>`. Add regression coverage for changed parsing, freshness, persistence, concurrency, or transport behavior; no numerical coverage threshold is configured. Keep synthetic responses in tests and temporary directories, never production fallbacks. UI changes require actual app and widget checks across sizes and appearances; record evidence and limitations in `Docs/VALIDATION.md`.

## Commit & Pull Request Guidelines

Existing commits use short imperative subjects, such as `Build native macOS Codex usage monitor with verified desktop widgets`; no Conventional Commits requirement exists. PRs should explain the behavior change, relevant issue, validation commands/results, and limitations. Include redacted screenshots for UI changes.

## Security & Configuration

Delegate authentication to Codex and keep queries read-only. Never commit credentials, certificates, profiles, caches, or raw responses. Preserve stale successful snapshots on errors. Keep widget cache permissions narrowly scoped. Obtain user authorization before installing or changing LaunchAgents or modifying system/Codex configuration.

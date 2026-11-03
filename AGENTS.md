# Repository Guidelines

## Project Structure & Module Organization

- `Sources/App/`: SwiftUI application, CLI discovery, Codex protocol adapter, and refresh coordination.
- `Sources/Core/`: shared models, cache storage, views, and refresh App Intent.
- `Sources/Widget/`: WidgetKit timeline provider and small and medium layouts.
- `Tests/`: XCTest model, persistence, scheduling, and isolated transport tests.
- `Config/`: application and extension plists and entitlements.
- `Scripts/`: build, installation, project generation, LaunchAgent management, and secret scanning.
- `CodexUsage.xcodeproj`: application and extension targets; `Package.swift` builds the testable core. `Docs/VALIDATION.md` records verification evidence. Asset catalogs live under `Sources/App/` and `Sources/Core/`; shared English and Simplified Chinese strings live under `Sources/Core/Resources/`.

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

## Local Temporary Outputs

Use the repository-root `.tmp/` directory for local drafts, exploratory scripts, promotional exports, screenshots for inspection, and other developer-specific temporary outputs. It is ignored by Git and is not part of the source archive or release assets. Create it when needed; do not add a tracked placeholder or force-add its contents. Existing local promotional files live under `.tmp/output/social-promo/`.

Keep reproducible build products and release recovery state under the existing `.build/` paths; do not move or delete pending release manifests or frozen artifacts. Promote temporary content into a tracked location only when it is intentionally part of the deliverable, after checking for private data. Repository housekeeping and ignore-rule changes do not require a binary release.

## Coding Style & Naming Conventions

Use four-space indentation for Swift and Python. Use `UpperCamelCase` for types and `lowerCamelCase` for methods and properties; name Swift files after their principal type. Prefer immutable values, explicit error categories, and `@MainActor` for observable UI state. Preserve the provider/storage/UI separation and existing Chinese interface copy. No dedicated formatter or linter is configured; keep builds warning-free and run `git diff --check`.

## Testing Guidelines

Name XCTest methods `test<Behavior>`. Add regression coverage for changed parsing, freshness, persistence, concurrency, or transport behavior; no numerical coverage threshold is configured. Keep synthetic responses in tests and temporary directories, never production fallbacks. UI changes require actual app and widget checks across sizes and appearances; record evidence and limitations in `Docs/VALIDATION.md`.

## Commit & Pull Request Guidelines

Existing commits use short imperative subjects, such as `Build native macOS Codex usage monitor with verified desktop widgets`; no Conventional Commits requirement exists. PRs should explain the behavior change, relevant issue, validation commands/results, and limitations. Include redacted screenshots for UI changes.

## Security & Configuration

Delegate authentication to Codex and keep queries read-only. Never commit credentials, certificates, profiles, caches, or raw responses. Preserve stale successful snapshots on errors. Keep widget cache permissions narrowly scoped. Obtain user authorization before installing or changing LaunchAgents or modifying system/Codex configuration.


## Required Agent Delivery Loop

The user wants completed delivery without manually managing versions, tags, or Release assets. For user-requested application features, fixes, or distribution changes, finish the loop below by default unless the user explicitly says not to publish. Documentation-only changes need a commit/push, not a new binary release. Do not publish unrelated work or manufacture a release when nothing changed.

1. **Inspect**: read `git status`, fetch `origin/main`, and inspect the latest release/tag. Work on `main`; do not create an extra branch unless requested. Preserve unrelated changes and local files (including `.tmp/`); stage only the task's files.
2. **Implement and validate**: add appropriate regression coverage, maintain English and Simplified Chinese resources, and record actual evidence/limitations in `Docs/VALIDATION.md`. UI rendering is not proof of desktop-host behavior. Update `Scripts/generate-project.py` and regenerate the project when membership/settings change.
3. **Commit**: commit the requested implementation. Never use `git add .` to sweep in unrelated material. Do not manually edit bundle version/build numbers during implementation; the release tool owns them.
4. **Choose the version**: use SemVer—patch for fixes, minor for compatible features (such as bilingual UI), major for intentional breaking changes. State the choice in a progress update; routine patch/minor selection does not need another permission question. Write concise bilingual release notes describing changes, installation, compatibility and real validation limits in an ignored temporary file.
5. **Run**: `python3 Scripts/release.py run --bump minor --notes-file .tmp/next-release.md` (choose the appropriate bump). This synchronizes app/widget versions, increments build, commits versioned notes, tests/builds from a committed-source archive, checks DMG/ZIP contents, pushes main, creates/pushes an annotated tag, uploads a draft release, checks downloads, publishes, then anonymously downloads and verifies every asset.
6. **Recover**: if anything fails after preparation, inspect the phase log and run `python3 Scripts/release.py publish` after fixing the cause. Do not run `run` again and bump a second time. Keep `.build/release-loop/<tag>/`; cached assets are bound to the exact source SHA. Never force-push/reassign a published tag, delete old releases, or use `gh release upload --clobber`. If source changes are required after tagging, use a new version.
7. **Verify and report**: only claim completion when the receipt reports published status plus successful anonymous download checks and the remote tag resolves to the built source. Return the release link, version/build, validation outcome, and relevant limitations. A successful build, pushed commit, uploaded draft, or queued workflow is not a completed release. Distinguish the published binary from the locally installed app; update the installed app when the task calls for it, then verify its bundle version.

Use Git and GitHub CLI (`gh`) for all repository and release operations. Do not use Computer Use for release forms, uploads, or tags. If `gh` is missing, install it from the official/Homebrew distribution; if login is missing, explain the exact authentication step and use `gh auth login` rather than asking for a token in chat. Browser/device confirmation may require the user, but this is one-time authentication, not a per-release process. Never change system/Codex settings or add LaunchAgents as part of releasing.

The detailed contract and retry commands are in `Docs/RELEASING.md`. The current standing release authorization covers this workflow; do not repeatedly ask for permission for its ordinary commit/tag/upload/publish steps. Stop for an actual credential/permission blocker, divergent upstream history, tag conflict, failed validation, or unexpected unrelated changes.

# Contributing / 参与贡献

Small, focused contributions are welcome. Start with an issue for substantial behavior changes. Useful areas: Codex CLI compatibility, accessibility, English UI localization, and validation on other Macs.

欢迎小而明确的改进。较大行为变更请先开 Issue 讨论；欢迎 CLI 兼容性、无障碍、英文本地化及其他 Mac 上的验证反馈。

## Local checks / 本地检查

```sh
Scripts/build.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 Scripts/scan-secrets.py
git diff --check
```

- Keep provider, persistence, and UI separate; use four-space indentation.
- Add regression tests for parsing, freshness, persistence, concurrency, or transport changes.
- Update `Scripts/generate-project.py` when changing resources or target membership, then regenerate the Xcode project.
- Verify UI changes in both widget sizes and appearances. Include redacted screenshots and record limitations in `Docs/VALIDATION.md`.
- Never add synthetic production fallbacks, credentials, caches, raw API responses, signing material, or identifiable account details.
- Explain what changed, why, and which checks passed. Do not describe untested behavior as verified.

保持数据适配、存储与 UI 分离；数据逻辑变更应有回归测试。UI 修改请检查小/中尺寸及明暗外观，附脱敏截图。禁止提交凭据、真实缓存、原始接口响应或签名材料。请在 PR 中说明变更原因、验证结果和未验证的边界。

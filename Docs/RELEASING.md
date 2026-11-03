# 构建与发布安装包

普通用户直接从 [GitHub Releases](https://github.com/Daltan/codex-macos-widget/releases) 下载 DMG 或 ZIP，无需安装 Xcode。安装步骤和临时签名限制见 [INSTALL.txt](INSTALL.txt)。

## 构建

在完整 Xcode 的 macOS 上运行：

```sh
Scripts/build.sh
```

构建完成后会自动运行 `Scripts/package-release.sh`，从已构建应用的 Info.plist 读取版本和 build 号，输出到 `.build/releases/Codex-Usage-<version>-<build>-universal/`：

- `.dmg`：应用、Applications 快捷方式和双语安装说明。
- `.zip`：保留应用 bundle、符号链接及资源的 ZIP 备选包。
- `INSTALL.txt`：双语安装、升级、首次启动及限制说明。
- `SHA256SUMS.txt`：以上三个文件的 SHA-256 校验值。

打包前检查签名，确认主应用和扩展同时包含 arm64 / x86_64；DMG 创建后进行完整性验证。只复制应用 bundle，不包含本地缓存、认证数据、日志或签名材料。已有构建可通过 `Scripts/package-release.sh` 重新打包；发布前应重新执行完整构建，避免打包旧版本。

## 发布

1. 确认待发布源码已提交并同步到 GitHub，主应用与扩展版本一致。
2. 运行 `Scripts/build.sh`、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`、`python3 Scripts/scan-secrets.py` 和 `git diff --check`。
3. 挂载 DMG 并解压 ZIP，检查包内应用签名与版本；执行 `shasum -a 256 -c SHA256SUMS.txt`。
4. 在 GitHub Releases 创建对应版本，tag 指向构建时的确切提交。上传上述四个文件；不要将二进制提交到 Git 仓库。
5. Release 说明列出系统要求、安装方式、功能变化和未公证/跨机器未验证的限制。
6. 发布后重新读取 Release 附件列表，并下载校验文件与安装包核对散列值。不要以页面提交成功代替附件可下载的验证。

如使用已登录的 GitHub CLI，可用以下命令上传到已创建的 Release（不加 `--clobber`，避免覆盖已发布附件）：

```sh
gh release upload <tag> .build/releases/Codex-Usage-<version>-<build>-universal/* \
  --repo Daltan/codex-macos-widget
```

当前为 ad-hoc 签名，未使用 Developer ID、未公证。DMG 包装不会改变签名状态；其他 Mac 和 Intel 实机的首次安装、小组件加载仍需独立验证。

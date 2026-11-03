# 自动发布闭环 / Release workflow

后续应用功能、修复和分发改动，由 Agent 默认完成版本管理、验证、tag、Release 与下载回验。用户无需手工创建 tag 或上传文件。仅文档修改通常不发二进制版；用户明确要求暂不发布时，以用户指令为准。

## 一条命令

前提：完整 Xcode、Python 3、Git，以及已登录的 GitHub CLI。首次登录只需执行 `gh auth login`；不需要把 Token 发到聊天。仓库日常只保留 `main`。

先提交实现代码，再由 Agent 在 Git 忽略的 `.tmp/` 中写好中英发布说明。本地草稿、宣传素材等临时输出也统一放在 `.tmp/`，不进入发布；构建产物和断点恢复状态仍保存在 `.build/`：

```sh
mkdir -p .tmp
python3 Scripts/release.py plan
python3 Scripts/release.py run --bump minor --notes-file .tmp/next-release.md
```

`patch` 用于修复，`minor` 用于兼容的新功能，`major` 用于破坏性变化。发布工具将当前 `1.0` 这种历史版本正规化为三段版本；例如 minor 升级为 `1.1.0`。主应用与扩展的版本、build 号始终一起变更。build 每次发布准备时递增一次。

## 自动完成的步骤

1. 检查当前分支是 main、已跟上 origin/main、已跟踪文件没有未提交更改、GitHub 登录及 Xcode 可用。未跟踪内容不加入提交，也不进入构建。
2. 更新两个 Info.plist 的版本和 build，将说明写入 `Docs/ReleaseNotes/vX.Y.Z.md`，提交版本准备变更。
3. 将确切提交导出到隔离临时目录，执行 Python 工作流回归测试、Swift 测试、凭据扫描、Release 构建和打包。
4. 校验 app/扩展版本、签名与双架构；挂载 DMG、解压 ZIP，与构建应用逐文件比较；验证安装说明、Applications 快捷方式和 SHA-256。
5. 推送 main，创建 annotated tag `vX.Y.Z` 并推送，回读 tag 的提交 SHA。
6. 创建 Draft Release，上传 DMG、ZIP、INSTALL.txt、SHA256SUMS.txt；已存在附件先下载比对，绝不覆盖。
7. 下载草稿全部附件并核验，再公开发布并设为 Latest。
8. 以无需登录的公开下载地址重新下载全部附件，逐字节散列比对。写入 `.build/release-loop/vX.Y.Z/receipt.json` 后才报告完成。

编译和测试日志保存在 `.build/release-loop/<tag>/`，不上传仓库。失败时脚本打印失败命令、对应日志和尾部错误。产物清单和散列绑定源提交 SHA，重试不会偷偷重新构建不同的包。

## 中断后继续

```sh
python3 Scripts/release.py publish
```

该命令从当前已经准备好的版本继续，不递增版本，不覆盖远端附件。发布前失败的 Release 保持草稿；已公开但最后下载检查失败时，再运行会重新校验，不重复发布。不要删除本地 `.build/release-loop/<tag>/`，它保存冻结的产物与校验依据。

若还没有发布 tag，可修复源代码并重新准备一个新版本；若 tag 已经存在，任何源代码改动都必须使用新版本。不得强制移动 tag、删除旧 Release，或通过 `--clobber` 替换别人已经下载的同名文件。权限或登录失败时完成认证后重试；远端 main 出现新提交时先正常同步解决，不能强推。

只准备版本、不发布时可用：

```sh
python3 Scripts/release.py prepare --bump patch --notes-file .tmp/next-release.md
```

## 普通构建与分发边界

`Scripts/build.sh` 仍可单独使用，生成 `.build/releases/Codex-Usage-<version>-<build>-universal/` 下的四个文件。它不自动创建 tag 或发布 Release；发布必须走上述闭环。

当前安装包为 ad-hoc 签名，未经 Developer ID 签名及 Apple 公证。自动发布不会改变这一事实；其他 Mac 首次安装、Intel 实机及桌面宿主中的 UI 验证要单独记录，不能从构建成功推断。说明见 [INSTALL.txt](INSTALL.txt)。

This workflow uses Git and `gh`, not browser automation. `run` prepares a synchronized semantic version/build, validates an isolated committed source snapshot, creates an immutable-by-policy annotated tag, verifies draft assets, publishes, and verifies anonymous downloads. `publish` resumes the same prepared version. Success requires a completed receipt, not merely a pushed commit or a draft upload.

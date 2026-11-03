# 本机验收记录

日期：2026-11-04（Asia/Shanghai）。本记录区分真实运行证据、隔离测试及尚未覆盖的环境；不包含凭据、完整账号信息或原始接口响应。

| 验收项目 | 状态 | 证据 |
| --- | --- | --- |
| macOS / Apple Silicon | 已完成 | macOS 27.2，arm64 |
| Xcode / Swift | 已完成 | Xcode 27.2 (27B52)，Swift 6.4；使用进程级 DEVELOPER_DIR，未修改系统选择 |
| 完整 Xcode 项目 | 已完成 | `CodexUsage.xcodeproj`，共享 CodexUsage scheme，主应用依赖并嵌入 Widget Extension |
| 真实额度验证先于 UI | 已完成 | 先通过本机 Codex CLI 0.165.0 完成 initialize 与 account/rateLimits/read；当时返回每周 10080 分钟周期、已用 23%，未返回 5 小时周期 |
| 独立数据模块 | 已完成 | `Sources/App/UsageDataProvider.swift`，官方 stdio 协议，无私有 HTTP 逆向依赖 |
| 复用登录 | 已完成 | 原有 ChatGPT 登录即可读取，无 API Key 输入、无 Token 读取/复制、无配置写入 RPC |
| 构建与签名校验 | 已完成 | Debug 与 Release 构建通过；最终 Release 无编译警告；codesign --verify --deep --strict 通过；本地 ad-hoc 签名 |
| 本机安装运行 | 已完成 | `~/Applications/Codex Usage.app`，真实 UI 显示每周剩余 76%（额度会继续变化） |
| Widget 桌面添加 | 已完成 | 用户实际添加小、中、大三种尺寸；PlugInKit 注册与 chronod 加载日志确认 |
| Widget 真实显示 | 已完成 | 修复只读缓存 entitlement 的路径格式及重启旧扩展后，三种尺寸均生成含“剩余”内容的时间线；用户确认“显示正常，刷新也正常” |
| 手动刷新 | 已完成 | 主应用实测刷新时禁用按钮并显示忙碌状态，成功时间改变；用户确认小组件按钮打开应用并刷新成功 |
| 自动刷新逻辑 | 已完成 | 运行中定时器、唤醒补查、小时门限测试通过；不宣称系统保证准点渲染 |
| 退出应用后的后台查询 | 已完成 | 经用户明确授权安装 LaunchAgent；RunAtLoad 首次运行成功，主应用退出后再次触发实测成功；launchctl 显示 runs=2、last exit code=0、run interval=3600，成功缓存时间前进 |
| 失败保留旧数据 | 已完成（隔离测试） | 认证失败保留成功快照及时间；重新创建 manager 后恢复同一状态 |
| 超时、限流、服务错误、格式损坏 | 已完成（隔离测试） | 独立临时协议进程测试，不触碰真实 Codex 登录；超时清理进程；错误转换为固定分类，不显示原始响应 |
| 缓存权限与损坏 | 已完成 | 实际小组件读取成功；原子保存、0600 权限、损坏文件错误状态测试通过 |
| 过期状态 | 已完成（隔离测试） | 满一小时、已到重置时间或查询失败均标记过期，不自动重置历史额度 |
| 重启恢复与登录复用 | 已完成 | 应用多次退出/重启仍可读旧快照并成功请求真实额度；测试覆盖重建 manager 的恢复 |
| 文档与后台卸载说明 | 已完成 | `README.md`、`Scripts/build.sh`、`Scripts/install-app.sh`、`Scripts/launch-agent.sh` |
| 提交前敏感信息检查 | 已完成 | `Scripts/scan-secrets.py` 扫描非忽略源码；构建、缓存、日志、证书、密钥、profile 与用户 Xcode 状态不入库；检查暂存差异 |
| 其他 Mac / Intel 实机 / 正式分发 | 无法验证（不属于本机交付） | 有 Intel 构建 slice，未做 Intel 实机验证；未公证，不承诺跨机器临时签名加载 |
| 连续多日、睡眠/断网/注销 | 无法验证长期结果 | 已实现补查与过期标记，未做多日 soak test；睡眠/离线不保证按小时获取新数据 |

## 自动测试结果

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

8 项测试、0 失败：

- 多桶解析、缺失 secondary、未知字段兼容及剩余比例边界。
- 一小时过期、重置时间过期、失败过期。
- 原子缓存回读、文件权限和损坏缓存。
- 失败保留成功数据、重启恢复。
- 自动到期触发与重复请求抑制。
- 超时终止无响应协议进程。
- 认证、429 限流、网络/服务错误分类。
- 非 JSON 响应拒绝，不生成虚构额度。

测试中的合成值只存在于 Tests，不用于真实界面或生产后备数据。

## 已解决的实际问题

1. 系统 `xcode-select` 指向 Command Line Tools：构建脚本设置 DEVELOPER_DIR，未动系统配置。
2. 无开发者签名证书，App Group 要求 provisioning：本机版使用专用目录及扩展只读沙箱文件例外，不触碰 Codex 凭据目录。
3. 例外路径缺少开头 `/` 导致 widget 无法读取缓存：按 Apple entitlement 规则改为 `/Library/Application Support/CodexUsage/`，提升 bundle build 版本并仅重启本工具旧扩展进程。三种尺寸重新加载真实时间线成功。
4. 中号空间受限：独立紧凑布局，小号显示首周期，中号最多两个，大号最多四个；更多周期在主应用展示，不截断主应用数据模型。

本地详细构建/测试与排障日志保存在忽略的 `.build/`，不会上传仓库。

## Release 安装包验证（2026-11-04）

- `Scripts/build.sh` 现自动生成 Universal DMG、ZIP、双语安装说明和 SHA-256 校验文件；文件保存在忽略的 `.build/releases/`。
- Release 编译通过，8 项 XCTest 通过；主应用和 Widget Extension 均包含 `arm64`、`x86_64`。
- 主应用与扩展版本匹配检查、`codesign --verify --deep --strict`、`hdiutil verify` 和全部 SHA-256 校验通过。
- 只读挂载 DMG、解压 ZIP 后分别校验签名和 bundle 版本，逐文件比较两个包内应用一致；包含应用图标、扩展资源、DMG Applications 快捷方式及双语安装说明。
- 本机 Xcode 27.2 的 `lipo -verify_arch` 对单一有效输入报告错误；改用 `lipo -archs` 实际输出检查两个架构。macOS 27 的 `hdiutil` 提示命令弃用，但创建、校验和挂载均成功；保留该命令以兼容项目的 macOS 14+ 构建环境。
- 此处证明安装包完整性，不代表其他 Mac 的 Gatekeeper 首次启动或 Widget 加载已验证。产物仍为 ad-hoc 签名，未经 Developer ID 签名或 Apple 公证。

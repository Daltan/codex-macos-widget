import SwiftUI
import AppKit

@main
struct CodexUsageApp: App {
    @StateObject private var manager = UsageRefreshManager.shared
    init() {
        if CommandLine.arguments.contains("--refresh-once") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            Task { @MainActor in
                await UsageRefreshManager.shared.refresh()
                exit(UsageRefreshManager.shared.state.failure == nil ? 0 : 1)
            }
        } else {
            UsageRefreshManager.shared.start()
        }
    }
    var body: some Scene {
        WindowGroup("Codex Usage", id: "usage") {
            MainView(manager: manager)
                .onOpenURL { url in
                    if url.scheme == "codexusage", url.host == "refresh" {
                        Task { await manager.refresh() }
                    }
                }
        }.defaultSize(width: 400, height: 570).windowResizability(.contentSize)
        MenuBarExtra("Codex Usage", systemImage: "chart.bar.xaxis") {
            Text(manager.state.snapshot == nil ? "尚未获取额度" : (manager.state.isStale() ? "额度数据已过期" : "额度已更新"))
            Button("刷新额度") { Task { await manager.refresh() } }.disabled(manager.state.isRefreshing)
            Button("显示监视器") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Divider()
            Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
struct MainView: View {
    @ObservedObject var manager: UsageRefreshManager
    @State private var showSettings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("额度一览").font(.title2.bold())
                    Text(manager.state.snapshot?.accountLabel ?? "本机 Codex 账号")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).accessibilityLabel("设置")
            }
            ScrollView {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    UsageCard(state: manager.state, now: context.date)
                        .padding(20)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
                }
            }.frame(minHeight: 230, maxHeight: 440)
            HStack {
                Label(manager.state.failure == .authentication ? "需要恢复登录" : (manager.state.snapshot != nil && manager.state.failure == nil ? "最近查询认证正常" : "等待验证认证"), systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await manager.refresh() }
                } label: { Label(manager.state.isRefreshing ? "刷新中…" : "刷新", systemImage: "arrow.clockwise") }
                    .disabled(manager.state.isRefreshing)
            }
            Text("应用运行时每小时查询，唤醒后补查。小组件显示最近一次成功数据；系统决定其实际刷新时间。")
                .font(.caption2).foregroundStyle(.secondary)
            if showSettings {
                Divider()
                Text("数据来自官方 Codex app-server，只读复用现有登录。").font(.caption)
                Button("选择 Codex 可执行文件…") { chooseExecutable() }
                Text("桌面右键 → 编辑小组件 → 搜索 Codex Usage。刷新按钮会打开本应用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 400)
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, FileManager.default.isExecutableFile(atPath: url.path) {
            UserDefaults.standard.set(url.path, forKey: "codexExecutable")
            Task { await manager.refresh() }
        }
    }
}

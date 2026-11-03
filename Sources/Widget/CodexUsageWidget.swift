import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: UsageState
}
struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, state: UsageState()) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: .now, state: UsageStore().load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let state = UsageStore().load(), now = Date()
        var dates = [now]
        if let started = state.refreshingSince, started.addingTimeInterval(50) > now {
            dates.append(started.addingTimeInterval(50))
        }
        if let fetched = state.snapshot?.fetchedAt {
            let staleAt = fetched.addingTimeInterval(3600)
            if staleAt > now { dates.append(staleAt) }
        }
        for window in state.snapshot?.buckets.flatMap(\.windows) ?? [] {
            if let reset = window.resetDate, reset > now, reset < now.addingTimeInterval(3600) { dates.append(reset) }
        }
        completion(Timeline(entries: dates.sorted().map { UsageEntry(date: $0, state: state) },
                            policy: .after(now.addingTimeInterval(3600))))
    }
}
struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry
    private var windows: [(String, UsageWindow)] {
        entry.state.snapshot?.buckets.flatMap { bucket in bucket.windows.map { (bucket.title, $0) } } ?? []
    }
    private var visibleCount: Int { family == .systemSmall ? 1 : 2 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label { Text("Codex") } icon: {
                    Image("CodexMark").resizable().scaledToFit().frame(width: 18, height: 18)
                }.font(.headline)
                Spacer(minLength: 2)
                if entry.state.isRefreshing(at: entry.date) { ProgressView().controlSize(.mini) }
                Button(intent: RefreshUsageIntent()) { Image(systemName: "arrow.clockwise").font(.caption) }
                    .buttonStyle(.plain).disabled(entry.state.isRefreshing(at: entry.date)).accessibilityLabel("刷新额度")
            }
            if windows.isEmpty {
                Spacer(minLength: 0)
                Text("—").font(.title)
                Text(LocalizedStringKey(entry.state.snapshot == nil ? "打开应用读取额度" : "接口未提供周期额度")).font(.caption)
                Spacer(minLength: 0)
            } else {
                let columns = family == .systemSmall || windows.count == 1 ? 1 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), alignment: .leading, spacing: 14) {
                    ForEach(Array(windows.prefix(visibleCount).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.1.title).font(.caption2).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(item.1.remaining / 100, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text("剩余").font(.caption2).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(100, max(0, item.1.usedPercent)), total: 100)
                                .tint(item.1.remaining < 20 ? .orange : .mint)
                                .accessibilityLabel("已用 \(Int(item.1.usedPercent))%，剩余 \(Int(item.1.remaining))%")
                            if let reset = item.1.resetDate {
                                if reset > entry.date {
                                    HStack(spacing: 2) { Text("重置"); Text(reset, style: .relative) }
                                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                } else { Text("待确认重置").font(.caption2).foregroundStyle(.orange) }
                            }
                            if family == .systemMedium && (entry.state.snapshot?.buckets.count ?? 0) > 1 {
                                Text(item.0).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let failure = entry.state.failure {
                Text(LocalizedStringKey(failure == .authentication ? "登录失效 · 打开应用" : "更新失败 · 数据已过期"))
                    .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
            } else if let snapshot = entry.state.snapshot {
                HStack(spacing: 3) {
                    Text(LocalizedStringKey(entry.state.isStale(at: entry.date) ? "已过期" : "更新"))
                    Text(snapshot.fetchedAt, style: .time)
                    if windows.count > visibleCount { Text("· 更多见应用") }
                }.font(.system(size: 10)).foregroundStyle(entry.state.isStale(at: entry.date) ? Color.orange : Color.secondary).lineLimit(1)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "codexusage://refresh"))
    }
}
@main
struct CodexUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: UsageStore.widgetKind, provider: UsageTimelineProvider()) { entry in WidgetView(entry: entry) }
            .configurationDisplayName("Codex Usage")
            .description("查看本机 Codex 真实剩余额度与重置时间。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

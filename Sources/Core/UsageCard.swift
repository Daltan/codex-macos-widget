import SwiftUI

struct UsageCard: View {
    let state: UsageState
    var compact = false
    var now = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            HStack {
                Image("CodexMark").resizable().scaledToFit()
                    .frame(width: 20, height: 20).foregroundStyle(.primary).accessibilityHidden(true)
                Text("Codex").font(.headline)
                Spacer()
                if state.isRefreshing(at: now) { ProgressView().controlSize(.mini) }
                else { Circle().fill(state.isStale(at: now) ? Color.orange : Color.mint).frame(width: 6, height: 6) }
            }
            if let snapshot = state.snapshot {
                let buckets = compact ? Array(snapshot.buckets.prefix(1)) : snapshot.buckets
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                    if snapshot.buckets.count > 1 { Text(bucket.title).font(.caption).foregroundStyle(.secondary) }
                    if bucket.windows.isEmpty { Text("接口未提供周期额度").font(.caption) }
                    ForEach(Array((compact ? Array(bucket.windows.prefix(1)) : bucket.windows).enumerated()), id: \.offset) { _, window in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.remaining / 100, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(size: compact ? 30 : 34, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text("剩余").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(window.title).font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(100, max(0, window.usedPercent)), total: 100)
                                .tint(window.remaining < 20 ? .orange : .mint)
                                .accessibilityLabel("已用 \(Int(window.usedPercent))%，剩余 \(Int(window.remaining))%")
                            if !compact { Text("已用 \(window.usedPercent, specifier: "%.0f")%") .font(.caption2).foregroundStyle(.secondary) }
                            if let reset = window.resetDate {
                                if reset > now {
                                    HStack(spacing: 3) {
                                        Text("重置于")
                                        Text(reset, style: .relative)
                                    }.font(.caption2).foregroundStyle(.secondary)
                                } else { Text("已到重置时间 · 等待查询").font(.caption2).foregroundStyle(.orange) }
                            }
                        }
                    }
                }
                if compact && (snapshot.buckets.count > 1 || snapshot.buckets.first?.windows.count ?? 0 > 1) {
                    Text("更多周期见应用").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text(state.isStale(at: now) ? "数据已过期" : "更新于")
                    Text(snapshot.fetchedAt, style: .time)
                }.font(.caption2).foregroundStyle(state.isStale(at: now) ? Color.orange : Color.secondary)
            } else {
                Text("—").font(.largeTitle)
                Text(state.isRefreshing(at: now) ? "正在读取真实额度…" : "打开应用以读取额度")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let failure = state.failure {
                Text(failure.message).font(.caption2).foregroundStyle(.orange).lineLimit(compact ? 2 : 4)
            }
        }
    }
}

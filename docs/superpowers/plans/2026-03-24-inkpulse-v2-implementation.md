# InkPulse v2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tabbed dashboard (Live/Trends/Reports), native macOS notifications for critical anomalies, Swift Charts reports, and historical trend visualization to InkPulse.

**Architecture:** Layered Tabs — each tab is an isolated SwiftUI view file sharing AppState via @ObservedObject. NotificationManager and AnomalyWatcher are cross-cutting services wired into AppState's refresh cycle. HistoryStore reads existing heartbeat JSONL files for historical data.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Charts (`import Charts`), UserNotifications (`import UserNotifications`), SPM executable target, macOS 14+

**Spec:** `docs/superpowers/specs/2026-03-24-inkpulse-v2-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Rename | `Sources/UI/DashboardView.swift` → `Sources/UI/LiveTab.swift` | Existing live dashboard, struct renamed to `LiveTab` |
| Create | `Sources/UI/TabbedDashboard.swift` | TabView container passing appState to 3 tabs |
| Create | `Sources/Persistence/HistoryStore.swift` | Reads heartbeat JSONL, produces DaySummary aggregates |
| Create | `Sources/UI/TrendsTab.swift` | Today/Week/Month trend views with Swift Charts |
| Create | `Sources/UI/ReportsTab.swift` | Native Swift Charts report replacing HTML generator |
| Create | `Sources/Notifications/NotificationManager.swift` | UNUserNotificationCenter wrapper + cooldown |
| Create | `Sources/Notifications/AnomalyWatcher.swift` | Monitors MetricsEngine, triggers notifications |
| Create | `Resources/inkpulse_alert.aiff` | Custom notification sound |
| Create | `scripts/generate_alert_sound.py` | One-time script to generate the .aiff |
| Modify | `Sources/App/InkPulseApp.swift` | Window uses TabbedDashboard |
| Modify | `Sources/App/AppState.swift` | Adds HistoryStore, NotificationManager, AnomalyWatcher |
| Modify | `Sources/Metrics/HealthScore.swift` | Add Anomaly notification text extension |

---

### Task 1: Rename DashboardView → LiveTab + Create TabbedDashboard Shell

**Files:**
- Rename: `Sources/UI/DashboardView.swift` → `Sources/UI/LiveTab.swift`
- Create: `Sources/UI/TabbedDashboard.swift`
- Modify: `Sources/App/InkPulseApp.swift`

- [ ] **Step 1: Rename file and struct**

```bash
cd ~/projects/InkPulse
mv Sources/UI/DashboardView.swift Sources/UI/LiveTab.swift
```

Inside `Sources/UI/LiveTab.swift`, rename `struct DashboardView: View` → `struct LiveTab: View`. No other changes — the `@ObservedObject var appState: AppState` pattern stays.

- [ ] **Step 2: Create TabbedDashboard.swift**

```swift
// Sources/UI/TabbedDashboard.swift
import SwiftUI

struct TabbedDashboard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            LiveTab(appState: appState)
                .tabItem {
                    Label("Live", systemImage: "waveform.path.ecg")
                }

            Text("Trends — coming soon")
                .tabItem {
                    Label("Trends", systemImage: "chart.xyaxis.line")
                }

            Text("Reports — coming soon")
                .tabItem {
                    Label("Reports", systemImage: "doc.text.chart.fill")
                }
        }
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 3: Update InkPulseApp.swift**

In `Sources/App/InkPulseApp.swift`, replace `DashboardView(appState: appState)` with `TabbedDashboard(appState: appState)`. Remove `.preferredColorScheme(.dark)` from Window (it's now inside TabbedDashboard).

```swift
Window("InkPulse", id: "dashboard") {
    TabbedDashboard(appState: appState)
}
.windowStyle(.hiddenTitleBar)
.defaultSize(width: 680, height: 640)  // Wider than v1 (620x560) to accommodate tab content + charts
```

- [ ] **Step 4: Build and verify**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!` — Live tab works identically, Trends/Reports show placeholder text.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: rename DashboardView → LiveTab, add TabbedDashboard shell"
```

---

### Task 2: Create HistoryStore + DaySummary Data Layer

**Files:**
- Create: `Sources/Persistence/HistoryStore.swift`

- [ ] **Step 1: Create HistoryStore.swift**

```swift
// Sources/Persistence/HistoryStore.swift
import Foundation
import Combine

struct DaySummary {
    let date: Date
    let avgHealth: Int
    let totalCost: Double
    let peakTokenMin: Double
    let totalSessions: Int
    let activeMinutes: Double
    let anomalyCount: Int
    let avgCacheHit: Double
    let avgErrorRate: Double
    let records: [HeartbeatRecord]
}

final class HistoryStore: ObservableObject {

    @Published var todayRecords: [HeartbeatRecord] = []
    @Published var weekSummaries: [DaySummary] = []
    @Published var monthSummaries: [DaySummary] = []

    private let heartbeatDir: URL
    private var todayTimer: Timer?
    private var historyTimer: Timer?

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    init(heartbeatDir: URL = InkPulseDefaults.heartbeatDir) {
        self.heartbeatDir = heartbeatDir
    }

    // MARK: - Lifecycle

    func start() {
        refreshToday()
        refreshHistory()

        todayTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshToday()
        }
        historyTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshHistory()
        }
    }

    // MARK: - Today

    func refreshToday() {
        let dateStr = Self.fileDateFormatter.string(from: Date())
        let fileURL = heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
        todayRecords = loadRecords(from: fileURL)
    }

    // MARK: - History

    func refreshHistory() {
        let today = Date()
        let calendar = Calendar.current

        // Week: last 7 days
        var weekDays: [DaySummary] = []
        for offset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = Self.fileDateFormatter.string(from: date)
            let fileURL = heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
            let records = loadRecords(from: fileURL)
            weekDays.append(aggregate(records: records, date: date))
        }
        weekSummaries = weekDays

        // Month: last 30 days
        var monthDays: [DaySummary] = []
        for offset in (0..<30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = Self.fileDateFormatter.string(from: date)
            let fileURL = heartbeatDir.appendingPathComponent("heartbeat-\(dateStr).jsonl")
            let records = loadRecords(from: fileURL)
            monthDays.append(aggregate(records: records, date: date))
        }
        monthSummaries = monthDays
    }

    // MARK: - File Loading

    private func loadRecords(from fileURL: URL) -> [HeartbeatRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        let decoder = JSONDecoder()
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(HeartbeatRecord.self, from: lineData)
            }
    }

    // MARK: - Aggregation

    private func aggregate(records: [HeartbeatRecord], date: Date) -> DaySummary {
        guard !records.isEmpty else {
            return DaySummary(
                date: date, avgHealth: 0, totalCost: 0, peakTokenMin: 0,
                totalSessions: 0, activeMinutes: 0, anomalyCount: 0,
                avgCacheHit: 0, avgErrorRate: 0, records: []
            )
        }

        let avgHealth = records.map(\.health).reduce(0, +) / records.count
        let totalCost = records.map(\.costEur).max() ?? 0 // cumulative — take max
        let peakTokenMin = records.map(\.tokenMin).max() ?? 0
        let uniqueSessions = Set(records.map(\.sessionId)).count
        let anomalyCount = records.filter { $0.anomaly != nil }.count
        let avgCacheHit = records.map(\.cacheHit).reduce(0, +) / Double(records.count)
        let avgErrorRate = records.map(\.errorRate).reduce(0, +) / Double(records.count)

        // Active minutes: approximate from record count × heartbeat interval (5s)
        let activeMinutes = Double(records.count) * 5.0 / 60.0

        return DaySummary(
            date: date, avgHealth: avgHealth, totalCost: totalCost,
            peakTokenMin: peakTokenMin, totalSessions: uniqueSessions,
            activeMinutes: activeMinutes, anomalyCount: anomalyCount,
            avgCacheHit: avgCacheHit, avgErrorRate: avgErrorRate,
            records: records
        )
    }
}
```

- [ ] **Step 2: Wire into AppState**

In `Sources/App/AppState.swift`, add:

```swift
// Property (near other @Published properties):
@Published var historyStore = HistoryStore()

// In start(), after sessionWatcher?.start():
historyStore.start()
```

- [ ] **Step 3: Build and verify**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add HistoryStore data layer for heartbeat JSONL history"
```

---

### Task 3: Implement TrendsTab (Today/Week/Month)

**Files:**
- Create: `Sources/UI/TrendsTab.swift`
- Modify: `Sources/UI/TabbedDashboard.swift`

- [ ] **Step 1: Create TrendsTab.swift**

This is the largest file. It contains a segmented Picker (Today/Week/Month) and three sub-views. Uses `import Charts` for Swift Charts.

```swift
// Sources/UI/TrendsTab.swift
import SwiftUI
import Charts

enum TrendsPeriod: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
}

struct TrendsTab: View {
    @ObservedObject var appState: AppState
    @State private var period: TrendsPeriod = .today

    var body: some View {
        ZStack {
            Color(hex: "#0a0f1a").ignoresSafeArea()

            VStack(spacing: 0) {
                // Period picker
                Picker("Period", selection: $period) {
                    ForEach(TrendsPeriod.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 16)

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                ScrollView {
                    switch period {
                    case .today:
                        TodayTrendView(records: appState.historyStore.todayRecords)
                    case .week:
                        WeekTrendView(summaries: appState.historyStore.weekSummaries)
                    case .month:
                        MonthTrendView(summaries: appState.historyStore.monthSummaries)
                    }
                }
            }
        }
    }
}

// MARK: - Today

struct TodayTrendView: View {
    let records: [HeartbeatRecord]

    private var avgHealth: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.health).reduce(0, +) / records.count
    }
    private var totalCost: Double { records.map(\.costEur).max() ?? 0 }
    private var peakTokenMin: Double { records.map(\.tokenMin).max() ?? 0 }
    private var sessions: Int { Set(records.map(\.sessionId)).count }
    private var activeHours: Double { Double(records.count) * 5.0 / 3600.0 }
    private var anomalies: [HeartbeatRecord] { records.filter { $0.anomaly != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Stats strip
            HStack(spacing: 0) {
                trendStat("health", "\(avgHealth)", color: healthColor(for: avgHealth))
                trendDivider()
                trendStat("cost", String(format: "€%.2f", totalCost), color: .white)
                trendDivider()
                trendStat("peak", String(format: "%.0f", peakTokenMin), color: Color(hex: "#00d4aa"))
                trendDivider()
                trendStat("sessions", "\(sessions)", color: Color(hex: "#4A9EFF"))
                trendDivider()
                trendStat("hours", String(format: "%.1f", activeHours), color: .white.opacity(0.7))
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))

            // ECG Extended
            if !records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("ECG — Full Day")
                    Chart(Array(records.enumerated()), id: \.offset) { item in
                        LineMark(
                            x: .value("Time", item.offset),
                            y: .value("tok/min", item.element.tokenMin)
                        )
                        .foregroundStyle(Color(hex: "#00d4aa"))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel().foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .frame(height: 120)
                }
            }

            // Anomaly timeline
            if !anomalies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("ANOMALIES — \(anomalies.count) detected")
                    ForEach(Array(anomalies.prefix(10).enumerated()), id: \.offset) { _, record in
                        HStack {
                            Text(record.ts.suffix(8).description)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(record.anomaly ?? "")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(hex: "#FF4444"))
                            Spacer()
                            Text("health \(record.health)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(healthColor(for: record.health))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
    }
}

// MARK: - Week

struct WeekTrendView: View {
    let summaries: [DaySummary]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private var weekAvgHealth: Int {
        let active = summaries.filter { !$0.records.isEmpty }
        guard !active.isEmpty else { return 0 }
        return active.map(\.avgHealth).reduce(0, +) / active.count
    }

    private var weekTotalCost: Double {
        summaries.map(\.totalCost).reduce(0, +)
    }

    private var worstSessions: [(sessionId: String, avgHealth: Int, anomalyCount: Int)] {
        let allRecords = summaries.flatMap(\.records)
        let grouped = Dictionary(grouping: allRecords, by: \.sessionId)
        return grouped.map { (sid, records) in
            let avg = records.map(\.health).reduce(0, +) / records.count
            let anomalies = records.filter { $0.anomaly != nil }.count
            return (sessionId: sid, avgHealth: avg, anomalyCount: anomalies)
        }
        .sorted { $0.avgHealth < $1.avgHealth }
        .prefix(3)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cost bar chart colored by health
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("DAILY COST & HEALTH")
                Chart(Array(summaries.enumerated()), id: \.offset) { item in
                    BarMark(
                        x: .value("Day", Self.dayFormatter.string(from: item.element.date)),
                        y: .value("Cost", item.element.totalCost)
                    )
                    .foregroundStyle(item.element.records.isEmpty ? Color.gray.opacity(0.2) : healthColor(for: item.element.avgHealth))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(height: 160)
            }

            // Health trend line
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("HEALTH TREND")
                Chart(Array(summaries.filter { !$0.records.isEmpty }.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value("Day", Self.dayFormatter.string(from: item.element.date)),
                        y: .value("Health", item.element.avgHealth)
                    )
                    .foregroundStyle(Color(hex: "#00d4aa"))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", Self.dayFormatter.string(from: item.element.date)),
                        y: .value("Health", item.element.avgHealth)
                    )
                    .foregroundStyle(healthColor(for: item.element.avgHealth))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 120)
            }

            // Comparison stats
            HStack(spacing: 0) {
                trendStat("avg health", "\(weekAvgHealth)", color: healthColor(for: weekAvgHealth))
                trendDivider()
                trendStat("total cost", String(format: "€%.2f", weekTotalCost), color: .white)
                trendDivider()
                trendStat("active days", "\(summaries.filter { !$0.records.isEmpty }.count)/7", color: Color(hex: "#4A9EFF"))
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))

            // Worst sessions
            if !worstSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("WORST SESSIONS")
                    ForEach(Array(worstSessions.enumerated()), id: \.offset) { _, session in
                        HStack {
                            Text(String(session.sessionId.prefix(8)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            if session.anomalyCount > 0 {
                                Text("\(session.anomalyCount) anomalies")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color(hex: "#FF4444").opacity(0.7))
                            }
                            Text("\(session.avgHealth)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(healthColor(for: session.avgHealth))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
    }
}

// MARK: - Month

struct MonthTrendView: View {
    let summaries: [DaySummary]

    private var totalCost: Double { summaries.map(\.totalCost).reduce(0, +) }
    private var totalSessions: Int { summaries.map(\.totalSessions).reduce(0, +) }
    private var totalAnomalies: Int { summaries.map(\.anomalyCount).reduce(0, +) }
    private var activeDays: Int { summaries.filter { !$0.records.isEmpty }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Heatmap
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("ACTIVITY HEATMAP — 30 DAYS")
                HeatmapGrid(summaries: summaries)
                    .frame(height: 100)
            }

            // Cumulative cost (precomputed — var inside Chart{} result builder is illegal)
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("CUMULATIVE COST")
                let cumulativeCost: [(idx: Int, running: Double)] = {
                    var running = 0.0
                    return summaries.enumerated().map { idx, day in
                        running += day.totalCost
                        return (idx: idx, running: running)
                    }
                }()
                Chart(cumulativeCost, id: \.idx) { item in
                    AreaMark(
                        x: .value("Day", item.idx),
                        y: .value("Cost", item.running)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color(hex: "#00d4aa").opacity(0.3), Color(hex: "#00d4aa").opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Day", item.idx),
                        y: .value("Cost", item.running)
                    )
                    .foregroundStyle(Color(hex: "#00d4aa"))
                }
                .chartXAxis(.hidden)
                .frame(height: 120)
            }

            // Usage pattern by weekday
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("USAGE PATTERN BY WEEKDAY")
                WeekdayUsageChart(summaries: summaries)
                    .frame(height: 100)
            }

            // Monthly summary
            HStack(spacing: 0) {
                trendStat("cost", String(format: "€%.2f", totalCost), color: .white)
                trendDivider()
                trendStat("sessions", "\(totalSessions)", color: Color(hex: "#4A9EFF"))
                trendDivider()
                trendStat("anomalies", "\(totalAnomalies)", color: totalAnomalies > 0 ? Color(hex: "#FF4444") : Color(hex: "#00d4aa"))
                trendDivider()
                trendStat("active", "\(activeDays)/30d", color: .white.opacity(0.7))
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
    }
}

// MARK: - Heatmap Grid

struct HeatmapGrid: View {
    let summaries: [DaySummary]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    /// Build a calendar-aligned grid: Mon=0, Sun=6. Pad start with empty cells
    /// so the first day lands on its correct weekday column.
    private var calendarCells: [(date: Date?, summary: DaySummary?)] {
        guard let firstDay = summaries.first?.date else { return [] }
        let calendar = Calendar.current
        // weekday: 1=Sun. Convert to Mon=0 index.
        let wd = calendar.component(.weekday, from: firstDay)
        let startPad = wd == 1 ? 6 : wd - 2 // Mon=0, Tue=1, ..., Sun=6

        var cells: [(date: Date?, summary: DaySummary?)] = []
        // Leading empty cells
        for _ in 0..<startPad {
            cells.append((date: nil, summary: nil))
        }
        // Data cells — missing days (empty records) render as dark grey
        for day in summaries {
            cells.append((date: day.date, summary: day))
        }
        return cells
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Weekday labels
            HStack(spacing: 3) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, cell in
                    if let summary = cell.summary {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(summary.records.isEmpty ? Color.white.opacity(0.04) : healthColor(for: summary.avgHealth).opacity(0.7))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                summary.records.isEmpty ? nil :
                                Text("\(summary.avgHealth)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                            )
                    } else {
                        // Empty padding cell
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.clear)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }
}

// MARK: - Weekday Usage Chart

struct WeekdayUsageChart: View {
    let summaries: [DaySummary]

    private static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var weekdayMinutes: [(day: String, minutes: Double)] {
        let calendar = Calendar.current
        var totals: [Int: Double] = [:]    // weekday number → total minutes
        var counts: [Int: Int] = [:]

        for summary in summaries where !summary.records.isEmpty {
            let wd = calendar.component(.weekday, from: summary.date) // 1=Sun
            let idx = wd == 1 ? 6 : wd - 2 // Convert to 0=Mon
            totals[idx, default: 0] += summary.activeMinutes
            counts[idx, default: 0] += 1
        }

        return (0..<7).map { idx in
            let avg = counts[idx, default: 0] > 0 ? totals[idx, default: 0] / Double(counts[idx]!) : 0
            return (day: Self.weekdays[idx], minutes: avg / 60.0) // hours
        }
    }

    var body: some View {
        Chart(weekdayMinutes, id: \.day) { item in
            BarMark(
                x: .value("Day", item.day),
                y: .value("Hours", item.minutes)
            )
            .foregroundStyle(Color(hex: "#4A9EFF").opacity(0.7))
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel().foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Shared Components

func trendStat(_ label: String, _ value: String, color: Color) -> some View {
    VStack(spacing: 4) {
        Text(value)
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
    }
    .frame(maxWidth: .infinity)
}

func trendDivider() -> some View {
    Rectangle()
        .fill(Color.white.opacity(0.06))
        .frame(width: 1, height: 36)
}

func sectionLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.4))
}
```

- [ ] **Step 2: Update TabbedDashboard.swift — replace placeholder**

Replace `Text("Trends — coming soon")` with `TrendsTab(appState: appState)`.

- [ ] **Step 3: Build and verify**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add TrendsTab with Today/Week/Month views and Swift Charts"
```

---

### Task 4: Implement ReportsTab (Native Swift Charts)

**Files:**
- Create: `Sources/UI/ReportsTab.swift`
- Modify: `Sources/UI/TabbedDashboard.swift`

- [ ] **Step 1: Create ReportsTab.swift**

```swift
// Sources/UI/ReportsTab.swift
import SwiftUI
import Charts

enum ReportPeriod: String, CaseIterable {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
}

struct ReportsTab: View {
    @ObservedObject var appState: AppState
    @State private var period: ReportPeriod = .today

    private var records: [HeartbeatRecord] {
        switch period {
        case .today: return appState.historyStore.todayRecords
        case .week: return appState.historyStore.weekSummaries.flatMap(\.records)
        case .month: return appState.historyStore.monthSummaries.flatMap(\.records)
        }
    }

    private var avgHealth: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.health).reduce(0, +) / records.count
    }
    // Cost: for multi-session aggregation, sum the per-session max
    // (costEur is cumulative per session — max per session is the session total)
    private var totalCost: Double {
        let grouped = Dictionary(grouping: records, by: \.sessionId)
        return grouped.values.map { sessionRecords in
            sessionRecords.map(\.costEur).max() ?? 0
        }.reduce(0, +)
    }
    private var model: String { records.last?.model ?? "—" }
    private var avgCacheHit: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.cacheHit).reduce(0, +) / Double(records.count)
    }
    private var avgErrorRate: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.errorRate).reduce(0, +) / Double(records.count)
    }
    private var anomalyRecords: [HeartbeatRecord] { records.filter { $0.anomaly != nil } }

    var body: some View {
        ZStack {
            Color(hex: "#0a0f1a").ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Period", selection: $period) {
                    ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 16)

                Divider().overlay(Color(hex: "#00d4aa").opacity(0.2))

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header card
                        reportHeader

                        // ECG Timeline
                        if !records.isEmpty {
                            chartSection("ECG TIMELINE — tok/min") {
                                Chart(Array(records.enumerated()), id: \.offset) { item in
                                    LineMark(x: .value("T", item.offset), y: .value("V", item.element.tokenMin))
                                        .foregroundStyle(Color(hex: "#00d4aa"))
                                        .interpolationMethod(.catmullRom)
                                    AreaMark(x: .value("T", item.offset), y: .value("V", item.element.tokenMin))
                                        .foregroundStyle(.linearGradient(colors: [Color(hex: "#00d4aa").opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                                }
                                .chartXAxis(.hidden)
                                .frame(height: 140)
                            }
                        }

                        // Cost Burn
                        if !records.isEmpty {
                            chartSection("COST BURN (EUR)") {
                                Chart(Array(records.enumerated()), id: \.offset) { item in
                                    AreaMark(x: .value("T", item.offset), y: .value("Cost", item.element.costEur))
                                        .foregroundStyle(.linearGradient(colors: [Color(hex: "#FFA500").opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                                    LineMark(x: .value("T", item.offset), y: .value("Cost", item.element.costEur))
                                        .foregroundStyle(Color(hex: "#FFA500"))
                                }
                                .chartXAxis(.hidden)
                                .frame(height: 120)
                            }
                        }

                        // Tool Usage + Cache side by side
                        if !records.isEmpty {
                            HStack(spacing: 16) {
                                chartSection("TOOL USAGE") {
                                    Chart(Array(records.enumerated()), id: \.offset) { item in
                                        BarMark(x: .value("T", item.offset), y: .value("V", item.element.toolFreq))
                                            .foregroundStyle(Color(hex: "#4A9EFF").opacity(0.7))
                                    }
                                    .chartXAxis(.hidden)
                                    .frame(height: 100)
                                }

                                chartSection("CACHE EFFICIENCY") {
                                    Chart {
                                        SectorMark(angle: .value("Hit", avgCacheHit * 100), innerRadius: .ratio(0.65))
                                            .foregroundStyle(Color(hex: "#00d4aa"))
                                        SectorMark(angle: .value("Miss", max(0, (1 - avgCacheHit) * 100)), innerRadius: .ratio(0.65))
                                            .foregroundStyle(Color(hex: "#FF4444").opacity(0.5))
                                    }
                                    .frame(height: 100)
                                }
                            }
                        }

                        // Anomaly log
                        if !anomalyRecords.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionLabel("ANOMALY LOG — \(anomalyRecords.count) events")
                                ForEach(Array(anomalyRecords.prefix(20).enumerated()), id: \.offset) { _, r in
                                    HStack {
                                        Text(r.ts.suffix(8).description)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.3))
                                        Text(String(r.sessionId.prefix(8)))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.5))
                                        Text(r.anomaly ?? "")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(Color(hex: "#FF4444"))
                                        Spacer()
                                        Text("\(r.health)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(healthColor(for: r.health))
                                    }
                                }
                            }
                        }

                        // Insights
                        insightsSection

                        // Export HTML (secondary, opt-in)
                        HStack {
                            Spacer()
                            Button(action: { appState.generateReport() }) {
                                Label("Export HTML", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 11, design: .rounded))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.3))
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 20)
                }
            }
        }
    }

    // MARK: - Components

    private var reportHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(avgHealth)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor(for: avgHealth))
                Text("AVG HEALTH")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Cost:").foregroundStyle(.white.opacity(0.4))
                    Text(String(format: "€%.4f", totalCost)).foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Text("Model:").foregroundStyle(.white.opacity(0.4))
                    Text(model).foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Text("Samples:").foregroundStyle(.white.opacity(0.4))
                    Text("\(records.count)").foregroundStyle(.white)
                }
            }
            .font(.system(size: 11, design: .monospaced))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#00d4aa").opacity(0.1), lineWidth: 1)))
    }

    private func chartSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            content()
        }
    }

    private var insightsSection: some View {
        let insights = generateInsights()
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("INSIGHTS")
            Text(insights)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color(hex: "#00d4aa").opacity(0.8))
                .lineSpacing(4)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }

    private func generateInsights() -> String {
        var lines: [String] = []
        if avgHealth >= 80 {
            lines.append("Health is excellent (\(avgHealth)/100) — operating within optimal parameters.")
        } else if avgHealth >= 50 {
            lines.append("Health is moderate (\(avgHealth)/100) — some metrics could improve.")
        } else {
            lines.append("Health is critical (\(avgHealth)/100) — review anomalies.")
        }
        let cachePct = Int(avgCacheHit * 100)
        if avgCacheHit >= 0.6 {
            lines.append("Cache hit \(cachePct)% is strong.")
        } else {
            lines.append("Cache hit \(cachePct)% — consider optimizing prompt structure.")
        }
        if totalCost < 0.10 { lines.append("Cost is minimal.") }
        else if totalCost < 1.0 { lines.append("Cost within normal range.") }
        else { lines.append("Cost elevated — monitor for spikes.") }
        return lines.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Update TabbedDashboard.swift — replace placeholder**

Replace `Text("Reports — coming soon")` with `ReportsTab(appState: appState)`.

- [ ] **Step 3: Build and verify**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add ReportsTab with native Swift Charts replacing HTML reports"
```

---

### Task 5: Add Anomaly Notification Text Extension

**Files:**
- Modify: `Sources/Metrics/HealthScore.swift`

- [ ] **Step 1: Add Anomaly extension**

Append to the end of `Sources/Metrics/HealthScore.swift`:

```swift
// MARK: - Notification Text

extension Anomaly {
    var notificationTitle: String {
        switch self {
        case .hemorrhage:   return "Token Hemorrhage"
        case .explosion:    return "Agent Explosion"
        case .loop:         return "Error Loop"
        case .stall:        return "Session Stall"
        case .deepThinking: return "Deep Thinking"
        }
    }

    func notificationBody(project: String, snapshot: MetricsSnapshot) -> String {
        switch self {
        case .hemorrhage:
            let sessionHours = max(Date().timeIntervalSince(snapshot.startTime) / 3600, 1.0/60.0)
            let rate = snapshot.costEUR / sessionHours
            let cachePct = Int(snapshot.cacheHit * 100)
            return "\(project) burning €\(String(format: "%.1f", rate))/h — cache \(cachePct)%"
        case .explosion:
            return "\(project) spawned \(snapshot.subagentCount) agents"
        case .loop:
            return "\(project) looping — \(String(format: "%.0f", snapshot.toolFreq)) tool calls/min, \(Int(snapshot.errorRate * 100))% errors"
        case .stall:
            return "\(project) stalled — \(String(format: "%.0f", snapshot.idleAvgS))s avg idle"
        case .deepThinking:
            return "\(project) thinking deeply — ratio \(String(format: "%.1f", snapshot.thinkOutputRatio ?? 0))"
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add Anomaly notification text extension"
```

---

### Task 6: Create NotificationManager

**Files:**
- Create: `Sources/Notifications/NotificationManager.swift`

- [ ] **Step 1: Create directory and file**

```bash
mkdir -p ~/projects/InkPulse/Sources/Notifications
```

```swift
// Sources/Notifications/NotificationManager.swift
import Foundation
import UserNotifications

final class NotificationManager {

    private let center = UNUserNotificationCenter.current()
    private var isAuthorized = false

    // MARK: - Authorization

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            // Dispatch to main thread — completion fires on arbitrary queue,
            // isAuthorized is read from main thread in send()
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error = error {
                    AppState.log("Notification auth error: \(error.localizedDescription)")
                }
                AppState.log("Notification authorization: \(granted)")
            }
        }
    }

    // MARK: - Send

    func send(title: String, body: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName("inkpulse_alert.aiff"))

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        center.add(request) { error in
            if let error = error {
                AppState.log("Notification send error: \(error.localizedDescription)")
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add NotificationManager with UNUserNotificationCenter"
```

---

### Task 7: Create AnomalyWatcher + Wire Into AppState

**Files:**
- Create: `Sources/Notifications/AnomalyWatcher.swift`
- Modify: `Sources/App/AppState.swift`

- [ ] **Step 1: Create AnomalyWatcher.swift**

```swift
// Sources/Notifications/AnomalyWatcher.swift
import Foundation

final class AnomalyWatcher {

    private let notificationManager: NotificationManager

    static let criticalAnomalies: Set<Anomaly> = [.hemorrhage, .explosion, .loop]

    private var previousState: [String: Anomaly] = [:]  // sessionId → last anomaly
    private var cooldowns: [String: Date] = [:]          // "sessionId:anomaly" → expiry
    private var lastGlobalNotification: Date = .distantPast

    private let perSessionCooldown: TimeInterval = 300    // 5 minutes
    private let globalCooldown: TimeInterval = 30         // 30 seconds

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    // MARK: - Check

    func check(sessions: [String: MetricsSnapshot], sessionCwds: [String: String]) {
        let now = Date()

        for (sessionId, snapshot) in sessions {
            let currentAnomaly: Anomaly? = snapshot.anomaly.flatMap { Anomaly(rawValue: $0) }
            let previousAnomaly: Anomaly? = previousState[sessionId]

            if let anomaly = currentAnomaly,
               Self.criticalAnomalies.contains(anomaly),
               previousAnomaly == nil {

                let cooldownKey = "\(sessionId):\(anomaly.rawValue)"

                // Check per-session cooldown
                if let expiry = cooldowns[cooldownKey], now < expiry {
                    previousState[sessionId] = currentAnomaly
                    continue
                }

                // Check global cooldown
                if now.timeIntervalSince(lastGlobalNotification) < globalCooldown {
                    previousState[sessionId] = currentAnomaly
                    continue
                }

                // Send notification
                let project = projectName(
                    from: sessionId,
                    filePath: nil,
                    cwd: sessionCwds[sessionId]
                )

                notificationManager.send(
                    title: anomaly.notificationTitle,
                    body: anomaly.notificationBody(project: project, snapshot: snapshot)
                )

                cooldowns[cooldownKey] = now.addingTimeInterval(perSessionCooldown)
                lastGlobalNotification = now
            }

            previousState[sessionId] = currentAnomaly
        }

        // Clean up stale entries
        let activeIds = Set(sessions.keys)
        for id in previousState.keys where !activeIds.contains(id) {
            previousState.removeValue(forKey: id)
        }
    }
}
```

- [ ] **Step 2: Wire into AppState**

In `Sources/App/AppState.swift`, add properties:

```swift
// Near other properties:
private(set) var notificationManager = NotificationManager()
private(set) var anomalyWatcher: AnomalyWatcher?
```

In `start()`, after `heartbeatLogger?.purgeOldFiles()`:

```swift
notificationManager.requestAuthorization()
anomalyWatcher = AnomalyWatcher(notificationManager: notificationManager)
```

In `refresh()`, after the token history update block:

```swift
// Anomaly check
anomalyWatcher?.check(sessions: metricsEngine.sessions, sessionCwds: sessionCwds)
```

- [ ] **Step 3: Build and verify**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add AnomalyWatcher with cooldown logic, wire into AppState"
```

---

### Task 8: Generate Custom Alert Sound

**Files:**
- Create: `scripts/generate_alert_sound.py`
- Create: `Resources/inkpulse_alert.aiff`

- [ ] **Step 1: Create sound generation script**

```python
#!/usr/bin/env python3
"""Generate InkPulse custom notification sound — heartbeat pulse."""
import struct
import math
import subprocess
import tempfile
import os

SAMPLE_RATE = 44100
DURATION = 1.0
FREQ = 80  # Low thump frequency

samples = []
n_samples = int(SAMPLE_RATE * DURATION)

for i in range(n_samples):
    t = i / SAMPLE_RATE
    # Two heartbeat pulses: thump at 0.1s and 0.35s
    pulse1 = math.exp(-((t - 0.10) ** 2) / 0.002)
    pulse2 = math.exp(-((t - 0.35) ** 2) / 0.002)
    envelope = (pulse1 + pulse2 * 0.7)
    # Low sine for thump body
    wave = math.sin(2 * math.pi * FREQ * t)
    # Higher harmonic for attack
    wave += 0.3 * math.sin(2 * math.pi * FREQ * 3 * t)
    sample = envelope * wave * 0.8
    sample = max(-1.0, min(1.0, sample))
    samples.append(int(sample * 32767))

# Write raw WAV first
wav_path = tempfile.mktemp(suffix=".wav")
with open(wav_path, "wb") as f:
    n = len(samples)
    data_size = n * 2
    f.write(b"RIFF")
    f.write(struct.pack("<I", 36 + data_size))
    f.write(b"WAVE")
    f.write(b"fmt ")
    f.write(struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16))
    f.write(b"data")
    f.write(struct.pack("<I", data_size))
    for s in samples:
        f.write(struct.pack("<h", s))

# Convert to AIFF via afconvert
script_dir = os.path.dirname(os.path.abspath(__file__))
aiff_path = os.path.join(script_dir, "..", "Resources", "inkpulse_alert.aiff")
subprocess.run(["afconvert", "-f", "AIFF", "-d", "BEI16", wav_path, aiff_path], check=True)
os.unlink(wav_path)
print(f"Generated: {aiff_path}")
```

- [ ] **Step 2: Run the script**

```bash
mkdir -p ~/projects/InkPulse/scripts
# (write the script first, then run)
cd ~/projects/InkPulse && python3 scripts/generate_alert_sound.py
```

Expected: `Generated: .../Resources/inkpulse_alert.aiff`

- [ ] **Step 3: Verify the sound**

```bash
afplay ~/projects/InkPulse/Resources/inkpulse_alert.aiff
```

Expected: Two quick low thumps (heartbeat).

- [ ] **Step 4: Commit**

```bash
git add scripts/generate_alert_sound.py Resources/inkpulse_alert.aiff && git commit -m "feat: add custom InkPulse alert sound (heartbeat pulse)"
```

---

### Task 9: Update Info.plist + Deploy to /Applications

**Files:**
- Modify: `/Applications/InkPulse.app/Contents/Info.plist`

- [ ] **Step 1: Build release**

```bash
cd ~/projects/InkPulse && swift build -c release 2>&1 | tail -5
```

- [ ] **Step 2: Kill running InkPulse**

```bash
pkill -x InkPulse 2>/dev/null; sleep 1
```

- [ ] **Step 3: Deploy binary + resources + plist**

```bash
# Binary
cp ~/projects/InkPulse/.build/release/InkPulse /Applications/InkPulse.app/Contents/MacOS/InkPulse

# Sound file
cp ~/projects/InkPulse/Resources/inkpulse_alert.aiff /Applications/InkPulse.app/Contents/Resources/inkpulse_alert.aiff
```

- [ ] **Step 4: Update Info.plist with notification description**

```bash
plutil -insert NSUserNotificationsUsageDescription \
  -string "InkPulse sends notifications when Claude Code sessions encounter critical anomalies." \
  /Applications/InkPulse.app/Contents/Info.plist
```

- [ ] **Step 5: Launch and verify**

```bash
open /Applications/InkPulse.app
```

Verify:
- Dashboard opens with 3 tabs (Live, Trends, Reports)
- Live tab works as before
- Trends tab shows today's data (if heartbeats exist)
- Reports tab shows native charts
- Notification permission dialog appears on first launch

- [ ] **Step 6: Commit all source changes**

```bash
cd ~/projects/InkPulse && git add -A && git commit -m "feat: InkPulse v2.0 — tabs, trends, reports, notifications, custom sound"
```

---

## Verification Checklist

After all tasks complete:

- [ ] Tabbed dashboard opens with Live/Trends/Reports tabs
- [ ] Live tab works identically to v1 DashboardView
- [ ] Trends Today shows ECG + stats from heartbeat JSONL
- [ ] Trends Week shows bar chart + health trend + worst sessions
- [ ] Trends Month shows heatmap + cumulative cost + usage pattern
- [ ] Reports tab renders Swift Charts (ECG, cost, tools, cache doughnut)
- [ ] Reports "Export HTML" button works (opt-in, secondary)
- [ ] macOS notification permission requested on first launch
- [ ] Custom alert sound plays (heartbeat pulse)
- [ ] AnomalyWatcher fires notification on hemorrhage/explosion/loop
- [ ] Cooldown prevents spam (5min per-session, 30s global)
- [ ] Zero external dependencies added
- [ ] App runs from /Applications with login item intact

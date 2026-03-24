# InkPulse v2.0 — Enhancement Design Spec

> Author: Claude x Calastri | Date: 2026-03-24 | Session: 452
> Approach: Layered Tabs | Principle: Autonomous tentacle, zero external dependencies

## 1. Problem Statement

InkPulse v1.0 monitors Claude Code sessions in real-time via menu bar. It works. But:
- **No notifications**: anomalies happen silently. If you're not looking at the menu bar, you miss them.
- **No historical trends**: heartbeat JSONL logs exist but aren't surfaced. No way to see patterns across days/weeks/months.
- **Reports require browser**: HTML report with Chart.js CDN dependency. Not integrated, not antifragile.

## 2. Decisions (Validated with User)

| Area | Decision | Rationale |
|------|----------|-----------|
| Notifications | macOS native only (UNUserNotificationCenter) | Zero external dependencies. If Mac is on, it works. |
| Alert level | Critical only: hemorrhage, explosion, loop | Signal over noise. Stall/deepThinking are informational, not actionable. |
| Sound | Custom .aiff (heartbeat pulse) | Brand identity in audio. Distinguishable from system sounds. |
| Trends depth | Today + Week + Month | Heartbeat data already exists. Maximum insight extraction. |
| Reports | Native SwiftUI with Swift Charts, in-app tab | Replaces HTML/Chart.js. Antifragile — no CDN, no browser. |
| Architecture | Layered Tabs | Each tab is an isolated file. Zero risk to existing Live functionality. |
| Telegram/n8n | NOT a dependency. Optional webhook layer, never required. | Anti-antifragile to route through intermediaries. |

## 3. Architecture

```
InkPulseApp
├── MenuBarExtra (unchanged — popover quick glance)
├── Window "Dashboard"
│   └── TabbedDashboard
│       ├── Tab: Live (existing DashboardView → renamed LiveTab)
│       ├── Tab: Trends (TrendsTab — new)
│       └── Tab: Reports (ReportsTab — new)
├── NotificationManager (new — cross-cutting)
│   ├── UNUserNotificationCenter
│   ├── Custom sound (.aiff in bundle)
│   └── AnomalyWatcher (observes MetricsEngine, triggers alerts)
└── HistoryStore (new — reads heartbeat JSONL)
    ├── loadToday() → [HeartbeatRecord]
    ├── loadWeek() → [DaySummary]
    └── loadMonth() → [DaySummary]
```

## 4. New Files

| File | Path | Responsibility |
|------|------|---------------|
| TabbedDashboard.swift | Sources/UI/ | TabView container with Live/Trends/Reports tabs |
| LiveTab.swift | Sources/UI/ | Rename of DashboardView.swift — existing live dashboard |
| TrendsTab.swift | Sources/UI/ | Historical trends: today/week/month with segmented picker |
| ReportsTab.swift | Sources/UI/ | Native SwiftUI report replacing HTML generator |
| NotificationManager.swift | Sources/Notifications/ | UNUserNotificationCenter wrapper + cooldown logic |
| AnomalyWatcher.swift | Sources/Notifications/ | Monitors MetricsEngine, triggers notifications on state transitions |
| HistoryStore.swift | Sources/Persistence/ | Reads heartbeat JSONL files, produces aggregated DaySummary |
| inkpulse_alert.aiff | Resources/ | Custom notification sound (~1s heartbeat pulse) |

## 5. Modified Files

| File | Change |
|------|--------|
| InkPulseApp.swift | Window body uses TabbedDashboard instead of DashboardView |
| AppState.swift | Adds NotificationManager, AnomalyWatcher, HistoryStore properties. Wires AnomalyWatcher into refresh cycle. |
| Package.swift | No changes needed — Swift Charts is a system framework, no new dependencies |
| Info.plist | Add NSUserNotificationsUsageDescription |

## 6. Trends Tab Detail

### 6.1 Data Model

```swift
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
    let records: [HeartbeatRecord] // raw data for drill-down
}
```

### 6.2 Today View
- ECG Extended: full-width LineMark of all today's datapoints (not just last 300s)
- Stats summary: avg health, total cost, peak tok/min, active hours, session count
- Anomaly timeline: vertical list with timestamp + type + session (only if anomalies exist)

### 6.3 Week View
- Bar chart: 7 bars for daily cost, colored by avg health (teal ≥70, orange ≥40, red <40)
- Trend line: avg health overlaid as LineMark
- Comparison stats: "Today vs week average" for cost, tok/min, cache hit, active hours
- Worst sessions: top 3 lowest-health sessions of the week

### 6.4 Month View
- Heatmap: 7×5 grid (Mon-Sun × weeks) colored by avg health. GitHub-contributions style, teal palette.
- Cumulative cost: AreaMark rising day by day with dashed projection to month end
- Usage pattern: bar chart of active hours per weekday (when you work most)
- Monthly summary: total cost, total sessions, total anomalies, health trend direction

### 6.5 HistoryStore Implementation

HistoryStore reads `~/.inkpulse/heartbeats/heartbeat-YYYY-MM-DD.jsonl` files.

- `loadToday()`: reads today's file, returns raw `[HeartbeatRecord]`
- `loadWeek()`: reads last 7 files, aggregates into `[DaySummary]`
- `loadMonth()`: reads last 30 files, aggregates into `[DaySummary]`
- Parsing is lazy: stream lines, decode one at a time, never load full file into memory
- Refresh interval: 60 seconds (historical data doesn't change fast)
- Cache: in-memory cache of loaded DaySummary, invalidated on refresh

## 7. Notification System Detail

### 7.1 AnomalyWatcher

Runs inside AppState's existing 1s refresh cycle. After `metricsEngine.refreshSnapshots()`:

```
for each session in metricsEngine.sessions:
    currentAnomaly = session.anomaly
    previousAnomaly = previousAnomalyState[session.sessionId]

    if currentAnomaly is critical AND previousAnomaly was nil:
        if not in cooldown for this session+anomaly:
            notificationManager.send(anomaly, session)
            set cooldown

    previousAnomalyState[session.sessionId] = currentAnomaly
```

### 7.2 Anti-Spam Logic

| Rule | Value | Purpose |
|------|-------|---------|
| Per-session cooldown | 5 minutes | Same anomaly on same session doesn't re-fire |
| Global cooldown | 30 seconds | Max 1 notification per 30s across all sessions |
| Transition-only | nil → critical | Only fires on state change, not on persistence |

### 7.3 Critical Anomaly Triggers

| Anomaly | Condition | Notification Title | Body |
|---------|-----------|-------------------|------|
| hemorrhage | costRate > 5 EUR/h AND cacheHit < 0.20 | "Token Hemorrhage" | "{project} burning €{rate}/h — cache {pct}%" |
| explosion | subagentCount > 8 | "Agent Explosion" | "{project} spawned {n} agents" |
| loop | toolFreq > 15 AND errorRate > 0.30 | "Error Loop" | "{project} looping — {n} errors/min" |

### 7.4 NotificationManager

- `requestAuthorization()`: called once at app launch. Requests `.alert, .sound, .badge`.
- `send(title:body:)`: creates UNMutableNotificationContent with custom sound, schedules immediately.
- Custom sound: `UNNotificationSound(named: UNNotificationSoundName("inkpulse_alert.aiff"))`
- Sound file must be in the app bundle's Resources, format: Linear PCM, MA4, uLaw, aLaw, .aiff/.wav/.caf, ≤30 seconds.

## 8. Reports Tab Detail

### 8.1 Layout

```
ReportsTab
├── Picker: "Today" | "This Week" | "This Month"  (reuses HistoryStore data)
├── Header Card
│   ├── Avg health (large, colored)
│   ├── Total cost
│   ├── Model
│   └── Sample count
├── Charts (Swift Charts — import Charts)
│   ├── ECG Timeline: Chart { LineMark } — tok/min over time
│   ├── Cost Burn: Chart { AreaMark } — cumulative cost
│   ├── Tool Usage: Chart { BarMark } — calls/min
│   └── Cache Efficiency: Chart { SectorMark } — doughnut hit/miss/creation
├── Anomaly Table: List of anomaly records
└── Insights: auto-generated text summary (same logic as ReportGenerator.generateSummary)
```

### 8.2 Shared Data

TrendsTab and ReportsTab both consume HistoryStore data. No duplication — HistoryStore is the single source of truth, owned by AppState, shared via @ObservedObject.

### 8.3 Legacy ReportGenerator

Kept as-is for external HTML export (button in Reports tab: "Export HTML"). Not the primary view anymore.

## 9. Custom Sound Generation

Generate a 1-second .aiff file:
- Two quick heartbeat pulses (thump-thump) with fade out
- 440Hz sine wave, 44.1kHz sample rate, 16-bit
- Generated via `afconvert` or Python script at build time
- Stored in Resources/inkpulse_alert.aiff

## 10. Info.plist Changes

Add to existing Info.plist:
```xml
<key>NSUserNotificationsUsageDescription</key>
<string>InkPulse sends notifications when Claude Code sessions encounter critical anomalies.</string>
```

## 11. Build Sequence

1. Rename DashboardView.swift → LiveTab.swift (update all references)
2. Create TabbedDashboard.swift (TabView wrapper)
3. Update InkPulseApp.swift to use TabbedDashboard
4. Create HistoryStore.swift (persistence layer)
5. Create TrendsTab.swift (UI consuming HistoryStore)
6. Create ReportsTab.swift (UI consuming HistoryStore)
7. Create NotificationManager.swift
8. Create AnomalyWatcher.swift
9. Wire AnomalyWatcher into AppState refresh cycle
10. Generate inkpulse_alert.aiff sound
11. Update Info.plist
12. Build, test, deploy to /Applications

## 12. Success Criteria

- [ ] Tabbed dashboard opens with Live/Trends/Reports tabs
- [ ] Live tab works identically to current DashboardView
- [ ] Trends tab shows today/week/month views with real heartbeat data
- [ ] Reports tab renders native Swift Charts (no browser)
- [ ] macOS notification fires on hemorrhage/explosion/loop with custom sound
- [ ] Notification cooldown prevents spam (5min per-session, 30s global)
- [ ] Zero external dependencies added
- [ ] App builds and runs from /Applications with login item

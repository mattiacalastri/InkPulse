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
| AppState.swift | Adds NotificationManager, AnomalyWatcher, HistoryStore as @Published properties. Wires AnomalyWatcher into refresh cycle. |
| Package.swift | platforms remains `.macOS(.v14)`. Swift Charts and UserNotifications are system frameworks — `import Charts` and `import UserNotifications` resolve automatically against the macOS SDK in both `swift build` and Xcode. No `.linkedFramework` needed. Verified: SPM resolves system frameworks at link time via the SDK path. |
| Info.plist | Located at `/Applications/InkPulse.app/Contents/Info.plist` (created during deploy step, not in SPM source tree). The deploy script copies binary + Info.plist + Resources into the .app bundle. UNUserNotificationCenter requires a valid .app bundle with code identity — the existing deploy process already produces this. Add `NSUserNotificationsUsageDescription`. |

### 5.1 State Injection Pattern

All three tabs receive `appState` via `@ObservedObject` parameter injection (same pattern as existing `PopoverView` and `DashboardView`). No `@EnvironmentObject` — explicit dependency passing is simpler and consistent with the v1 codebase.

```swift
// TabbedDashboard passes appState to each tab:
TabView {
    LiveTab(appState: appState).tabItem { ... }
    TrendsTab(appState: appState).tabItem { ... }
    ReportsTab(appState: appState).tabItem { ... }
}
```

Each tab accesses `appState.historyStore` for historical data and `appState.metricsEngine` for live data.

## 6. Trends Tab Detail

### 6.1 Data Model

```swift
struct DaySummary {
    let date: Date
    let avgHealth: Int          // Int intentionally — consistent with MetricsSnapshot.health
                                 // and HealthResult.score across the entire codebase.
                                 // Precision loss from integer averaging is acceptable for
                                 // dashboard display. Charts use raw records for interpolation.
    let totalCost: Double
    let peakTokenMin: Double
    let totalSessions: Int       // Count of unique sessionIds in the day's records
    let activeMinutes: Double
    let anomalyCount: Int
    let avgCacheHit: Double
    let avgErrorRate: Double
    let records: [HeartbeatRecord] // raw data for drill-down and chart interpolation
}
```

**"Worst session" definition** (used in Week View §6.3): Group all `HeartbeatRecord` entries by `sessionId`. For each session, compute `avgHealth = records.map(\.health).reduce(0,+) / records.count`. Sort ascending by `avgHealth`. Take top 3. Display: sessionId prefix, project name, avgHealth, anomaly count.

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
- Heatmap: Calendar-aligned grid (Mon-Sun × weeks of the month) colored by avg health. GitHub-contributions style, teal palette. **Missing days** (no heartbeat file = no Claude usage) render as dark grey cells with no value — they are not zero, they are absent. The grid always shows the full calendar month, not just days with data.
- Cumulative cost: AreaMark rising day by day with dashed projection to month end
- Usage pattern: bar chart of active hours per weekday (when you work most)
- Monthly summary: total cost, total sessions, total anomalies, health trend direction

### 6.5 HistoryStore Implementation

HistoryStore reads `~/.inkpulse/heartbeats/heartbeat-YYYY-MM-DD.jsonl` files.

- `loadToday()`: reads today's file, returns raw `[HeartbeatRecord]`
- `loadWeek()`: reads last 7 files, aggregates into `[DaySummary]`
- `loadMonth()`: reads last 30 files, aggregates into `[DaySummary]`
- Parsing is lazy: stream lines, decode one at a time, never load full file into memory
- Refresh intervals:
  - `loadToday()`: 10 seconds (near-real-time for today's ECG, reduces visible lag vs Live tab's 1s)
  - `loadWeek()` / `loadMonth()`: 60 seconds (historical data doesn't change fast)
- Cache: in-memory cache of loaded DaySummary, invalidated on refresh

## 7. Notification System Detail

### 7.1 AnomalyWatcher

Runs inside AppState's existing 1s refresh cycle. After `metricsEngine.refreshSnapshots()`:

```swift
// Critical anomaly set — only these trigger notifications
static let criticalAnomalies: Set<Anomaly> = [.hemorrhage, .explosion, .loop]

for (sessionId, snapshot) in metricsEngine.sessions {
    // Convert String? → Anomaly? via rawValue
    let currentAnomaly: Anomaly? = snapshot.anomaly.flatMap { Anomaly(rawValue: $0) }
    let previousAnomaly: Anomaly? = previousAnomalyState[sessionId]

    if let anomaly = currentAnomaly,
       Self.criticalAnomalies.contains(anomaly),
       previousAnomaly == nil {
        if !isInCooldown(sessionId: sessionId, anomaly: anomaly) {
            let project = projectName(from: sessionId, ...)
            notificationManager.send(
                title: anomaly.notificationTitle,   // e.g. "Token Hemorrhage"
                body: anomaly.notificationBody(project: project, snapshot: snapshot)
            )
            setCooldown(sessionId: sessionId, anomaly: anomaly)
        }
    }

    previousAnomalyState[sessionId] = currentAnomaly
}
```

**Anomaly extension for notification text** (added to HealthScore.swift):
```swift
extension Anomaly {
    var notificationTitle: String { ... }  // "Token Hemorrhage", "Agent Explosion", "Error Loop"
    func notificationBody(project: String, snapshot: MetricsSnapshot) -> String { ... }
}
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
- `send(title: String, body: String)`: the single public API. AnomalyWatcher formats the title/body using `Anomaly.notificationTitle` and `Anomaly.notificationBody(project:snapshot:)`, then calls this method. NotificationManager only knows about strings — it does not import or understand `Anomaly`.
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

Kept as-is for **opt-in** external HTML export. The Reports tab includes a secondary "Export HTML" button (small, bottom-right, non-prominent) that generates the HTML report via `ReportGenerator.generate()` and opens it in the browser. This is an escape hatch for sharing reports externally — it is NOT the primary reporting experience. The primary experience is the native Swift Charts in-app.

## 9. Custom Sound Generation

**Pre-generated and committed to repo** (not generated at build time — SPM has no run-script build phases).

The sound file `Resources/inkpulse_alert.aiff` is:
- 1 second, two quick heartbeat pulses (thump-thump) with fade out
- 440Hz sine wave, 44.1kHz sample rate, 16-bit Linear PCM
- Generated once via Python script (`scripts/generate_alert_sound.py`), then committed as a binary
- The deploy script copies it into `/Applications/InkPulse.app/Contents/Resources/`
- SPM includes it via `.copy("../Resources")` in Package.swift (already configured)

## 10. Info.plist Changes

Add to existing Info.plist:
```xml
<key>NSUserNotificationsUsageDescription</key>
<string>InkPulse sends notifications when Claude Code sessions encounter critical anomalies.</string>
```

## 11. Build Sequence

1. Rename DashboardView.swift → LiveTab.swift. Update: struct name `DashboardView` → `LiveTab` inside the file, and the reference in `InkPulseApp.swift` (replaced by TabbedDashboard in step 3). The `@ObservedObject var appState: AppState` pattern remains unchanged.
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

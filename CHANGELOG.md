# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [v1.3.0] - 2026-03-25

### Added
- DashboardStats shared struct — eliminates duplicated computed properties between PopoverView and LiveTab
- Pillar identity mapping — BTC Bot (teal), AuraHome (gold), Astra (blue), Astra OS (purple) with config overrides
- activeTaskName parsing from TaskCreate/TaskUpdate tool_use blocks in JSONL
- Dynamic ScrollView height in popover — adapts to agent count and expanded state

### Fixed
- activeTaskName was declared but never written (always nil)
- PopoverView ScrollView hardcoded to 350px regardless of session count

## [v1.2.0] - 2026-03-23

### Added
- 2-column agent grid with wider popover layout
- Expand detail panel for individual agents
- Git branch differentiation in LiveTab
- Pulse animation and activity indicator for living agent UX
- Open Terminal action from agent cards

### Fixed
- Tool error detection from user events with `is_error` flag
- Forced 350px height for agent cards ScrollView
- Popover minHeight 620 for agent cards visibility

## [v1.1.0] - 2026-03-22

### Added
- EGI Detector with enhanced agent cards and new AppIcon
- Orchestration UX overhaul: pillar identity, anomaly heatmap, cost waste, actionable insights
- ReportsTab with native Swift Charts replacing HTML reports
- TrendsTab with Today/Week/Month views and Swift Charts
- HistoryStore data layer for heartbeat JSONL history
- AnomalyWatcher with cooldown logic
- NotificationManager with UNUserNotificationCenter
- Anomaly notification text extension
- Custom InkPulse alert sound (heartbeat pulse)
- 11 EGI tests

### Changed
- Renamed DashboardView to LiveTab, added TabbedDashboard shell
- Refactored TrendsTab into focused files with shared components

### Fixed
- Aggressive health decay, trend arrows, cost tracking, health alerts
- Popover maxHeight 500 to 700 for agent visibility
- Polished ReportsTab with clean ECG, grouped anomalies, better labels
- Improved TodayTrendView with clean ECG line and grouped anomalies
- Prevented crash when UNUserNotificationCenter has no bundle

## [v1.0.0] - 2026-03-20

### Added
- JSONL parser with typed ClaudeEvent and 8 tests
- Metrics engine with health score, anomaly detection, and 12 tests
- File tailer and session watcher with polling
- Heartbeat logger with offset checkpoint persistence
- SwiftUI menu bar UI with pulsating heart and popover
- HTML report generator with Chart.js dark theme
- Emoji mood, project names, health bars, status text
- Data-dense popover with stats strip, ECG label, and bottom bar
- Native SwiftUI config panel with action buttons
- CWD-based project names
- README and MIT license

[v1.2.0]: https://github.com/mattiacalastri/InkPulse/compare/v1.1.0...v1.2.0
[v1.1.0]: https://github.com/mattiacalastri/InkPulse/compare/v1.0.0...v1.1.0
[v1.0.0]: https://github.com/mattiacalastri/InkPulse/releases/tag/v1.0.0

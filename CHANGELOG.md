# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [v2.3.0] - 2026-04-03

### Added
- MCP Hub (Phase 4) — shared MCP server pool with TCP proxy, eliminates N*M process duplication
- 23 stress tests for MCPRouter + MCPServerManager
- Adaptive agent cards — compact when idle, full detail when active
- Compact footer with capsule buttons

### Changed
- Version aligned across ConfigView and LiveTab (was inconsistent v2.1.0/v2.2.0)

### Fixed
- Flexible decoder test aligned with graceful degradation behavior (malformed JSON → empty missions)
- Swift strict concurrency warnings in MCP Hub closures
- PromptBox removed from popover — data over poetry

## [v2.2.0] - 2026-03-28

### Added
- Dynamic orchestrator spawning — Claude meta-prompt generates missions, InkPulse spawns them
- OrchestrateSpawner with identity-infused meta-prompt (Percezione Liminale, 7 Idee Pure)
- MissionsWatcher with FSEvents + poll fallback
- MissionConfig, MissionsFile, OrchestratePhase types
- Orchestrate button in LiveTab header with phase state machine

### Fixed
- Concurrency error in orchestrate timeout handler
- 3 known issues resolved + dynamic team auto-grouping

## [v2.1.0] - 2026-03-27

### Added
- Setup Wizard — organize teams in 30 seconds, zero manual JSON
- Deck editor — customize motivational quotes from Config UI
- Unified menu bar — polpo icon with health, tok/min, cost metrics
- Externalized prompt deck to JSON loader with generic EN deck for OSS

### Changed
- Removed all hardcoded project names — fully dynamic pillar system
- Workspace team + overflow agent grouping + live menu bar

### Fixed
- .gitignore hardened with credential patterns

## [v2.0.0] - 2026-03-26

### Added
- Team UI (Phase 1) — org chart replaces flat agent list
- One-Click Spawn (Phase 2) — spawn terminal windows per team/role with AppleScript
- WebSocket control channel (Phase 3) — bidirectional IPC on localhost:9999
- EventDetector for significant event notifications (Phase 5)
- SessionKiller with confirmation alert on role cards
- PromptBoxView identity prompt picker
- v3 SPEC — control plane vision for multi-agent Claude Code teams
- Apache 2.0 license + README rewrite for GitHub growth

### Changed
- Architecture evolved from passive monitor to active control plane
- CodexBar absorbed — accurate pricing, live quota sync, incremental scan

### Fixed
- Process resolution via pgrep -f for reliable claude PID matching
- AppleScript quoting — single escape layer for do script
- Terminal window matching simplified to title-based approach
- Ghost session detection and cleanup

## [v1.4.0] - 2026-03-25

### Added
- Project name inference from tool paths when cwd is Home (ring buffer + frequency analysis)
- 15 new pillar tests, total 60
- Smart capitalize for inferred project names

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

[v2.3.0]: https://github.com/mattiacalastri/InkPulse/compare/v2.2.0...v2.3.0
[v2.2.0]: https://github.com/mattiacalastri/InkPulse/compare/v2.1.0...v2.2.0
[v2.1.0]: https://github.com/mattiacalastri/InkPulse/compare/v2.0.0...v2.1.0
[v2.0.0]: https://github.com/mattiacalastri/InkPulse/compare/v1.4.0...v2.0.0
[v1.4.0]: https://github.com/mattiacalastri/InkPulse/compare/v1.3.0...v1.4.0
[v1.3.0]: https://github.com/mattiacalastri/InkPulse/compare/v1.2.0...v1.3.0
[v1.2.0]: https://github.com/mattiacalastri/InkPulse/compare/v1.1.0...v1.2.0
[v1.1.0]: https://github.com/mattiacalastri/InkPulse/compare/v1.0.0...v1.1.0
[v1.0.0]: https://github.com/mattiacalastri/InkPulse/releases/tag/v1.0.0

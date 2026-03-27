# InkPulse

**Control Plane for AI Agent Teams** — a native macOS app that monitors, organizes, and orchestrates Claude Code sessions in real-time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-green)

## The Problem

Claude Code is built for 1 developer, 1 project, 1 terminal. Power users running 8-15 sessions across multiple projects face:

- **No team structure** — flat list of sessions with no logical grouping
- **No orchestration** — can't spawn or coordinate sessions from a central point
- **No inter-session awareness** — each session is an island
- **Cognitive overload** — tab-switching across 15 terminals is unsustainable

InkPulse solves this.

## What It Does

### Team Org Chart
Sessions grouped into teams with named roles. No more flat lists.

```
Bot Team [~/btc_predictions]
  PM         — roadmap, priorities
  Dev        — code, deploy, debug
  Researcher — R&D, experiments

AuraHome Team [~/projects/aurahome]
  PM         — product roadmap
  Dev        — WP/WooCommerce
  Content    — SEO, copy, i18n
```

### One-Click Spawn
Click **Spawn** on a team and InkPulse opens Terminal windows for each role, running Claude Code with the role prompt injected. Agents start working immediately.

### Real-Time Health Monitoring
8 metrics tracked per session with sliding windows:

| Metric | What it measures |
|--------|-----------------|
| tok/min | Token throughput (60s window) |
| Cache hit | Cache read vs total input ratio |
| Error rate | Failed tool calls (5min window) |
| Cost | Running session cost in EUR |
| Context % | Context window utilization |
| Subagents | Spawned agent count |
| Think:Output | Reasoning vs output ratio |
| Idle gaps | Pause time between events |

### Smart Notifications
macOS alerts for deploy completion, error spikes, idle agents burning credits.

### WebSocket Control Channel
Bidirectional communication between InkPulse and Claude Code sessions on `localhost:9998`. Send tasks to specific agents programmatically.

## Installation

```bash
git clone https://github.com/mattiacalastri/InkPulse.git
cd InkPulse
swift build -c release
```

### Install to Applications

```bash
cp -f .build/release/InkPulse /Applications/InkPulse.app/Contents/MacOS/InkPulse
open /Applications/InkPulse.app
```

### Requirements

- macOS 14.0 Sonoma or later
- Claude Code installed (`~/.claude/projects/` must exist)
- Swift 5.9+ (Xcode 15+)

## Configuration

### Teams (`~/.inkpulse/teams.json`)

```json
{
  "teams": [
    {
      "id": "backend",
      "name": "Backend",
      "cwd": "~/projects/my-api",
      "color": "#00d4aa",
      "roles": [
        {
          "id": "pm",
          "name": "PM",
          "prompt": "You are the Project Manager. Read CLAUDE.md, prioritize tasks.",
          "icon": "chart.bar.fill"
        },
        {
          "id": "dev",
          "name": "Dev",
          "prompt": "You are the Lead Developer. Implement features and fix bugs.",
          "icon": "hammer.fill"
        },
        {
          "id": "reviewer",
          "name": "Reviewer",
          "prompt": "You are the Code Reviewer. Review PRs and suggest improvements.",
          "icon": "magnifyingglass"
        }
      ]
    }
  ]
}
```

Each team maps to a working directory. Roles define the prompts injected when spawning agents.

### Settings (`~/.inkpulse/config.json`)

Optional overrides for refresh rate, session timeout, health score weights, daily budget alerts, and pillar color overrides.

## Architecture

```
InkPulse.app (Swift, single binary)
  UI Layer (SwiftUI)           WebSocket Server (Network.framework, :9998)
    Team Org Chart               Session Registry
    Role Cards                   Command Dispatch
    Spawn Buttons                Status Receive

  JSONL Monitor                Notifications
    File Tailer                  EventDetector (deploy, errors, idle)
    Metrics Engine               AnomalyWatcher (stall, loop, hemorrhage)
    Health + EGI Score           macOS UNUserNotificationCenter
```

Zero dependencies. Everything is built with Apple frameworks.

## How It Works

1. InkPulse watches `~/.claude/projects/` for JSONL log files
2. Parses events, computes 8 health metrics per session with sliding windows
3. Matches sessions to team roles by working directory
4. Shows live org chart in menu bar popover + full window dashboard
5. Spawn opens Terminal.app windows with `claude "<role prompt>"`
6. WebSocket server enables bidirectional control

**Read-only** — InkPulse never modifies Claude Code files.

## Roadmap

- [x] Team org chart with collapsible sections
- [x] One-click spawn with role prompts
- [x] WebSocket control channel
- [x] Smart event notifications
- [ ] MCP Hub — shared MCP server pool (N*M processes -> M+1)
- [ ] Send Task UI — dispatch prompts to agents from dashboard

## License

Apache 2.0

## Author

Built by [Mattia Calastri](https://github.com/mattiacalastri) with Claude Code.

Part of the [Astra Digital](https://digitalastra.it) ecosystem.

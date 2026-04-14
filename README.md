<!--
SEO Keywords: claude code, anthropic, ai agents, orchestration, macos, menubar, swiftui,
swift, mcp, developer tools, control plane, multi-agent, cost monitoring, anomaly detection,
italian ai, astra digital, polpo squad
SEO Description: The missing control plane for Claude Code. Monitor, organize, and orchestrate AI agent teams from your macOS menu bar. 11K lines of Swift. Zero dependencies.
Author: Mattia Calastri
Location: Verona, Italy
-->

<div align="center">

# 🐙 InkPulse

### The missing control plane for Claude Code.

Monitor, organize, and orchestrate AI agent teams from your macOS menu bar.
**11K lines of Swift. Zero dependencies.**

[![License](https://img.shields.io/github/license/mattiacalastri/InkPulse?color=00d4aa&labelColor=0a0f1a)](./LICENSE)
[![Stars](https://img.shields.io/github/stars/mattiacalastri/InkPulse?color=00d4aa&labelColor=0a0f1a)](https://github.com/mattiacalastri/InkPulse/stargazers)
[![Issues](https://img.shields.io/github/issues/mattiacalastri/InkPulse?color=00d4aa&labelColor=0a0f1a)](https://github.com/mattiacalastri/InkPulse/issues)
[![Swift](https://img.shields.io/badge/Swift-5.9-00d4aa?labelColor=0a0f1a&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13+-00d4aa?labelColor=0a0f1a&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Zero Deps](https://img.shields.io/badge/dependencies-zero-00d4aa?labelColor=0a0f1a)](#)
[![Astra Digital](https://img.shields.io/badge/built_by-Astra_Digital-00d4aa?labelColor=0a0f1a)](https://mattiacalastri.com)

</div>

---

## ✨ Why

Managing concurrent Claude Code sessions today means:

- Tab-switching across 15 terminals with no logical grouping
- No way to spawn or coordinate sessions from one place
- Cost and token usage invisible until the bill arrives
- Anomalies (runaway loops, exploding context) go unnoticed
- N sessions × M MCP servers = dozens of duplicated processes

**InkPulse replaces that chaos with a single control plane.**

## 🎯 Features

- 🐙 **Team Org Chart** — Group sessions into named teams and roles, not a flat terminal list
- ⚡ **One-Click Spawn** — Launch an entire agent team with correct directories and role prompts
- 📊 **8 KPI Metrics** — tok/min, cache hit ratio, error rate, cost, context %, subagent count, think:output ratio, idle gaps
- 🚨 **Anomaly Detection** — Hemorrhage, explosion, and loop alerts before they burn your credits
- 🔌 **MCP Hub** — Shared MCP server pool across all sessions (N agents, 1 set of processes)
- 💰 **Cost Governance** — Daily budget with progress bar and threshold alerts
- 🔗 **WebSocket Control** — Bidirectional channel on `localhost:9998` for programmatic automation
- 🧠 **Smart Inference** — Auto-detects which project a session is working on from file paths

## 🚀 Quick Start

```bash
git clone https://github.com/mattiacalastri/InkPulse.git
cd InkPulse && swift build -c release
open .build/release/InkPulse.app
```

Requires macOS 13+ and Swift 5.9+ (Xcode 15+).

## 📖 What It Does

Claude Code runs one session per terminal. Power users running 8–15 sessions across multiple projects hit a wall: no grouping, no orchestration, no visibility into cost or anomalies.

InkPulse sits in your menu bar and gives you a bird's-eye view of everything your AI agents are doing.

| Layer | What it provides |
|-------|-----------------|
| **Team Org Chart** | Group sessions into teams with named roles (PM, Dev, Reviewer). Each team maps to a project directory. Collapsible sections, team-level aggregate stats. |
| **One-Click Spawn** | Click Spawn on any team — InkPulse opens Terminal windows for each role with the correct working directory and role prompt injected. Agents start working immediately. |
| **8 KPI Metrics** | Real-time health monitoring per session using sliding windows: token throughput, cache efficiency, error rate, running cost, context utilization, subagent count, reasoning ratio, idle time. |
| **Anomaly Detection** | Catches cost hemorrhage, token explosion, and tool-call loops. Native macOS notifications with cooldown logic to prevent alert fatigue. |
| **MCP Hub** | Shared MCP server pool. Instead of N sessions × M servers = N·M processes, InkPulse proxies all tool calls through a single set of server instances. |
| **Cost Governance** | Set a daily spending limit. Progress bar in the UI. Alert near the cap. The AI that regulates its own spending. |

Architecture is read-only — InkPulse never modifies your Claude Code files or sessions.

## 🏗️ Architecture

```mermaid
graph TB
    M[Menu Bar] --> V[SwiftUI Views]
    V --> VM[ViewModels]
    VM --> S[Session Store]
    S --> CC[Claude Code Logs]
    VM --> K[KPI Engine]
    K --> A[Anomaly Detector]
    A --> N[macOS Notifications]
    VM --> H[MCP Hub]
    H --> P[Process Pool]
    VM --> WS[WebSocket :9998]
```

## ⚙️ Configuration

Define your teams in `~/.inkpulse/teams.json`:

```json
{
  "teams": [
    {
      "id": "backend",
      "name": "Backend",
      "cwd": "~/projects/my-api",
      "color": "#00d4aa",
      "roles": [
        { "id": "pm", "name": "PM", "prompt": "You are the Project Manager...", "icon": "chart.bar.fill" },
        { "id": "dev", "name": "Dev", "prompt": "You are the Lead Developer...", "icon": "hammer.fill" },
        { "id": "reviewer", "name": "Reviewer", "prompt": "You are the Code Reviewer...", "icon": "magnifyingglass" }
      ]
    }
  ]
}
```

## 🛠️ Built With

Pure Apple frameworks. No SPM dependencies. No CocoaPods. No Carthage.

![Swift](https://img.shields.io/badge/Swift-5.9-00d4aa?labelColor=0a0f1a&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-native-00d4aa?labelColor=0a0f1a&logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-menubar-00d4aa?labelColor=0a0f1a&logo=apple&logoColor=white)
![Combine](https://img.shields.io/badge/Combine-reactive-00d4aa?labelColor=0a0f1a)
![Network](https://img.shields.io/badge/Network-WebSocket-00d4aa?labelColor=0a0f1a)

- **SwiftUI** — all UI
- **Network** — WebSocket server
- **Combine** — reactive data flow
- **AppKit** — menu bar, notifications, Terminal.app integration

## 🗺️ Roadmap

- [ ] Send Task UI — dispatch prompts to agents from dashboard
- [ ] macOS widget for daily cost
- [ ] Cross-session data export
- [ ] iTerm2 / Warp terminal support

## 🤝 Contributing

Contributions welcome. See [open issues](https://github.com/mattiacalastri/InkPulse/issues).

```bash
git clone https://github.com/mattiacalastri/InkPulse.git
cd InkPulse && swift build && swift test
```

## 📄 License

[Apache 2.0](LICENSE)

## 🔗 Links

- 🌐 [mattiacalastri.com](https://mattiacalastri.com) · [digitalastra.it](https://digitalastra.it)
- 🐙 [Polpo Cockpit](https://github.com/mattiacalastri/polpo-cockpit) — the ~600-line sibling for single-project orchestration
- 🔨 [AI Forging Kit](https://github.com/mattiacalastri/AI-Forging-Kit) — the method behind the agents
- 🎙️ [Jarvis STT](https://github.com/mattiacalastri/jarvis-stt) — voice dictation for Claude Code

---

<div align="center">

**Built with 🐙 by [Mattia Calastri](https://mattiacalastri.com) · [Astra Digital Marketing](https://digitalastra.it)**

*AI for humans, not for hype*

</div>

# InkPulse v3 — SPEC

> The Best App for Claude Code
> Control Plane for AI Agent Teams
> Open Source — Apache 2.0
> By Mattia Calastri / Astra Digital

---

## 1. Problem Statement

Claude Code is designed for 1 developer, 1 project, 1 terminal. Power users running 8-15 concurrent sessions across multiple projects face:

- **No team structure**: flat list of sessions with no logical grouping
- **No orchestration**: can't spawn, command, or coordinate sessions from a central point
- **No inter-session awareness**: each session is an island
- **Resource waste**: N sessions x M MCP servers = N*M duplicated processes (57 observed for 8 sessions)
- **Cognitive overload**: tab-switching across 15 terminals is unsustainable

InkPulse v3 evolves from a passive heartbeat monitor to an **active control plane** for multi-agent Claude Code teams.

---

## 2. Architecture Overview

```
+----------------------------------------------------------+
|                    InkPulse.app (Swift)                   |
|                                                          |
|  +------------------+  +--------------------+            |
|  |   UI Layer       |  |  WebSocket Server  |            |
|  |   (SwiftUI)      |  |  (NIO, :9999)      |            |
|  |                  |  |                    |            |
|  |  - Team View     |  |  - Session registry|            |
|  |  - Org Chart     |  |  - Command dispatch|            |
|  |  - Spawn Panel   |  |  - Status receive  |            |
|  |  - Notifications |  +--------------------+            |
|  +------------------+                                    |
|                                                          |
|  +------------------+  +--------------------+            |
|  |  JSONL Monitor   |  |  MCP Proxy         |            |
|  |  (existing)      |  |  (NIO + stdio)     |            |
|  |                  |  |                    |            |
|  |  - File tailer   |  |  - Shared pool     |            |
|  |  - Metrics       |  |  - Tool routing    |            |
|  |  - Health/EGI    |  |  - ~10 processes   |            |
|  +------------------+  +--------------------+            |
+----------------------------------------------------------+
         |                        |
         v                        v
  Claude Code Sessions      MCP Servers (shared)
  (Terminal.app windows)     (fal, telegram, github, ...)
```

Single binary. Everything inside InkPulse.app.

---

## 3. Features

### 3.1 Team Orchestration (Layer 1 — Org Chart UI)

**From flat agent list to living org chart.**

Each pillar is a team. Each team has up to 3 roles: PM + Dev + 1 custom.

```
Bot Team [~/btc_predictions]
  PM         — roadmap, fix priority
  Dev        — code, deploy, debug
  Researcher — crazy ideas, R&D

AuraHome Team [~/projects/aurahome]
  PM         — product roadmap
  Dev        — WP/WooCommerce deploy
  Content    — SEO, copy, i18n

Astra Team [~/Downloads/Astra Digital Marketing]
  PM         — MRR, pipeline, deadlines
  ClientOps  — email, invoices, reminders
  Researcher — AI Souls, positioning

Brand OS Team [~/claude_voice]
  PM         — infra roadmap
  Dev        — Railway, MCP, hooks
  Content    — TG, LinkedIn, social
```

**Config**: `~/.inkpulse/teams.json`

```json
{
  "teams": [
    {
      "id": "bot",
      "name": "BTC Bot",
      "cwd": "~/btc_predictions",
      "color": "#FF6B35",
      "roles": [
        {
          "id": "pm",
          "name": "PM",
          "prompt": "You are the Project Manager for the BTC Predictor Bot. Your job is to read the current roadmap, prioritize fixes and features, and coordinate with the Dev agent. Start by reading session_current.md and CLAUDE.md.",
          "icon": "chart.bar.fill"
        },
        {
          "id": "dev",
          "name": "Dev",
          "prompt": "You are the Lead Developer for the BTC Predictor Bot. Your job is to implement fixes, features, and deploy. Start by reading CLAUDE.md and checking git status.",
          "icon": "hammer.fill"
        },
        {
          "id": "researcher",
          "name": "Researcher",
          "prompt": "You are the R&D Researcher for the BTC Predictor Bot. Explore crazy ideas, test hypotheses, research new approaches. Read the crazy ideas garden and propose experiments.",
          "icon": "magnifyingglass"
        }
      ]
    }
  ]
}
```

**UI behavior**:
- PopoverView shows teams as collapsible sections (replacing flat "ACTIVE AGENTS" list)
- Each role slot shows: occupied (session active) or vacant (grey, "not running")
- Team-level aggregate stats: total cost, combined health, active count
- Clicking a role: Open terminal (existing cwd-match + miniaturize behavior)
- Full window (LiveTab) shows expanded org chart with detail panels per team

### 3.2 One-Click Spawn (Layer 2 — Control Plane)

**"Spawn Team" button per team.**

Click: InkPulse opens N Terminal.app windows (one per role), each running:
```bash
cd <team.cwd> && claude --prompt "<role.prompt>"
```

If `--prompt` is not supported by claude CLI, fallback:
1. Open terminal, cd to cwd
2. Run `claude`
3. Inject prompt via AppleScript keystroke after 2s delay

**Spawn behavior**:
- Each role gets its own Terminal.app window (separate windows, not tabs)
- Window title set via AppleScript: "InkPulse — Bot/PM"
- InkPulse tracks which sessions it spawned (by PID or TTY)
- "Spawn" button greys out for roles already running
- Individual role spawn: click vacant role slot to spawn just that one

### 3.3 WebSocket Control Channel (Layer 2 — Bidirectional IPC)

**InkPulse runs a WebSocket server on localhost:9999.**

A Claude Code hook (SessionStart) auto-connects each session:

```bash
# ~/.inkpulse/hooks/ws_client.sh
# Launched by Claude Code SessionStart hook
# Maintains WebSocket connection for bidirectional control
```

**Protocol** (JSON over WebSocket):

```json
// Session -> InkPulse (status update)
{
  "type": "status",
  "session_id": "abc123",
  "cwd": "/Users/.../btc_predictions",
  "state": "working",
  "current_tool": "Edit",
  "current_target": "main.py",
  "task": "Implementing phase engine fix"
}

// InkPulse -> Session (command)
{
  "type": "command",
  "action": "task",
  "prompt": "Prioritize the council rebalance fix over the cache optimization"
}

// InkPulse -> Session (notification from another agent)
{
  "type": "notify",
  "from_team": "bot",
  "from_role": "pm",
  "message": "Deploy approved, proceed with railway push"
}
```

### 3.4 MCP Hub (Infrastructure — Shared Server Pool)

**Single proxy inside InkPulse that serves all MCP tools to all sessions.**

```
Before: Session1 -> [fal, tg, github, linkedin, x, bridge, ...]  (7 procs)
        Session2 -> [fal, tg, github, linkedin, x, bridge, ...]  (7 procs)
        = N * 7 processes

After:  Session1 -> InkPulse MCP Proxy -> [fal, tg, github, ...]  (shared)
        Session2 -> InkPulse MCP Proxy -> [same instances]
        = 1 proxy + 7 server processes total
```

**Implementation**:
- InkPulse reads `~/.claude.json` to know which MCP servers are configured
- Launches each server once, maintains stdio pipes via NIO
- Exposes a local MCP-compatible endpoint (stdio proxy or HTTP+SSE)
- Sessions point their MCP config to the proxy instead of individual servers
- Proxy handles request routing and response multiplexing

**Session config change** (`~/.claude.json`):
```json
{
  "mcpServers": {
    "inkpulse-proxy": {
      "type": "stdio",
      "command": "~/.inkpulse/mcp-proxy-client",
      "args": ["--port", "9997"]
    }
  }
}
```

### 3.5 macOS Notifications

Significant events detected from JSONL patterns:

- **Deploy completed** (git push, railway deploy)
- **Email sent** (gmail_create_draft)
- **Build passed/failed** (swift build, npm test)
- **Task completed** (TaskUpdate status=completed)
- **Error spike** (error rate > 10%)

Native macOS notification via `UNUserNotificationCenter`. Click opens the terminal for that session.

---

## 4. UI Mockup — Popover

```
+-------------------------------------------------------+
|  InkPulse                          68 HEALTH    [gear] |
|  4 teams - 8 agents - 2h uptime                       |
+-------------------------------------------------------+
|  1266 tok/min | 3514 peak | 98% cache | E2.40 cost    |
+-------------------------------------------------------+
|  ECG ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~          |
+-------------------------------------------------------+
|                                                        |
|  v Bot Team                              [Spawn]       |
|  +-------------+ +-------------+ +-------------+      |
|  | * PM        | | * Dev       | | o Researcher |      |
|  | Working     | | Forging     | | (vacant)     |      |
|  | roadmap.md  | | main.py     | |              |      |
|  | 45  E0.12   | | 89  E0.80   | | [Spawn]      |      |
|  | [Open]      | | [Open]      | |              |      |
|  +-------------+ +-------------+ +-------------+      |
|                                                        |
|  > AuraHome Team                         [Spawn]       |
|  > Astra Team                  [2 active][Spawn]       |
|  > Brand OS Team               [1 active][Spawn]       |
|                                                        |
+-------------------------------------------------------+
|  [Report]        [Pause]        [Config]               |
+-------------------------------------------------------+
```

---

## 5. Data Model

```swift
struct TeamConfig: Codable, Identifiable {
    let id: String
    let name: String
    let cwd: String
    let color: String
    let roles: [RoleConfig]
}

struct RoleConfig: Codable, Identifiable {
    let id: String
    let name: String
    let prompt: String
    let icon: String
}

struct TeamState: Identifiable {
    let id: String  // matches TeamConfig.id
    let config: TeamConfig
    var slots: [RoleSlot]
}

struct RoleSlot: Identifiable {
    let id: String  // matches RoleConfig.id
    let role: RoleConfig
    var session: MetricsSnapshot?  // nil = vacant
    var sessionId: String?
}
```

---

## 6. New/Modified Files

```
Sources/
  Config/
    TeamConfig.swift         (NEW — team/role data model + Codable)
    TeamsLoader.swift        (NEW — reads ~/.inkpulse/teams.json)
  UI/
    PopoverView.swift        (MODIFIED — team sections replace flat list)
    TeamSectionView.swift    (NEW — collapsible team with role cards)
    RoleCardView.swift       (NEW — role slot card, vacant or occupied)
    SpawnButton.swift        (NEW — spawn team or individual role)
    LiveTab.swift            (MODIFIED — org chart layout)
  Actions/
    TerminalOpener.swift     (MODIFIED — window title setting)
    TeamSpawner.swift        (NEW — spawn N Terminal windows for team)
  WebSocket/
    WSServer.swift           (NEW — NIO WebSocket server :9999)
    SessionRegistry.swift    (NEW — connected sessions, role mapping)
    WSProtocol.swift         (NEW — message types JSON codable)
  MCP/
    MCPProxy.swift           (NEW — shared MCP server pool manager)
    MCPServerManager.swift   (NEW — launch/maintain stdio server procs)
    MCPRouter.swift          (NEW — route tool calls session -> server)
  Notifications/
    NotificationManager.swift (NEW — UNUserNotificationCenter)
    EventDetector.swift      (NEW — detect significant events from JSONL)

~/.inkpulse/
  teams.json               (team configuration file)
  hooks/
    ws_client.sh           (Claude Code SessionStart hook script)
```

---

## 7. Implementation Phases

### Phase 1 — Team UI
1. TeamConfig + TeamsLoader — read teams.json
2. TeamSectionView + RoleCardView — replace flat agent list
3. Match existing sessions to teams/roles by cwd
4. Collapsible sections in PopoverView
5. Team-level aggregate stats

### Phase 2 — Spawn
1. TeamSpawner — AppleScript to open Terminal windows with claude
2. Spawn button per team and per vacant role
3. Track spawned sessions by PID/TTY
4. Window title setting via AppleScript

### Phase 3 — WebSocket Control Plane
1. WSServer with SwiftNIO WebSocket
2. SessionRegistry — connect/disconnect/role mapping
3. WSProtocol — typed messages
4. Claude Code hook for auto-connect
5. Command dispatch UI (send task to specific agent)

### Phase 4 — MCP Hub
1. MCPServerManager — read .claude.json, launch servers once
2. MCPProxy — stdio pipe management with NIO
3. MCPRouter — multiplex tool calls from N sessions to shared servers
4. Proxy client script for session config
5. Migration guide for .claude.json

### Phase 5 — Notifications + Polish
1. NotificationManager — UNUserNotificationCenter
2. EventDetector — pattern matching on JSONL
3. Click-to-focus from notification
4. UI animations, team health aggregation

---

## 8. Non-Goals (v3)

- Multi-terminal support (iTerm2, Warp, Ghostty) — Terminal.app only
- Persistent state across restarts — fresh scan every launch
- More than 3 roles per team — fixed at PM + Dev + 1 custom
- Auto-generated role prompts — user defines in teams.json
- Remote/cloud orchestration — local only
- Windows/Linux — macOS only (SwiftUI + AppleScript)

---

## 9. Open Source

- **Repo**: github.com/astra-digital/inkpulse
- **License**: Apache 2.0
- **README**: screenshots, GIF demo, quick start
- **Config**: teams.json generic, no hardcoded pillars
- **Example**: ships with example teams.json for typical multi-project setup
- **Business**: OSS free -> AstraAI enterprise custom

---

## 10. Success Criteria

- [ ] 4 teams visible in popover with collapsible sections
- [ ] One-click spawn opens 3 Terminal windows with claude running
- [ ] WebSocket connects sessions to InkPulse bidirectionally
- [ ] MCP proxy reduces process count from N*M to M+1
- [ ] macOS notification on deploy/error/task completion
- [ ] README + Apache 2.0 + published on GitHub
- [ ] Power user can manage 12+ agents across 4+ teams without cognitive overload

---

*Spec: sess.524, 26 Mar 2026*
*Mattia Calastri + Claude — Astra Digital*

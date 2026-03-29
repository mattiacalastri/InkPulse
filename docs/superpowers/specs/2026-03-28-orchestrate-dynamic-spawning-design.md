# InkPulse Orchestrate — Dynamic Agent Spawning

> Design spec for the Orchestrate feature: a single button that spawns an autonomous orchestrator
> agent which reads the Obsidian vault and decides what 6 sub-agents should work on.

## Problem

The current system uses `teams.json` with predefined teams and static prompts. Agents always spawn
with the same roles regardless of what actually needs doing. The orchestrator should decide dynamically
based on current state — vault, roadmap, backlog, git, session history.

## Design Decision

**Approach A (Sequential)** — approved. InkPulse spawns the orchestrator agent, the orchestrator
reads whatever it needs autonomously, writes `~/.inkpulse/missions.json`, InkPulse watches the file
and spawns 6 agents with dynamic prompts. Coexists with existing teams.json (Approach B for coexistence).

## Flow

```
User clicks "Orchestrate" button in LiveTab header
  → InkPulse spawns 1 Terminal window: orchestrator agent
  → Orchestrator has full autonomy: reads vault, memory, git, roadmap, quaderno, anything
  → Orchestrator writes ~/.inkpulse/missions.json with 6 missions
  → InkPulse MissionsWatcher detects file change (FSEvents)
  → InkPulse spawns 6 Terminal windows with dynamic prompts from missions.json
  → UI shows "Orchestrate" team section with orchestrator + 6 agent cards
  → Orchestrator stays active as 7th agent (supervisor, cross-domain connector)
```

## missions.json Schema

```json
{
  "generated": "2026-03-28T14:30:00Z",
  "reasoning": "Brief explanation of why these 6 missions were chosen",
  "missions": [
    {
      "id": "m1",
      "name": "Human-readable mission name",
      "cwd": "~/projects/aurahome",
      "icon": "flame.fill",
      "color": "#FFD700",
      "prompt": "Full dynamic prompt for the agent..."
    }
  ]
}
```

Fields:
- `generated`: ISO 8601 timestamp
- `reasoning`: orchestrator's rationale (shown in UI tooltip)
- `missions`: exactly 6 entries
- Each mission: `id` (m1-m6), `name`, `cwd` (tilde-expanded by InkPulse), `icon` (SF Symbol),
  `color` (hex, optional — defaults to team color), `prompt` (complete startup prompt)

## Components

### New Files

#### `Sources/Actions/OrchestrateSpawner.swift`
- `OrchestrateSpawner.orchestrate()` — spawns orchestrator Terminal window
- Orchestrator meta-prompt: tells it to read autonomously, write missions.json in the exact schema
- After missions.json is detected: calls `TeamSpawner.spawnRole()` for each mission
- Reuses existing AppleScript spawn mechanism from `TeamSpawner`

#### `Sources/Watcher/MissionsWatcher.swift`
- FSEvents watcher on `~/.inkpulse/missions.json`
- Debounce: 1s after last write (orchestrator may write incrementally)
- Decodes `MissionsFile`, validates 6 missions, notifies callback
- Cleans up: deletes missions.json after successful spawn (prevents stale re-reads)

### Modified Files

#### `Sources/Config/TeamConfig.swift`
New structs:
```swift
struct MissionConfig: Codable, Identifiable {
    let id: String
    let name: String
    let cwd: String
    let icon: String
    let color: String?
    let prompt: String
}

struct MissionsFile: Codable {
    let generated: String
    let reasoning: String
    let missions: [MissionConfig]
}

enum OrchestratePhase {
    case idle
    case thinking    // orchestrator spawned, waiting for missions.json
    case spawning(Int, Int)  // (completed, total)
    case active      // all 7 agents running
    case failed(String)
}
```

#### `Sources/App/AppState.swift`
- New `@Published var orchestratePhase: OrchestratePhase = .idle`
- New `@Published var orchestrateTeamState: TeamState?` — dynamic team from missions
- New `private var missionsWatcher: MissionsWatcher?`
- New `func orchestrate()`:
  1. Set phase to `.thinking`
  2. Start MissionsWatcher
  3. Call `OrchestrateSpawner.spawnOrchestrator()`
  4. On missions received: set phase `.spawning(0, 6)`, spawn agents sequentially, update count
  5. On all spawned: set phase `.active`, build `TeamState` from missions
  6. Timeout: 120s → phase `.failed("Orchestrator did not produce missions")`
- `refreshTeamStates()` includes `orchestrateTeamState` in `teamStates` array when active

#### `Sources/UI/LiveTab.swift`
- New `orchestrateButton` in header, between title and health score
- Visual states: idle (teal "Orchestrate" with brain icon), thinking (pulsing), spawning (progress),
  active (green checkmark with agent count), failed (red with retry)
- When `.active`: the orchestrate team appears as first team in `teamAgentsContent`

### Unchanged
- `TeamSpawner.swift` — reused as-is for spawning individual missions
- `TerminalOpener.swift` — unchanged
- `TeamSectionView.swift` — reused for displaying orchestrate team (it's just a TeamState)
- `teams.json` — untouched, coexists
- All metrics, ECG, health, WebSocket, heartbeat — unchanged

## Orchestrator Meta-Prompt

The orchestrator receives a prompt that:
1. Declares identity: "Sei il Polpo — il cervello centrale"
2. Grants full autonomy: read anything (vault, memory, git, files)
3. Specifies the output contract: write `~/.inkpulse/missions.json` in exact schema
4. Specifies constraint: exactly 6 missions
5. Tells it to stay active after writing missions (supervisor role)
6. Includes the JSON schema inline so it doesn't need to guess

The prompt does NOT prescribe what to read or what missions to create. Maximum autonomy.

## UI States

| Phase | Button | Team Section |
|-------|--------|-------------|
| idle | "Orchestrate" teal, brain icon | Not shown |
| thinking | Pulsing animation, "Thinking..." | Orchestrator card only (1 slot) |
| spawning | Progress "Spawning 3/6..." | Orchestrator + filling cards |
| active | Green check, "7 Active" | Full team: orchestrator + 6 missions |
| failed | Red, "Retry" | Error message |

## Edge Cases

- **missions.json already exists on click**: delete it first, then spawn orchestrator
- **Orchestrator writes < 6 missions**: spawn what's there, show warning badge
- **Orchestrator writes > 6 missions**: take first 6, ignore rest
- **User clicks Orchestrate while active**: confirm dialog "Replace current orchestration?"
- **Individual team spawn during orchestration**: works independently, no conflict
- **Orchestrator crashes before writing**: 120s timeout → failed state with retry

## Testing

- Unit: MissionsFile decoding (valid, partial, malformed)
- Unit: OrchestratePhase transitions
- Integration: file watcher detects missions.json write
- Manual: full flow — click → orchestrator thinks → 6 agents spawn

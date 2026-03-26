# InkPulse: Project Inference from Tool Paths

> Date: 2026-03-26 | Session: ~511 | Status: SPEC

## Problem

When Claude Code is launched from `~/` (Home), all sessions show "Home" as the project name in agent cards. But the tool_use events contain full file paths that reveal the actual project context (e.g., `luxguard_lightbox.png`, `footgolf_page_19029_updated.html`). Today, `extractToolTarget()` truncates paths to just the filename, discarding the project-identifying directory information.

## Design

### Data Flow

```
assistant event → tool_use content block → input.file_path
                                              ↓
                              ToolUseInfo.fullPath (NEW — raw path, not truncated)
                                              ↓
                              SessionMetrics.recentToolPaths (ring buffer, max 30)
                                              ↓
                              SessionMetrics.inferredProject (computed)
                                              ↓
                              MetricsSnapshot.inferredProject: String?
                                              ↓
                              PillarInfo.from(cwd:, inferredProject:)
                                              ↓
                              AgentCardView shows "LuxGuard" instead of "Home"
```

### Inference Algorithm

Given collected full paths like:
```
/Users/mattiacalastri/Downloads/⚡ Astra Digital Marketing/clients/luxguard/lightbox.png
/Users/mattiacalastri/Downloads/⚡ Astra Digital Marketing/clients/luxguard/style.css
/Users/mattiacalastri/projects/footgolfpark/pages/index.html
```

1. Strip home directory prefix (`/Users/mattiacalastri/`)
2. Skip known container directories: `Downloads`, `projects`, `Documents`, `Desktop`, `.claude`
3. Take the next path component as the "project root candidate"
4. Special case: if candidate is a known multi-level container (e.g., `⚡ Astra Digital Marketing/clients/`), go one level deeper
5. Count frequency of each candidate across all collected paths
6. Winner = most frequent candidate
7. Smart capitalize: `luxguard` → `LuxGuard`, `footgolfpark` → `Footgolfpark`

**Edge cases:**
- All paths are in `~/` directly (e.g., `~/.zshrc`) → no inference, keep "Home"
- Mixed paths from multiple projects → winner takes all (most frequent)
- No tool_use with file_path → no inference, keep current behavior
- Paths under known pillars (`btc_predictions`, `claude_voice`, etc.) → PillarInfo already handles these via cwd; inference only matters when cwd is Home

### Files to Modify

| File | Change |
|------|--------|
| `ClaudeEvent.swift` | Add `fullPath: String?` to `ToolUseInfo` |
| `JSONLParser.swift` | Extract raw `file_path` before truncation, pass as `fullPath` |
| `SessionMetrics.swift` | Add `recentToolPaths: [String]` (ring buffer 30), add `inferredProject` computed property |
| `MetricsEngine.swift` | Pass `inferredProject` through to `MetricsSnapshot` (check if snapshot is built there or in SessionMetrics) |
| `SessionRowView.swift` | Update `PillarInfo.from()` to accept and use `inferredProject` parameter |
| `AgentCardView.swift` | Pass `inferredProject` from snapshot to `PillarInfo.from()` |
| `PopoverView.swift` | Pass `inferredProject` from snapshot to card views |
| `DashboardStats.swift` | Check if pillar info needs the new parameter |
| `Tests/` | Add `PillarTests` for inference logic |

### Smart Capitalize

```swift
func smartCapitalize(_ name: String) -> String {
    // "luxguard" → "LuxGuard" (camelCase-ish split)
    // "footgolfpark" → "Footgolfpark" (single word, just capitalize first)
    // "my-project" → "My Project" (hyphen split)
    // "⚡ Astra Digital Marketing" → keep as-is (already capitalized)
    if name.first?.isUppercase == true { return name }
    if name.contains("-") {
        return name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
    return name.prefix(1).uppercased() + name.dropFirst()
}
```

### Container Directories

Directories that are structural containers, not project names:

```swift
private static let containerDirs: Set<String> = [
    "Downloads", "projects", "Documents", "Desktop",
    "Library", ".claude", "Applications", "tmp",
    "clients"  // inside Astra Digital Marketing
]
```

When we hit a container dir, we skip it and take the next component.

### Constraints

1. **Ring buffer max 30** — no unbounded growth
2. **Only `file_path` keys** — don't parse project names from command strings (too unreliable)
3. **Inference is display-only** — never affects cwd, offsets, or persistence
4. **No new files** — all changes go in existing files
5. **Backward compatible** — if no paths collected, behavior is identical to today

### Test Plan

- [ ] Session with cwd=Home, tool paths in `~/projects/footgolfpark/` → inferred "Footgolfpark"
- [ ] Session with cwd=Home, tool paths in `~/Downloads/⚡ Astra Digital Marketing/clients/luxguard/` → inferred "LuxGuard" (skips containers)
- [ ] Session with cwd=Home, no file_path tool_use events → stays "Home"
- [ ] Session with cwd=`~/btc_predictions/` → PillarInfo uses cwd as before, inference not used
- [ ] Mixed paths: 15 luxguard + 5 other → "LuxGuard" wins
- [ ] Paths only in `~/` root (e.g., `~/.zshrc`) → stays "Home"
- [ ] Ring buffer caps at 30, oldest entries dropped

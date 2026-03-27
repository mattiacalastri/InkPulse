# InkPulse Phase 4 — MCP Hub Design

> Session 539 | 27 Mar 2026 | Mattia Calastri + Claude

## Problem

N Claude Code sessions x M stdio MCP servers = N*M duplicated processes. With 8 sessions and ~15 stdio servers, that's ~120 processes doing identical work. The MCP Hub launches each stdio server once and multiplexes tool calls from all sessions through a single HTTP endpoint.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Session-facing transport | HTTP endpoint on :9997 | No extra binaries, simple .claude.json config |
| Which servers to proxy | stdio only | HTTP servers (supabase, stripe, github) are already shared endpoints |
| Crash behavior | Tools lost, restart recovers | Menubar app runs 24/7, restart takes 2s. Complexity of detached pools not justified |
| Config migration | Auto-rewrite .claude.json with backup/restore | Zero friction. Safety net via backup file + signal handlers |

## Architecture

```
Claude Code Session 1 --HTTP POST--+
Claude Code Session 2 --HTTP POST--+
Claude Code Session N --HTTP POST--+--> MCPHub (:9997)
                                   |      |
                                   |      v
                                   |   MCPRouter
                                   |   (tool_name -> server_id)
                                   |      |
                                   |      +--stdio--> n8n server
                                   |      +--stdio--> telegram server
                                   |      +--stdio--> railway server
                                   |      +--stdio--> fal server
                                   |      +--stdio--> wordpress x5
                                   |      +--stdio--> obsidian, etc.
                                   |
ConfigMigrator
  startup: backup .claude.json, rewrite -> point to :9997
  quit:    restore backup
```

## Components

### MCPServerManager.swift (~200 lines)

Reads `~/.claude.json.inkpulse-backup`, filters servers where `type == "stdio"`. For each:

- Launches `Process()` with command + args + env from config
- Captures stdin (Pipe for writing) and stdout (Pipe for reading)
- Monitors process lifecycle, restarts on crash (max 3 retries, backoff 1s/2s/4s)
- Exposes: `servers: [String: MCPServerProcess]` keyed by server name

```swift
struct MCPServerProcess {
    let name: String
    let process: Process
    let stdin: FileHandle   // write requests here
    let stdout: FileHandle  // read responses here
    var isHealthy: Bool
    var toolNames: [String] // populated after tools/list
}
```

### MCPRouter.swift (~150 lines)

After all servers are launched, sends `initialize` + `tools/list` to each via stdin/stdout. Builds routing table.

- `routingTable: [String: String]` — tool name -> server name
- `serverQueues: [String: DispatchQueue]` — one serial queue per server (stdio is single-threaded)
- On `tools/call`: look up tool name -> server name -> enqueue on server's queue -> write to stdin -> read from stdout
- ID remapping: incoming JSON-RPC id from session -> internal auto-increment id for backend -> remap response back to original id
- Tool name collision: first server wins, warning logged, collisions visible in UI

```swift
func route(toolName: String, arguments: [String: Any], sessionRequestId: JSONRPCId) async throws -> JSONRPCResponse
```

### MCPHub.swift (~180 lines)

HTTP server using Network.framework (same pattern as WSServer). Listens on :9997 (fallback :9996, :9995 if occupied).

Single endpoint: `POST /mcp`

Handles MCP JSON-RPC methods:
- `initialize` -> responds with aggregated capabilities from all servers
- `notifications/initialized` -> ack
- `tools/list` -> responds with union of all tools from all servers
- `tools/call` -> delegates to MCPRouter, returns response

No SSE needed — all interactions are synchronous request/response over HTTP POST.

HTTP parsing: read Content-Length header, read body, parse JSON-RPC, dispatch, write response with Content-Type: application/json.

### ConfigMigrator.swift (~120 lines)

**Startup sequence:**
1. Check if `~/.claude.json.inkpulse-backup` exists -> if yes, previous crash: restore first
2. Copy `~/.claude.json` -> `~/.claude.json.inkpulse-backup`
3. Read backup, parse mcpServers
4. Rewrite `.claude.json`: remove all stdio servers, add:
   ```json
   "inkpulse-hub": {
     "type": "http",
     "url": "http://localhost:9997/mcp"
   }
   ```
5. HTTP servers (supabase, stripe, github) left untouched

**Quit (normal):** restore `.claude.json` from backup, delete backup file.

**Crash (signal handler):** register `SIGTERM`, `SIGINT`, `SIGHUP` -> restore + exit.

**Unrecoverable crash:** backup survives. Next startup detects it (step 1) and restores.

**Toggle off from UI:** restore .claude.json, kill all server processes, stop :9997.

## Protocol Details

### Backend (InkPulse -> stdio servers)

JSON-RPC 2.0, one message per line on stdin/stdout:

```json
// Initialize
-> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"InkPulse","version":"2.1.0"}}}
<- {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}}}

// Tool list
-> {"jsonrpc":"2.0","id":2,"method":"tools/list"}
<- {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"SEND_MESSAGE","description":"...","inputSchema":{...}}]}}

// Tool call (forwarded from session)
-> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"SEND_MESSAGE","arguments":{...}}}
<- {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Message sent"}]}}
```

### Frontend (sessions -> InkPulse HTTP)

Same JSON-RPC 2.0 over HTTP POST:

```
POST /mcp HTTP/1.1
Content-Type: application/json

{"jsonrpc":"2.0","id":1,"method":"tools/list"}
```

Response:
```
HTTP/1.1 200 OK
Content-Type: application/json

{"jsonrpc":"2.0","id":1,"result":{"tools":[...all tools from all servers...]}}
```

### ID Remapping

Sessions send their own JSON-RPC ids. MCPRouter maintains:
- `pendingRequests: [Int: (serverName: String, originalId: JSONRPCId, continuation: CheckedContinuation)]`
- Internal auto-increment counter for backend ids
- On response from backend: look up internal id -> find original session id -> remap and return

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Server stdio crashes | MCPServerManager restarts (max 3 retries, backoff 1s/2s/4s). Queued tool calls get error |
| Server fails to start | Log warning, excluded from routing table. Others work fine |
| Tool call to dead server | JSON-RPC error -32603 to session. Claude Code handles retry |
| Port :9997 occupied | Fallback :9996, :9995. Logged in ConfigView |
| .claude.json locked/readonly | Skip migration, log warning. Hub works but sessions need manual config |
| Tool name collision | First server wins + warning log + collisions visible in ConfigView |
| Server timeout (30s) | Error to session, server marked unhealthy in UI |

## UI Changes

### ConfigView — new "MCP Hub" section
- Toggle on/off (enables/disables the proxy)
- Status line: "Running — 12 servers, 147 tools" or "Off"
- Server list with health indicator (green/red dot)
- Collision warnings if any

### PopoverView — footer stats
- Add "MCP: 12/12" next to existing stats (tok/min, cost, cache)

### LiveTab — hub badge
- Brief flash when a tool call routes through the hub

## File Plan

```
NEW:
  Sources/MCP/MCPServerManager.swift    ~200 lines
  Sources/MCP/MCPRouter.swift           ~150 lines
  Sources/MCP/MCPHub.swift              ~180 lines
  Sources/MCP/ConfigMigrator.swift      ~120 lines

MODIFIED:
  Sources/App/AppState.swift            init/shutdown hub, expose state
  Sources/UI/ConfigView.swift           MCP Hub section
  Sources/UI/PopoverView.swift          "MCP: 12/12" footer stat
  Sources/UI/LiveTab.swift              hub active badge
```

Estimated: ~650 lines new Swift, ~40 lines modifications. Zero external dependencies.

## Non-Goals (Phase 4)

- Proxying HTTP MCP servers (already shared endpoints)
- Persistent server pool across InkPulse restarts (Process children die with parent)
- Per-session MCP config (all sessions get all stdio tools)
- Tool call caching or deduplication
- Rate limiting or quota management per server

## Success Criteria

- [ ] All stdio MCP servers from .claude.json launch once inside InkPulse
- [ ] N sessions share M server processes (not N*M)
- [ ] Tool calls route correctly through HTTP -> router -> stdio -> response
- [ ] .claude.json auto-migrated on startup, restored on quit/crash
- [ ] ConfigView shows hub status, server list, toggle
- [ ] Process count drops from ~120 to ~15 with 8 active sessions
- [ ] Zero external dependencies added to Package.swift

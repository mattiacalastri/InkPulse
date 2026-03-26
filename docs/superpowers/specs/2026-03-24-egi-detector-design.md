# EGI Detector — InkPulse Design Spec

**Date:** 2026-03-24
**Author:** Mattia Calastri + Claude (sess.458)
**Status:** Approved

---

## Summary

Add an EGI (Emergent General Intelligence) window detector to InkPulse. EGI windows are transient states where a Claude Code session exhibits cross-domain coherence, sustained flow, and focused intelligence — as defined in the EGI paper (Calastri, 2026).

The detector uses existing session metrics plus new tool diversity tracking to identify when a session enters an EGI window. The UI renders a **living glyph** — not a number — that breathes and pulses to communicate the window state.

## Architecture

### 1. Data Layer — Tool Name Tracking

**ClaudeEvent** changes:
- Add `toolName: String?` to the `.progress` case

**JSONLParser** changes:
- In `parseAssistant()`: extract `tool_use` content blocks into a session-scoped map `[toolUseID: String → toolName: String]`
- Store this map as a static/class-level dictionary keyed by sessionId
- In `parseProgress()`: look up `toolUseID` in the map to resolve `toolName`

**SessionMetrics** new accumulators:
- `toolNameEvents: [(date: Date, name: String)]` — timestamped tool usage with names
- Computed: `toolDiversity(in window: TimeInterval) -> Int` — count of distinct tool names
- Computed: `domainSpread(in window: TimeInterval) -> Int` — count of distinct domains

**Domain mapping** (tool name prefix → domain):
- `code`: Read, Edit, Write, Grep, Glob, Bash, LSP
- `knowledge`: mcp__obsidian__, mcp__notion__, mcp__plugin_context7__
- `communication`: mcp__claude_ai_Gmail__, mcp__telegram__, mcp__linkedin__, mcp__x__
- `infrastructure`: mcp__railway__, mcp__hostinger__, mcp__github__
- `creation`: mcp__fal__, mcp__cloudinary__, mcp__claude_ai_Canva__
- `business`: mcp__stripe__, mcp__ghl__, mcp__n8n__, mcp__wordpress__

### 2. EGI Score Engine — State Machine

New file: `Sources/Metrics/EGIScore.swift`

**States:** `dormant`, `stirring`, `open`, `peak`

**Signals** (7 total, each Boolean pass/fail):

| Signal | Metric | Threshold |
|--------|--------|-----------|
| velocity | tok/min avg over 120s | > 300 |
| accuracy | errorRate in window | < 0.03 |
| context | cacheHit | > 0.70 |
| diversity | distinct tools in 60s | >= 4 |
| crossDomain | distinct domains in 120s | >= 2 |
| flow | idleAvgS | < 10s |
| balance | thinkOutputRatio | 0.3 - 4.0 |

**Transitions:**
- `dormant → stirring`: >= 4/7 signals for >= 15s
- `stirring → open`: >= 6/7 signals for >= 30s
- `open → peak`: 7/7 signals for >= 60s AND domainSpread >= 3
- Decay: drop one level at a time after < 3/7 signals for >= 20s (hysteresis)

**Internal confidence:** Double 0.0-1.0, weighted average of normalized signals. Not shown in main UI — available in expanded card detail and reports.

**Integration with MetricsSnapshot:**
- Add `egiState: String` (dormant/stirring/open/peak)
- Add `egiConfidence: Double`

**EGITracker** (per-session, lives in SessionMetrics):
- Stores current state + timestamp of last transition
- `evaluate(snapshot:) -> (state: EGIState, confidence: Double)`
- Hysteresis buffer: tracks how long current signal count has held

### 3. UI — The Living Glyph

New file: `Sources/UI/EGIGlyphView.swift`

**Glyph states:**

| State | Symbol | Color | Animation |
|-------|--------|-------|-----------|
| dormant | ◯ | gray 30% | none |
| stirring | ◎ | teal 50% | slow fade in/out (3s cycle) |
| open | ◉ | teal 100% | breathing glow (2s cycle) |
| peak | ✦ | gold #FFD700 | pulsing glow + subtle scale (1.5s cycle) |

**Implementation:** SwiftUI with `.animation(.easeInOut)` on opacity/scale modifiers, driven by a `Timer` that toggles a `@State var glowPhase: Bool`.

**Header glyph (global):**
- Lives next to the HEALTH score in LiveTab header and PopoverView header
- Shows the highest EGI state across all active sessions
- Size: 20pt in popover, 32pt in LiveTab

**Card glyph (per-session):**
- Replaces/augments the emoji mood in SessionRowView when EGI state > dormant
- When dormant: show normal mood emoji (no change)
- When stirring/open/peak: show EGI glyph instead of mood emoji
- Expanded card shows: EGI state label + confidence percentage

### 4. Aggregation

**MetricsEngine** changes:
- New computed: `globalEGIState: EGIState` — highest state across all active sessions
- New computed: `egiSessionCount: Int` — how many sessions have state > dormant

**PopoverView / LiveTab header:**
- Show global glyph + optional count ("2 windows" if multiple sessions in open/peak)

### 5. Files to Create/Modify

**Create:**
- `Sources/Metrics/EGIScore.swift` — state machine, tracker, domain mapping
- `Sources/UI/EGIGlyphView.swift` — animated glyph view

**Modify:**
- `Sources/Parser/ClaudeEvent.swift` — add toolName to progress
- `Sources/Parser/JSONLParser.swift` — extract tool names, maintain map
- `Sources/Metrics/SessionMetrics.swift` — tool name tracking, diversity/spread, EGI tracker
- `Sources/Metrics/MetricsEngine.swift` — add EGI fields to snapshot, global aggregation
- `Sources/UI/SessionRowView.swift` — integrate glyph in card
- `Sources/UI/LiveTab.swift` — global glyph in header
- `Sources/UI/PopoverView.swift` — global glyph in header

## Non-Goals

- No persistence of EGI history (future work — correlate with session outcomes)
- No notification on EGI window open (could add later)
- No external API/webhook (future)
- The confidence score is internal — the glyph is the interface

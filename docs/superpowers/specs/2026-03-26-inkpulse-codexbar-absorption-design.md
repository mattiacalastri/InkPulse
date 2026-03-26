# InkPulse v2.0 — CodexBar Absorption + App Store Freemium

> Date: 2026-03-26 | Session: 516 | Status: SPEC
> Goal: One menu bar item. Uninstall CodexBar. Ship to App Store.

## Vision

InkPulse becomes the **only** macOS menu bar app a Claude Code user needs.
CodexBar tells you cost. InkPulse tells you rhythm. Combined: **everything**.

Business model: **Free forever** (full monitoring) + **Pro Lifetime €79** (quota, CLI, export, widget).

---

## Phase 1 — CodexBar Killer (immediate)

### 1.1 Accurate Pricing Table

**Problem**: Current `Pricing.swift` has wrong prices and no tiered pricing.

**Fix** (from CodexBar's `CostUsagePricing.swift`):

| Model | Input/1M | Output/1M | Cache Read/1M | Cache Create/1M |
|-------|----------|-----------|---------------|-----------------|
| haiku-4.5 | $1.00 | $5.00 | $0.10 | $1.25 |
| sonnet-4.5/4.6 | $3.00 | $15.00 | $0.30 | $3.75 |
| sonnet (>200K ctx) | $6.00 | $22.50 | $0.60 | $7.50 |
| opus-4.5/4.6 | $5.00 | $25.00 | $0.50 | $6.25 |

**Key change**: Sonnet doubles price above 200K token threshold. `costEUR()` must check `lastContextTokens` and use tiered rate.

**Implementation**:
- Replace `ModelPricing` with `ModelPricing(input:, output:, cacheRead:, cacheCreate:, tieredInput:, tieredOutput:, tieredCacheRead:, tieredCacheCreate:, tierThreshold:)`
- Or simpler: add a `tieredModels` dict with separate pricing for >200K
- `costEUR()` gets new param `contextTokens: Int` to select tier

**Files**: `Pricing.swift` only. ~30 lines changed.

### 1.2 OAuth Quota Fetcher

**Problem**: InkPulse calculates cost locally but doesn't know actual Anthropic quota/limits.

**Solution**: Call Anthropic's undocumented OAuth usage endpoint (same as CodexBar).

**Endpoint**: `GET https://api.anthropic.com/api/oauth/usage`
**Headers**:
- `Authorization: Bearer <token>`
- `anthropic-beta: oauth-2025-04-20`
- `User-Agent: claude-code/1.0.0`

**Token source** (in order):
1. `~/.claude/.credentials.json` → parse JSON → `accessToken` field
2. Keychain `Claude Code-credentials`

**Response** (relevant fields):
```json
{
  "five_hour": { "limit": 100, "remaining": 45, "resets_at": "..." },
  "seven_day": { "limit": 500, "remaining": 230 },
  "seven_day_opus": { "limit": 200, "remaining": 120 },
  "seven_day_sonnet": { "limit": 300, "remaining": 110 },
  "extra_usage": { "enabled": false }
}
```

**Display in UI**:
- Header stats strip: new column `quota` showing `45%` (five_hour remaining/limit)
- Color: green >50%, orange 20-50%, red <20%
- Tooltip on hover: "5h: 45/100 remaining | 7d: 230/500"

**Refresh cadence**: Every 5 minutes (same as CodexBar default). Not per-second — it's an API call.

**Error handling**: If token not found or API fails → hide quota column, no crash. Degrade gracefully.

**New file**: `Sources/Quota/QuotaFetcher.swift`
**Modified**: `AppState.swift` (trigger refresh), `PopoverView.swift` + `LiveTab.swift` (display), `DashboardStats.swift` (aggregate)

### 1.3 Incremental JSONL Scan

**Problem**: At boot, InkPulse re-reads last 500KB of every active JSONL. Wasteful when files haven't changed.

**Solution** (from CodexBar pattern): Before tailing, check `mtime + size`. If unchanged since last run, skip. If file grew, resume from last offset. If file shrank/changed, rescan.

**Implementation**:
- Extend `OffsetEntry` with `mtime: Date?` and `fileSize: UInt64?`
- In `SessionWatcher.scanForActiveJSONL()`: compare stored mtime/size before creating new tailer
- Persist in existing `offsets.json`

**Files**: `OffsetEntry.swift`, `OffsetCheckpoint.swift`, `SessionWatcher.swift`. ~40 lines.

---

## Phase 2 — App Store + Freemium (next sprint)

### 2.1 App Store Packaging

**Requirements**:
- Xcode project (currently Swift Package only) — need `.xcodeproj` or convert to Xcode workspace
- App Sandbox entitlements (required for App Store)
- Hardened Runtime + notarization
- App icon properly registered in asset catalog
- macOS 14.0+ deployment target (already correct)

**Sandbox considerations**:
- File access: needs `com.apple.security.files.user-selected.read-only` for `~/.claude/projects/`
- Actually: `~/.claude/` is outside sandbox. Options:
  - (A) Ship outside App Store (DMG/Homebrew) — no sandbox issues
  - (B) App Store with bookmark/security-scoped URL — user grants access once
  - (C) App Store + helper tool outside sandbox
- **Recommendation**: Ship BOTH — App Store (sandboxed, user grants folder access on first launch) + Homebrew cask (unsandboxed, power users). Same binary, different packaging.

### 2.2 Freemium Gate

**Free tier** (everything current):
- Multi-session monitoring (unlimited)
- Health score + anomalies + EGI
- Agent cards with project inference
- ECG sparkline
- Local cost tracking
- Trends/Reports
- Notifications + sound
- Config panel

**Pro tier** (€79 lifetime):
- OAuth quota (real Anthropic limits/usage)
- CLI `inkpulse status/cost/health --json`
- Data export (CSV/JSON heartbeat history)
- macOS Widget (WidgetKit)
- Custom themes (beyond teal)
- Priority future features

**Gate mechanism**:
- StoreKit 2 (native Swift, no server needed)
- Non-consumable in-app purchase: `com.inkpulse.pro.lifetime`
- Store purchase state in `UserDefaults` + receipt validation
- Pro features check: `ProGate.isUnlocked` static bool
- Graceful: Pro features show lock icon in free tier, tap shows upgrade sheet

### 2.3 CLI Target

**New SPM target**: `InkPulseCLI` (executable)
- Shares: `JSONLParser`, `SessionMetrics`, `MetricsEngine`, `HealthScore`, `Pricing`, `SessionWatcher`
- Does NOT share: UI files, AppKit, SwiftUI
- Commands: `inkpulse status [--json]`, `inkpulse cost [--today|--week]`, `inkpulse health`
- Install: symlink from app bundle or separate Homebrew formula

### 2.4 WidgetKit Extension

**Widget types** (inspired by CodexBar):
- **Compact**: Health score + cost today
- **Standard**: Health + cost + active agents count
- **Large**: Mini agent cards (top 3 by activity)

Timeline refresh: every 15 minutes. Data from shared `WidgetSnapshotStore` (same pattern as CodexBar).

---

## File Plan

### Phase 1 (new files)
| File | Purpose |
|------|---------|
| `Sources/Quota/QuotaFetcher.swift` | OAuth endpoint call + token resolution |
| `Sources/Quota/QuotaSnapshot.swift` | Response model (five_hour, seven_day, etc.) |

### Phase 1 (modified files)
| File | Change |
|------|--------|
| `Pricing.swift` | Correct prices + tiered Sonnet >200K |
| `SessionMetrics.swift` | Pass contextTokens to costEUR |
| `OffsetEntry.swift` | Add mtime + fileSize fields |
| `SessionWatcher.swift` | mtime/size check before tailing |
| `AppState.swift` | QuotaFetcher lifecycle + timer |
| `PopoverView.swift` | Quota display in header |
| `LiveTab.swift` | Quota display in header |
| `DashboardStats.swift` | Quota aggregate |
| `ConfigView.swift` | OAuth token status indicator |

### Phase 2 (new files/targets)
| Item | Purpose |
|------|---------|
| `InkPulse.xcodeproj` | Xcode project for App Store |
| `Sources/Pro/ProGate.swift` | StoreKit 2 purchase + gate |
| `Sources/Pro/UpgradeSheet.swift` | SwiftUI upgrade UI |
| `InkPulseCLI/` | CLI target |
| `InkPulseWidget/` | WidgetKit extension |

---

## Constraints

1. **Zero new dependencies** — no SPM packages added. URLSession for HTTP, Security framework for Keychain
2. **Graceful degradation** — if OAuth fails, everything else works. Free tier is fully functional
3. **No credential storage** — read Claude Code's existing token, never store our own copy
4. **Privacy-first** — no analytics, no telemetry, no network calls except OAuth (opt-in Pro)
5. **Phase 1 ships today** — pricing fix + OAuth + incremental scan. Phase 2 is next sprint

---

## Test Plan

### Phase 1
- [ ] Cost calculation matches CodexBar for same session (within 5% tolerance)
- [ ] Sonnet tiered pricing activates above 200K context
- [ ] QuotaFetcher reads token from `~/.claude/.credentials.json`
- [ ] Quota display shows correct percentages
- [ ] QuotaFetcher gracefully returns nil when no token found
- [ ] Incremental scan skips unchanged files (verify with log)
- [ ] Boot time improves with 10+ JSONL files present

### Phase 2
- [ ] App Store build passes validation
- [ ] StoreKit 2 purchase flow works in sandbox
- [ ] Pro features locked in free tier with lock icon
- [ ] CLI output matches app metrics
- [ ] Widget displays correct data from shared store

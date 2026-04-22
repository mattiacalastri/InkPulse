#!/usr/bin/env bash
# InkPulse Hook Installer
# ─────────────────────────────────────────────────────────────────────────────
# Installs the InkPulse WebSocket client as a Claude Code hook so every
# session auto-registers with InkPulse.
#
# Usage:
#   ./scripts/install_hook.sh
#
# What it does:
#   1. Copies ws_client.sh to ~/.inkpulse/hooks/
#   2. Patches ~/.claude/settings.json to add SessionStart + PreToolUse hooks
#   3. Creates ~/.inkpulse/teams.json from example if missing
#
# Safe to re-run — idempotent. Existing hooks are preserved.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.inkpulse/hooks"
HOOK_SRC="$SCRIPT_DIR/ws_client.sh"
HOOK_DEST="$HOOKS_DIR/inkpulse_ws_client.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
TEAMS_FILE="$HOME/.inkpulse/teams.json"
EXAMPLE_TEAMS="$SCRIPT_DIR/../Resources/example-teams.json"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}InkPulse Hook Installer${NC}"
echo "─────────────────────────────────────────"

# ── 1. Install hook script ────────────────────────────────────────────────────

mkdir -p "$HOOKS_DIR"
cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo -e "${GREEN}✓${NC} Hook installed: $HOOK_DEST"

# ── 2. Patch ~/.claude/settings.json ─────────────────────────────────────────

mkdir -p "$(dirname "$SETTINGS_FILE")"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{}' > "$SETTINGS_FILE"
    echo -e "${GREEN}✓${NC} Created settings.json"
fi

# Use Python to safely merge hook entries (no jq dependency)
python3 - "$SETTINGS_FILE" "$HOOK_DEST" <<'PYEOF'
import sys, json, os

settings_path = sys.argv[1]
hook_path = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# ── SessionStart ──────────────────────────────────────────────────────────────
session_start = hooks.setdefault("SessionStart", [])

start_cmd = {
    "type": "command",
    "command": f'bash "{hook_path}" SessionStart'
}

already_has = any(
    e.get("command", "").endswith("inkpulse_ws_client.sh SessionStart")
    for e in session_start
    if isinstance(e, dict)
)

if not already_has:
    session_start.append(start_cmd)
    print(f"  + Added SessionStart hook")
else:
    print(f"  = SessionStart hook already present")

# ── PreToolUse ────────────────────────────────────────────────────────────────
pre_tool = hooks.setdefault("PreToolUse", [])

pretool_cmd = {
    "type": "command",
    "command": f'bash "{hook_path}" PreToolUse'
}

already_has_pre = any(
    e.get("command", "").endswith("inkpulse_ws_client.sh PreToolUse")
    for e in pre_tool
    if isinstance(e, dict)
)

if not already_has_pre:
    pre_tool.append(pretool_cmd)
    print(f"  + Added PreToolUse hook")
else:
    print(f"  = PreToolUse hook already present")

# ── Stop ──────────────────────────────────────────────────────────────────────
stop_hook = hooks.setdefault("Stop", [])

stop_cmd = {
    "type": "command",
    "command": f'bash "{hook_path}" Stop'
}

already_has_stop = any(
    e.get("command", "").endswith("inkpulse_ws_client.sh Stop")
    for e in stop_hook
    if isinstance(e, dict)
)

if not already_has_stop:
    stop_hook.append(stop_cmd)
    print(f"  + Added Stop hook")
else:
    print(f"  = Stop hook already present")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"\nSettings written to {settings_path}")
PYEOF

echo -e "${GREEN}✓${NC} settings.json patched"

# ── 3. Create teams.json if missing ──────────────────────────────────────────

if [[ ! -f "$TEAMS_FILE" ]]; then
    if [[ -f "$EXAMPLE_TEAMS" ]]; then
        cp "$EXAMPLE_TEAMS" "$TEAMS_FILE"
        echo -e "${GREEN}✓${NC} Created teams.json from example: $TEAMS_FILE"
        echo -e "${YELLOW}!${NC}  Edit it with your actual project paths"
    fi
else
    echo -e "=${NC} teams.json already exists: $TEAMS_FILE"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}Installation complete.${NC}"
echo ""
echo "Next steps:"
echo "  1. Start InkPulse.app"
echo "  2. Open a new Claude Code session — it will auto-register"
echo "  3. Edit ~/.inkpulse/teams.json with your project paths"
echo ""
echo "To verify:"
echo "  bash $HOOK_DEST SessionStart"
echo "  (should send a heartbeat to InkPulse silently)"

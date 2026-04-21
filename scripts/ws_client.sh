#!/usr/bin/env bash
# InkPulse WebSocket Client Hook
# ─────────────────────────────────────────────────────────────────────────────
# Install as a Claude Code SessionStart hook so InkPulse receives live status
# updates from every session.
#
# Usage (auto-installed by install_hook.sh):
#   ~/.claude/hooks/inkpulse_ws_client.sh
#
# Protocol: JSON over WebSocket on localhost:9998
# Messages sent:
#   - connect heartbeat on start
#   - status update on STDIN events (when called with event JSON)
#   - disconnect on exit
#
# Requirements: bash, /usr/bin/nc (netcat, always present on macOS), python3
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

INKPULSE_HOST="127.0.0.1"
INKPULSE_PORT="9998"
SESSION_ID="${CLAUDE_SESSION_ID:-}"
CWD="${CLAUDE_CWD:-$(pwd)}"
HOOK_EVENT="${1:-}"  # "SessionStart" | "PreToolUse" | "PostToolUse" | "Stop"

# ── Require session ID ────────────────────────────────────────────────────────

if [[ -z "$SESSION_ID" ]]; then
    # Derive from process: use parent PID as a stable session fingerprint
    SESSION_ID="local-$$"
fi

# ── WebSocket handshake helper ────────────────────────────────────────────────
# We use Python's built-in http.server + websockets is not available everywhere,
# so we do a raw TCP WebSocket upgrade + framing using Python stdlib only.

send_ws_message() {
    local payload="$1"
    local length=${#payload}

    python3 - <<PYEOF
import socket, struct, os, sys

HOST = "$INKPULSE_HOST"
PORT = $INKPULSE_PORT
payload = b'''$payload'''

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(3)
try:
    sock.connect((HOST, PORT))
except Exception as e:
    sys.exit(0)  # InkPulse not running, skip silently

import base64, hashlib

# WebSocket HTTP Upgrade
key = base64.b64encode(os.urandom(16)).decode()
upgrade = (
    f"GET / HTTP/1.1\r\n"
    f"Host: {HOST}:{PORT}\r\n"
    f"Upgrade: websocket\r\n"
    f"Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    f"Sec-WebSocket-Version: 13\r\n"
    f"\r\n"
).encode()
sock.sendall(upgrade)

# Read HTTP response
resp = b""
while b"\r\n\r\n" not in resp:
    chunk = sock.recv(4096)
    if not chunk:
        break
    resp += chunk

if b"101" not in resp:
    sock.close()
    sys.exit(0)

# Encode WebSocket text frame (unmasked for server→client direction is wrong,
# client frames MUST be masked per RFC 6455)
data = payload
length = len(data)

mask_key = os.urandom(4)
masked = bytearray(length)
for i in range(length):
    masked[i] = data[i] ^ mask_key[i % 4]

if length < 126:
    header = struct.pack("!BB", 0x81, 0x80 | length)
elif length < 65536:
    header = struct.pack("!BBH", 0x81, 0x80 | 126, length)
else:
    header = struct.pack("!BBQ", 0x81, 0x80 | 127, length)

frame = header + mask_key + bytes(masked)
sock.sendall(frame)
sock.settimeout(0.5)
try:
    sock.recv(4096)  # drain any response
except:
    pass
sock.close()
PYEOF
}

# ── Build message ─────────────────────────────────────────────────────────────

build_status_message() {
    local state="$1"
    local tool="${2:-}"
    local target="${3:-}"
    local task="${4:-}"

    # Escape quotes in strings
    local cwd_escaped="${CWD//\"/\\\"}"
    local tool_escaped="${tool//\"/\\\"}"
    local target_escaped="${target//\"/\\\"}"
    local task_escaped="${task//\"/\\\"}"

    local tool_json="null"
    [[ -n "$tool" ]] && tool_json="\"${tool_escaped}\""

    local target_json="null"
    [[ -n "$target" ]] && target_json="\"${target_escaped}\""

    local task_json="null"
    [[ -n "$task" ]] && task_json="\"${task_escaped}\""

    cat <<JSON
{"type":"status","data":{"session_id":"${SESSION_ID}","cwd":"${cwd_escaped}","state":"${state}","current_tool":${tool_json},"current_target":${target_json},"task":${task_json}}}
JSON
}

build_heartbeat_message() {
    cat <<JSON
{"type":"heartbeat","data":{"session_id":"${SESSION_ID}"}}
JSON
}

# ── Handle hook events ────────────────────────────────────────────────────────

case "$HOOK_EVENT" in
    "SessionStart"|"")
        # Register session with InkPulse
        MSG=$(build_heartbeat_message)
        send_ws_message "$MSG" 2>/dev/null || true
        ;;

    "PreToolUse")
        # Read tool info from STDIN (Claude Code passes JSON)
        if [[ -t 0 ]]; then
            # No stdin (called without pipe), just send idle status
            MSG=$(build_status_message "idle")
        else
            STDIN_DATA=$(cat)
            TOOL_NAME=$(echo "$STDIN_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
            TOOL_INPUT=$(echo "$STDIN_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); inp=d.get('tool_input',{}); print(list(inp.values())[0] if inp else '')" 2>/dev/null || echo "")
            MSG=$(build_status_message "working" "$TOOL_NAME" "$TOOL_INPUT")
        fi
        send_ws_message "$MSG" 2>/dev/null || true
        ;;

    "PostToolUse")
        MSG=$(build_status_message "idle")
        send_ws_message "$MSG" 2>/dev/null || true
        ;;

    "Stop")
        # Session ending — send a final status so InkPulse can grey out the slot
        MSG=$(build_status_message "stopped")
        send_ws_message "$MSG" 2>/dev/null || true
        ;;
esac

# Always exit 0 — never block Claude Code
exit 0

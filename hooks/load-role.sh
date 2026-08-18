#!/usr/bin/env bash
# SessionStart hook: if this session was launched with HANDOFF_ROLE=orchestrator|implementer|reviewer,
# inject roles/<ROLE>.md as additional context so the session starts already "being" its role.
# Silent no-op for every other session.
set -euo pipefail
role="${HANDOFF_ROLE:-}"
[ -z "$role" ] && exit 0
role_upper=$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
file="$root/roles/$role_upper.md"
if [ ! -f "$file" ]; then
  printf '{"systemMessage":"claude-handoff: unknown HANDOFF_ROLE=%s (no roles/%s.md)"}\n' "$role" "$role_upper"
  exit 0
fi
# JSON-escape the file content (python3 is present on macOS/Linux dev machines; fall back to plain stdout).
if command -v python3 >/dev/null 2>&1; then
  python3 - "$file" "$role" <<'PY'
import json, sys
content = open(sys.argv[1], encoding="utf-8").read()
role = sys.argv[2]
print(json.dumps({
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": f"[claude-handoff] You are the {role.upper()} session. Follow these role instructions for the whole session:\n\n{content}"
  }
}))
PY
else
  printf '[claude-handoff] You are the %s session. Role instructions:\n\n' "$role_upper"; cat "$file"
fi

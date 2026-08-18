#!/usr/bin/env bash
# SessionStart hook: if this session was launched with HANDOFF_ROLE=orchestrator|implementer|reviewer,
# print roles/<ROLE>.md so Claude Code adds it to the session context. Silent no-op otherwise.
# Pure bash on purpose — runs on macOS, Linux, WSL and Windows (Git Bash, which Claude Code requires anyway).
set -u
role="${HANDOFF_ROLE:-}"
[ -z "$role" ] && exit 0
role_upper=$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
file="$root/roles/$role_upper.md"
if [ ! -f "$file" ]; then
  printf '[claude-handoff] unknown HANDOFF_ROLE=%s (no roles/%s.md)\n' "$role" "$role_upper"
  exit 0
fi
printf '[claude-handoff] You are the %s session. Follow these role instructions for the whole session:\n\n' "$role_upper"
cat "$file"

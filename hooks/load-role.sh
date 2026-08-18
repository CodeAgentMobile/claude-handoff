#!/usr/bin/env bash
# SessionStart hook: when HANDOFF_ROLE is set, inject (1) roles/ENGINEERING.md (shared), (2) roles/<ROLE>.md,
# (3) project-local overrides from <repo>/.claude-handoff/local-engineering.md and local-<role>.md if present.
# Silent no-op for every other session. Pure bash: macOS, Linux, WSL, Windows (Git Bash).
set -u
role="${HANDOFF_ROLE:-}"
[ -z "$role" ] && exit 0
ROLE=$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')
lrole=$(printf '%s' "$role" | tr '[:upper:]' '[:lower:]')
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
repo="${HANDOFF_REPO:-$PWD}"

printf '[claude-handoff] You are the %s session. The following role instructions apply for the whole session.\n\n' "$ROLE"
[ -f "$root/roles/ENGINEERING.md" ] && { cat "$root/roles/ENGINEERING.md"; printf '\n\n'; }
if [ -f "$root/roles/$ROLE.md" ]; then
  cat "$root/roles/$ROLE.md"
else
  printf '[claude-handoff] (no roles/%s.md in the plugin - role has no dedicated instructions)\n' "$ROLE"
fi

seen=" "
for d in "$repo" "$PWD"; do
  d=$(cd "$d" 2>/dev/null && pwd -P) || continue
  case "$seen" in *" $d "*) continue;; esac
  seen="$seen$d "
  for f in "$d/.claude-handoff/local-engineering.md" "$d/.claude-handoff/local-$lrole.md"; do
    [ -f "$f" ] && { printf '\n\n# Project-local rules (%s)\n\n' "$f"; cat "$f"; }
  done
done
exit 0

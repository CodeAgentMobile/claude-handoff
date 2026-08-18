#!/usr/bin/env bash
# Shared helpers for claude-handoff scripts. Source me: `. "$(dirname "$0")/lib.sh"`.
set -u
HANDOFF_SESSION="${HANDOFF_SESSION:-handoff}"          # tmux session name
HANDOFF_SOCKET="${HANDOFF_SOCKET:-handoff}"            # tmux -L socket → isolated from the user's own tmux
HANDOFF_STATE="${HANDOFF_STATE:-$HOME/.claude/handoff/.state}"
mkdir -p "$HANDOFF_STATE" 2>/dev/null || true

hf_os() {
  case "$(uname -s)" in
    Darwin) echo mac;;
    Linux)  grep -qi microsoft /proc/version 2>/dev/null && echo wsl || echo linux;;
    MINGW*|MSYS*|CYGWIN*) echo windows;;
    *) echo unknown;;
  esac
}

hf_tmux() { tmux -L "$HANDOFF_SOCKET" "$@"; }

# On native Windows (Git Bash) tmux lives in WSL; route tmux calls there.
hf_tmux_any() {
  if [ "$(hf_os)" = windows ]; then wsl.exe -e bash -lc "tmux -L $HANDOFF_SOCKET $(printf '%q ' "$@")"; else hf_tmux "$@"; fi
}

hf_ensure_tmux() {
  case "$(hf_os)" in
    windows) wsl.exe -e bash -lc 'command -v tmux >/dev/null || (command -v apt-get >/dev/null && sudo apt-get install -y tmux)' ;;
    mac)     command -v tmux >/dev/null || { command -v brew >/dev/null && brew install tmux; } ;;
    *)       command -v tmux >/dev/null || { command -v apt-get >/dev/null && sudo apt-get install -y tmux; } ;;
  esac
  if [ "$(hf_os)" = windows ]; then wsl.exe -e bash -lc 'command -v tmux' >/dev/null; else command -v tmux >/dev/null; fi
}

# The env-clearing prefix every peer command needs (child-session marker etc.).
hf_env_clear() { printf '%s' "for v in \$(env | sed -n 's/^\\(CLAUDE[A-Za-z_]*\\)=.*/\\1/p'); do unset \$v; done"; }

hf_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

hf_plugin_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

hf_log() { printf '[claude-handoff] %s\n' "$*"; }

#!/usr/bin/env bash
# Stop all peers: kill the tmux session, sleep inhibitor, terminal windows; optionally remove role worktrees.
#   close-handoff.sh [--repo <path>] [--remove-worktrees]
. "$(dirname "$0")/lib.sh"
repo=""; rm_wt=0
while [ $# -gt 0 ]; do case "$1" in --repo) repo="$2"; shift 2;; --remove-worktrees) rm_wt=1; shift;; *) shift;; esac; done
hf_tmux_any kill-session -t "$HANDOFF_SESSION" 2>/dev/null
for f in caffeinate.pid inhibit.pid; do [ -f "$HANDOFF_STATE/$f" ] && { kill "$(cat "$HANDOFF_STATE/$f")" 2>/dev/null; rm -f "$HANDOFF_STATE/$f"; }; done
case "$(hf_os)" in
  mac) osascript -e 'tell application "Terminal" to close (every window whose name contains "handoff")' >/dev/null 2>&1 ;;
esac
if [ "$rm_wt" = 1 ] && [ -n "$repo" ]; then for r in implementer reviewer; do "$(dirname "$0")/setup-worktree.sh" "$repo" "$r" --remove; done; fi
hf_log "handoff session closed"

#!/usr/bin/env bash
# Stop all peers: kill the tmux session, sleep inhibitor, terminal windows, and remove the role worktrees.
#   close-handoff.sh [--repo <path>] [--keep-worktrees]
# Worktrees are removed by default — a finished job must not leave .worktrees/<role> behind. Pass --keep-worktrees to keep them.
. "$(dirname "$0")/lib.sh"
repo=""; keep_wt=0
while [ $# -gt 0 ]; do case "$1" in --repo) repo="$2"; shift 2;; --keep-worktrees) keep_wt=1; shift;; --remove-worktrees) shift;; *) shift;; esac; done
cd "$HOME" 2>/dev/null || true   # never sit inside a worktree we are about to remove
hf_tmux_any kill-session -t "$HANDOFF_SESSION" 2>/dev/null
for f in caffeinate.pid inhibit.pid; do [ -f "$HANDOFF_STATE/$f" ] && { kill "$(cat "$HANDOFF_STATE/$f")" 2>/dev/null; rm -f "$HANDOFF_STATE/$f"; }; done
case "$(hf_os)" in
  mac) osascript -e 'tell application "Terminal" to close (every window whose name contains "handoff")' >/dev/null 2>&1 ;;
esac
if [ -n "$repo" ]; then
  if [ "$keep_wt" = 1 ]; then hf_log "keeping worktrees under $repo/.worktrees (--keep-worktrees)"
  else
    for r in $(ls "$repo/.worktrees" 2>/dev/null); do "$(dirname "$0")/setup-worktree.sh" "$repo" "$r" --remove; done
    rmdir "$repo/.worktrees" 2>/dev/null || true
    git -C "$repo" worktree prune 2>/dev/null || true
  fi
else
  hf_log "no --repo given: worktrees (if any) were not removed"
fi
hf_log "handoff session closed"

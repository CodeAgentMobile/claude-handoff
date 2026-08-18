#!/usr/bin/env bash
# Launch a peer Claude Code session as a tmux window (session "handoff"), with its role loaded.
#   launch-peer.sh <role> [--model <alias>] [--repo <path>] [--cwd <path>] [--resume <session-id>] [--no-terminal]
# <role> = implementer | reviewer (any name works; roles/<ROLE>.md is loaded if it exists)
# --cwd defaults to the role's worktree if <repo>/.worktrees/<role> exists, else <repo>.
. "$(dirname "$0")/lib.sh"
role="${1:?role}"; shift
model=""; repo="$(pwd)"; cwd=""; resume=""; open_term=1
while [ $# -gt 0 ]; do case "$1" in
  --model) model="$2"; shift 2;; --repo) repo="$2"; shift 2;; --cwd) cwd="$2"; shift 2;;
  --resume) resume="$2"; shift 2;; --no-terminal) open_term=0; shift;;
  *) echo "unknown arg $1" >&2; exit 2;; esac; done
[ -z "$cwd" ] && { [ -d "$repo/.worktrees/$role" ] && cwd="$repo/.worktrees/$role" || cwd="$repo"; }
root=$(hf_plugin_root); ROLE=$(hf_upper "$role"); rolefile="$root/roles/$ROLE.md"
hf_ensure_tmux || { hf_log "tmux unavailable — install tmux (or WSL+tmux on Windows) and retry"; exit 1; }
prompt="You are the $role session in a multi-session workflow. Reply only: ready. Then wait for [DEV handoff] messages from the orchestrator and follow them exactly."
cmd="cd '$cwd' && $(hf_env_clear) && export HANDOFF_ROLE=$role HANDOFF_REPO='$repo' && claude -n $role ${model:+--model $model} ${resume:+--resume $resume} --permission-mode bypassPermissions $( [ -f "$rolefile" ] && printf -- "--append-system-prompt-file '%s'" "$rolefile" ) '$prompt'"
if hf_tmux_any has-session -t "$HANDOFF_SESSION" 2>/dev/null; then
  hf_tmux_any kill-window -t "$HANDOFF_SESSION:$role" 2>/dev/null
  hf_tmux_any new-window -t "$HANDOFF_SESSION" -n "$role" "$cmd"
else
  hf_tmux_any new-session -d -s "$HANDOFF_SESSION" -n "$role" "$cmd"
  # keep the host awake while the swarm lives (macOS: caffeinate bound to the tmux server; Linux: systemd-inhibit)
  case "$(hf_os)" in
    mac)   srv=$(hf_tmux display-message -p '#{pid}' 2>/dev/null); [ -n "$srv" ] && { nohup caffeinate -i -w "$srv" >/dev/null 2>&1 & echo $! > "$HANDOFF_STATE/caffeinate.pid"; } ;;
    linux) command -v systemd-inhibit >/dev/null && { nohup systemd-inhibit --what=idle:sleep --why="claude-handoff peers" sleep infinity >/dev/null 2>&1 & echo $! > "$HANDOFF_STATE/inhibit.pid"; } ;;
  esac
  [ "$open_term" = 1 ] && "$root/scripts/open-terminal.sh"   # one visible window attached to the whole session
fi
hf_log "launched $role (model=${model:-default}, cwd=$cwd) — verify with ListAgents in ~25s"

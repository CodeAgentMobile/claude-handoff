#!/usr/bin/env bash
# Kill a peer session and relaunch it fresh (clean context). Same args as launch-peer.sh.
#   recycle-peer.sh <role> [launch-peer args...]
. "$(dirname "$0")/lib.sh"
role="${1:?role}"
hf_tmux_any kill-window -t "$HANDOFF_SESSION:$role" 2>/dev/null
case "$(hf_os)" in
  windows) powershell.exe -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*claude*-n $role*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1 ;;
  *) pkill -f "claude -n $role" 2>/dev/null ;;
esac
sleep 1
exec "$(dirname "$0")/launch-peer.sh" "$@" --force

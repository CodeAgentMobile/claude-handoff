#!/usr/bin/env bash
# Open a VISIBLE terminal window/tab attached to the handoff tmux session (or a specific window).
#   open-terminal.sh [<tmux-window-name>]
# Adapter is auto-detected; override with HANDOFF_TERMINAL=iterm2|ghostty|terminal-app|windows-terminal|x-terminal|none
. "$(dirname "$0")/lib.sh"
target="$HANDOFF_SESSION${1:+:$1}"
attach="tmux -L $HANDOFF_SOCKET attach-session -t $target"

detect() {
  [ -n "${HANDOFF_TERMINAL:-}" ] && { echo "$HANDOFF_TERMINAL"; return; }
  case "$(hf_os)" in
    mac)
      case "${TERM_PROGRAM:-}" in iTerm.app) echo iterm2; return;; ghostty) echo ghostty; return;; esac
      [ -d /Applications/iTerm.app ] && { echo iterm2; return; }
      [ -d /Applications/Ghostty.app ] && { echo ghostty; return; }
      echo terminal-app;;
    windows) command -v wt.exe >/dev/null && echo windows-terminal || echo none;;
    wsl)     command -v wt.exe >/dev/null && echo windows-terminal || echo none;;
    linux)   command -v x-terminal-emulator >/dev/null && echo x-terminal || echo none;;
    *) echo none;;
  esac
}

adapter=$(detect)
title="handoff${1:+ · $1}"
case "$adapter" in
  iterm2)
    osascript -e "tell application \"iTerm\"
      activate
      set w to (create window with default profile)
      tell current session of w to write text \"$attach\"
    end tell" >/dev/null ;;
  ghostty)
    open -na Ghostty --args --title="$title" -e bash -lc "$attach" ;;
  terminal-app)
    osascript -e "tell application \"Terminal\"
      activate
      do script \"$attach\"
    end tell" >/dev/null ;;
  windows-terminal)
    # tmux lives in WSL; Windows Terminal opens a tab (window group "handoff") that attaches inside WSL
    wt.exe -w handoff new-tab --title "$title" wsl.exe -e bash -lc "$attach" ;;
  x-terminal)
    x-terminal-emulator -T "$title" -e bash -lc "$attach" >/dev/null 2>&1 & ;;
  none)
    hf_log "no terminal adapter available — attach manually: $attach"; exit 0;;
esac
hf_log "opened $adapter window attached to $target"

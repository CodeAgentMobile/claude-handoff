#!/usr/bin/env bash
# Create or update a per-role git worktree under <repo>/.worktrees/<role>.
#   setup-worktree.sh <repo> <role> --branch <name> [--base <ref>]   # implementer: branch checkout (created from base if missing)
#   setup-worktree.sh <repo> <role> --commit <sha>                    # reviewer: detached at an exact commit
#   setup-worktree.sh <repo> <role> --remove
# Prints the worktree path. Symlinks node_modules from the main checkout when present (so tests run without a reinstall).
. "$(dirname "$0")/lib.sh"
repo="${1:?repo}"; role="${2:?role}"; shift 2
branch=""; base=""; commit=""; remove=0
while [ $# -gt 0 ]; do case "$1" in
  --branch) branch="$2"; shift 2;; --base) base="$2"; shift 2;; --commit) commit="$2"; shift 2;; --remove) remove=1; shift;;
  *) echo "unknown arg $1" >&2; exit 2;; esac; done
wt="$repo/.worktrees/$role"
cd "$repo" || exit 1
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { hf_log "$repo is not a git repo"; exit 1; }
grep -qx '.worktrees/' .git/info/exclude 2>/dev/null || echo '.worktrees/' >> .git/info/exclude
if [ "$remove" = 1 ]; then cd "$repo"; git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"; git worktree prune; hf_log "removed $wt"; exit 0; fi
if [ -n "$commit" ]; then
  if [ -d "$wt" ]; then git -C "$wt" checkout --quiet --detach "$commit"
  else git worktree add --quiet --detach "$wt" "$commit"; fi
elif [ -n "$branch" ]; then
  if [ -d "$wt" ]; then git -C "$wt" checkout --quiet "$branch" 2>/dev/null || git -C "$wt" checkout --quiet -b "$branch" "${base:-HEAD}"
  elif git show-ref --verify --quiet "refs/heads/$branch"; then git worktree add --quiet "$wt" "$branch"
  else git worktree add --quiet -b "$branch" "$wt" "${base:-HEAD}"; fi
else echo "need --branch or --commit" >&2; exit 2; fi
# share heavy dependency dirs from the main checkout (jest/vitest resolve through the symlink fine)
for d in node_modules .venv vendor; do
  [ -e "$repo/$d" ] && [ ! -e "$wt/$d" ] && ln -s "$repo/$d" "$wt/$d"
done
echo "$wt"

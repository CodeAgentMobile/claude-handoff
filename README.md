# claude-handoff

**Orchestrator → Implementer → Reviewer**, as three separate [Claude Code](https://claude.com/claude-code) sessions with clean contexts, file-based handoffs, and an *isolated* reviewer that never sees how the code was written.

```
 orchestrator (you + the strongest model)      implementer (opus)            reviewer (strongest, fresh each round)
 ─────────────────────────────────────────     ────────────────────────      ────────────────────────────────────
 ticket → grounding → plan → APPROVAL  ──►  plan.md → TDD → commits  ──►  plan.md + diff → tests + code-review
        ▲                                     impl-report-N.md ──┐            review-report-N.md ──┐
        └──────────── final-report.md ◄───────────────────────────┴───────────── PASS / FAIL ◄──────┘
                                                                          FAIL → implementer round N+1 (max 3)
```

Why: one session that plans, writes and reviews its own code grades its own homework. Splitting the roles into sessions (not subagents) gives each a real, inspectable context and lets the reviewer read the diff with genuinely fresh eyes.

## What's inside

| Path | Purpose |
|---|---|
| `skills/orchestrating-handoffs/SKILL.md` | The workflow. Invoke `/orchestrating-handoffs` in the session that will orchestrate. |
| `roles/ORCHESTRATOR.md` · `IMPLEMENTER.md` · `REVIEWER.md` | Per-role contract (Owns / Does Not Own / Handoff). |
| `roles/ENGINEERING.md` | Shared engineering rules loaded for every role (small increments, tests that fail for a plausible wrong implementation, no heavy jobs in parallel, worktree discipline…). |
| `hooks/hooks.json` + `hooks/load-role.sh` | `SessionStart` hook: with `HANDOFF_ROLE=<role>` it injects `ENGINEERING.md` + `roles/<ROLE>.md` + your repo's `.claude-handoff/local-*.md`. |
| `scripts/launch-peer.sh` · `recycle-peer.sh` · `setup-worktree.sh` · `open-terminal.sh` · `close-handoff.sh` | Peer lifecycle: tmux window per peer (own socket), per-role git worktrees, visible terminal via adapters (iTerm2 / Ghostty / Terminal.app / Windows Terminal+WSL / x-terminal), sleep inhibitor, clean shutdown. |

**Per-role worktrees.** The implementer works in `<repo>/.worktrees/implementer` on the ticket branch; the reviewer sits in `<repo>/.worktrees/reviewer` **detached at the exact commit** under review — so it never sees half-edited files and can't race the implementer. `node_modules`/`.venv`/`vendor` are symlinked from the main checkout; `.worktrees/` is excluded via `.git/info/exclude`.

**Project-local rules.** Drop `.claude-handoff/local-engineering.md` / `local-implementer.md` / `local-reviewer.md` in your repo to add project rules (test commands, conventions) without forking the plugin.

## Install

```
/plugin marketplace add CodeAgentMobile/claude-handoff
/plugin install claude-handoff@codeagentmobile
```

Or try it without installing: `claude --plugin-dir /path/to/claude-handoff`.

## Use — step by step

### 1. Open the orchestrator session
In your IDE terminal (or any terminal), start Claude Code in the repo you'll work on, on your **most capable model**, and name the session:

```
claude --model <strongest>          # e.g. the current top tier
/rename orchestrator                # peers reply to this exact name
```

(Or launch it pre-loaded with its role: `HANDOFF_ROLE=orchestrator claude -n orchestrator`.)

### 2. Invoke the skill
```
/orchestrating-handoffs
```
The skill (Phase −1) confirms this session is the orchestrator, then checks with `ListAgents` whether `implementer` and `reviewer` sessions are running. **If they aren't, it launches them for you** — no manual setup:

- installs `tmux` via Homebrew if missing;
- creates a detached tmux session named **`handoff`** with one window per peer (`implementer` on the best coding model, `reviewer` on the strongest model);
- each peer starts with its role instructions (`roles/<ROLE>.md`) already loaded via `HANDOFF_ROLE` + the SessionStart hook, in `bypassPermissions` mode so cross-session messages are delivered without a manual "Deliver" click;
- opens a **visible terminal window already attached** to the tmux session (iTerm2, Ghostty, Terminal.app, Windows Terminal + WSL, or `x-terminal-emulator`; `HANDOFF_TERMINAL=…` to force one) and keeps the host awake (`caffeinate` / `systemd-inhibit`) while peers live;
- gives each peer its own git worktree and briefs it with an exact `commit:` to review.

Then it walks the ticket: **plan → your approval → implementer (worktree, branch) → isolated review (fresh session, worktree @ commit) → fix loop (max 3) → final report → close**. You keep the outward actions (push, PR, ticket writes) unless you explicitly delegate them.

### 3. Watch the peers (tmux — macOS/Linux/WSL)
A terminal window attached to the peers opens automatically. To (re)attach from any terminal — an IDE tab works — note the **own socket** (`-L handoff`, so your personal tmux is untouched):

```
tmux -L handoff attach -t handoff
```

| Keys | Action |
|---|---|
| `Ctrl-b n` / `Ctrl-b p` | next / previous window (implementer ↔ reviewer) |
| `Ctrl-b <number>` | jump to window N |
| `Ctrl-b w` | window picker |
| `Ctrl-b d` | detach (peers keep running) |
| `tmux -L handoff ls` · `tmux -L handoff list-windows -t handoff` | what's running |
| `tmux -L handoff capture-pane -p -t handoff:reviewer` | print a peer's screen without attaching |
| `scripts/recycle-peer.sh reviewer` | stop + relaunch one peer fresh (the orchestrator does this every review round) |
| `scripts/close-handoff.sh [--repo <repo> --remove-worktrees]` | stop all peers, sleep inhibitor, windows (and optionally the role worktrees) |

On **Windows** there is no tmux: the peers open as tabs of a Windows Terminal window named `handoff` — just switch tabs.

You can type into a peer's window like any Claude Code session (e.g. to answer a question it asks), but the workflow itself is driven by the orchestrator through `SendMessage`.

### 4. What you'll be asked to do
- **Confirm the plan** (the orchestrator will not dispatch anything before that).
- Occasionally answer a design question the orchestrator can't decide alone.
- **Push / open the PR** at the end (or tell the orchestrator to do it).

Everything else — briefing, waiting, relaying, recycling the reviewer for a clean context each round, the final ≤150-word report — is the orchestrator's job.

### Files
Handoff files live in `~/.claude/handoff/<TICKET>/` (`plan.md`, `inbox/<role>/brief-N.md`, `impl-report-N.md`, `review-report-N.md`, `final-report.md`) — a durable location on purpose (`/tmp` gets wiped on reboot); the `inbox/` copy of each brief lets a restarted peer resume without the orchestrator resending.

## Model policy

| Role | Model |
|---|---|
| Orchestrator | the most capable model available |
| Implementer | the best coding model (`opus` today) |
| Reviewer | the most capable model available |

Move up when a stronger tier ships; don't pin old names.

## Hard-won details (all encoded in the skill)

- Peers must be launched with the inherited `CLAUDE_*` env vars cleared, or they become invisible *child* sessions.
- Peers must run with `--permission-mode bypassPermissions` to receive cross-session messages without a manual "Deliver" click. That is a deliberate trade-off — you own those sessions.
- A session cannot `/clear` itself, so the reviewer is **recycled** (killed + relaunched) before every round, and reviews an exact commit in its own worktree.
- The reviewer runs **only** the listed test specs — never lint/build/full suite (laptops overheat; the implementer already ran them).

## Platforms

| Platform | Peers run in | Notes |
|---|---|---|
| macOS | tmux session `handoff` (auto-installed via Homebrew) | fallback: Terminal.app windows |
| Linux / WSL | tmux session `handoff` (auto-installed via apt if missing) | fallback: `x-terminal-emulator` |
| Windows | tmux **inside WSL** (scripts route tmux through `wsl.exe`), Windows Terminal tab attached (`wt.exe … wsl.exe -e tmux attach`) | requires WSL with tmux (`wsl --install`, `sudo apt-get install tmux`); Claude Code runs in Git Bash or inside WSL |

On Windows the handoff files live in `%USERPROFILE%\.claude\handoff\<TICKET>\`. Windows support follows the same rules as macOS/Linux but has had less field testing — issues welcome.

## Requirements

Claude Code ≥ 2.1 (cross-session `SendMessage` / `ListAgents`), `bash`, `git` ≥ 2.20 (worktrees), `tmux` (auto-installed via Homebrew/apt; inside WSL on Windows).

## Credits

The per-role worktrees, terminal adapters, restart-safe inbox, sleep inhibitor and the *Owns / Does Not Own / Handoff* role structure are borrowed from Robert C. Martin's [swarm-forge](https://github.com/unclebob/swarm-forge); this plugin is a lighter, Claude-Code-native take (cross-session messaging instead of a handoff daemon).

## Contributing

Issues and PRs welcome. Keep the skill generic (no project-specific tickets/repos), keep the role docs terse, and if you change a rule, say what failure it prevents.

## License

MIT

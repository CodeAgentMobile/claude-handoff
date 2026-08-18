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
| `roles/ORCHESTRATOR.md` · `IMPLEMENTER.md` · `REVIEWER.md` | System instructions per role. |
| `hooks/hooks.json` + `hooks/load-role.sh` | `SessionStart` hook: when a session starts with `HANDOFF_ROLE=<role>`, injects `roles/<ROLE>.md`. |

The orchestrator launches the peers itself — one **tmux** window each (installs tmux via Homebrew if missing; falls back to a Terminal.app window). Attach from any terminal (an IDE tab works): `tmux attach -t handoff`.

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
- falls back to a Terminal.app window only when tmux can't be installed.

Then it walks the ticket: **plan → your approval → implementer → isolated review → fix loop (max 3) → final report**. You keep the outward actions (push, PR, ticket writes) unless you explicitly delegate them.

### 3. Watch the peers (tmux)
tmux runs **detached** — nothing pops up on its own. To see the peer sessions, open a new terminal tab (the IDE's integrated terminal works) and attach:

```
tmux attach -t handoff
```

| Keys | Action |
|---|---|
| `Ctrl-b n` / `Ctrl-b p` | next / previous window (implementer ↔ reviewer) |
| `Ctrl-b <number>` | jump to window N |
| `Ctrl-b w` | window picker |
| `Ctrl-b d` | detach (peers keep running) |
| `tmux ls` · `tmux list-windows -t handoff` | what's running |
| `tmux capture-pane -p -t handoff:reviewer` | print a peer's screen without attaching |
| `tmux kill-window -t handoff:reviewer` | stop one peer (the orchestrator does this itself when recycling the reviewer) |
| `tmux kill-session -t handoff` | stop all peers |

You can type into a peer's window like any Claude Code session (e.g. to answer a question it asks), but the workflow itself is driven by the orchestrator through `SendMessage`.

### 4. What you'll be asked to do
- **Confirm the plan** (the orchestrator will not dispatch anything before that).
- Occasionally answer a design question the orchestrator can't decide alone.
- **Push / open the PR** at the end (or tell the orchestrator to do it).

Everything else — briefing, waiting, relaying, recycling the reviewer for a clean context each round, the final ≤150-word report — is the orchestrator's job.

### Files
Handoff files live in `~/.claude/handoff/<TICKET>/` (`plan.md`, `impl-report-N.md`, `review-report-N.md`, `final-report.md`) — a durable location on purpose (`/tmp` gets wiped on reboot).

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
- A session cannot `/clear` itself, so the reviewer is **recycled** (killed + relaunched) before every round.
- The reviewer runs **only** the listed test specs — never lint/build/full suite (laptops overheat; the implementer already ran them).

## Requirements

macOS or Linux, Claude Code ≥ 2.1 (cross-session `SendMessage`/`ListAgents`), `tmux` (auto-installed via Homebrew on macOS) — Terminal.app fallback is macOS-only.

## Contributing

Issues and PRs welcome. Keep the skill generic (no project-specific tickets/repos), keep the role docs terse, and if you change a rule, say what failure it prevents.

## License

MIT

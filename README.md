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

## Use

1. Open the session that will orchestrate on your most capable model, name it: `/rename orchestrator`.
2. `/orchestrating-handoffs` — the skill checks/launches `implementer` and `reviewer` sessions, then walks you through: plan → your approval → implementer → isolated review → loop → final report.
3. You keep the outward actions: push, PR, ticket writes.

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

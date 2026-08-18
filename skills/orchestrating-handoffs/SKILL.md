---
name: orchestrating-handoffs
description: Use when this session is the ORCHESTRATOR for a ticket or feature and the work must be handed to a separate implementer Claude Code session and then to a separate, clean reviewer session (peer sessions in tmux, each in its own git worktree) — any task where planning, implementation and review run in different sessions/models with clean contexts between them.
---

# orchestrating-handoffs

Three **sessions**, three contexts, three worktrees, one baton. **You (this session, "orchestrator") never implement and never review the implementer's work** — you design, brief, relay, and decide. Peers are separate Claude Code sessions; you talk to them with `SendMessage`, never with `Agent`.

Read the standing contracts once: `roles/ORCHESTRATOR.md` (yours), `roles/IMPLEMENTER.md`, `roles/REVIEWER.md`, `roles/ENGINEERING.md` (shared) — all under `PLUGIN_ROOT` = this skill's base directory `/../..`. Sessions launched by the scripts get theirs injected automatically (`HANDOFF_ROLE` + SessionStart hook + `--append-system-prompt-file`). If this session was not started with `HANDOFF_ROLE=orchestrator`, read `roles/ORCHESTRATOR.md` now.

| Role | Runs in | Model | `SendMessage.to` | Worktree | Context |
|---|---|---|---|---|---|
| **Orchestrator** | this session | the most capable model (Fable 5 today) | — | main checkout | full conversation |
| **Implementer** | tmux window `handoff:implementer` | the best coding model (`opus` today) | `implementer` | `<repo>/.worktrees/implementer` on the ticket branch | plan brief only |
| **Reviewer** | tmux window `handoff:reviewer`, recycled every round | the most capable model (session default if that's the strongest, else `--model`) | `reviewer` | `<repo>/.worktrees/reviewer` detached at the exact commit | reviewer brief only — **never the implementer's output** |

"Today" = at the time of writing; when a stronger tier ships, move up. You can't switch your own model — if this session isn't on the strongest, ask the engineer to `/model` before Phase 0.

## Files (durable, restart-safe)

```
~/.claude/handoff/<TICKET>/            (%USERPROFILE%\.claude\handoff\<TICKET>\ on Windows)
  plan.md                              orchestrator → implementer (approved plan; Amendment N sections appended, never rewritten)
  inbox/implementer/brief-N.md         the exact brief you sent (peer re-reads it after a restart)
  inbox/reviewer/brief-N.md
  impl-report-N.md                     implementer → orchestrator (has a "## Commit" line)
  review-report-N.md                   reviewer → orchestrator (has a "## Commit" line)
  final-report.md                      orchestrator → engineer
```

`/private/tmp` and the session scratchpad are wiped on reboot — never put handoff files there. Files carry content; `SendMessage` carries a path plus one status line.

## Scripts (in `PLUGIN_ROOT/scripts/`, all bash; macOS · Linux · WSL · Windows-with-WSL)

| Script | Does |
|---|---|
| `setup-worktree.sh <repo> <role> --branch <b> [--base <ref>]` / `--commit <sha>` / `--remove` | creates/updates `<repo>/.worktrees/<role>` (branch checkout for the implementer, detached commit for the reviewer), symlinks `node_modules`/`.venv`/`vendor` from the main checkout, excludes `.worktrees/` via `.git/info/exclude`; prints the path |
| `launch-peer.sh <role> [--model m] [--repo p] [--cwd p] [--resume id] [--no-terminal]` | tmux window `handoff:<role>` (own socket `-L handoff`), env `CLAUDE_*` cleared, `HANDOFF_ROLE`/`HANDOFF_REPO` set, `bypassPermissions`, role file appended, first prompt; on first launch also starts a sleep inhibitor (`caffeinate` / `systemd-inhibit`) and **opens a visible terminal attached to the session** (adapter auto-detect: iTerm2 → Ghostty → Terminal.app → Windows Terminal(+WSL) → `x-terminal-emulator`; override with `HANDOFF_TERMINAL=…`; skip with `--no-terminal`). `--cwd` defaults to the role's worktree if it exists |
| `recycle-peer.sh <role> [launch args]` | kills the peer's window/process and relaunches it fresh — this is how the reviewer gets a clean context every round |
| `open-terminal.sh [<window>]` | (re)opens a visible terminal attached to `handoff` |
| `close-handoff.sh [--repo p] [--remove-worktrees]` | kills the tmux session, sleep inhibitor, terminal windows; optionally removes role worktrees |

Why every ingredient is load-bearing (verified on macOS, Claude Code 2.1.x): clearing `CLAUDE_*` prevents the peer from being an invisible *child* session; `bypassPermissions` is the only mode that delivers cross-session messages without a manual "Deliver" click (`manual`/`acceptEdits`/`auto` hold them) — the engineer's standing choice for peers, say so if they want stricter; the first prompt makes the session complete a turn and register as a peer; tmux uses its own socket so it never touches the engineer's tmux; IDE terminal tabs can't be created from the CLI, so tmux (attached in one IDE tab with `tmux -L handoff attach -t handoff`) is how you get "tabs".

## Phase −1 — Claim the role, ensure peers

1. **Claim orchestrator — with confirmation.** `ListAgents`: if a peer named `orchestrator` is listed, another session holds the role — ask which one should orchestrate; don't proceed as a second one. Otherwise ask one question: "This session will orchestrate <TICKET>. Confirm, `/rename orchestrator` if the prompt box doesn't show that name, and make sure it's on the most capable model (`/model`)." Wait for the confirmation.
2. Detect the OS once (`uname -s`). Native Windows needs WSL with tmux (`wsl --install`, then `sudo apt-get install tmux` inside) — the scripts route tmux calls through `wsl.exe`; if WSL is absent, stop and tell the engineer.
3. Peers are launched **per phase** (implementer in Phase 1, reviewer in Phase 2) — but check now with `ListAgents` whether `implementer`/`reviewer` sessions already exist (previous ticket, or tabs the engineer opened). Two peers with the same name is a failure mode: SendMessage becomes ambiguous and briefs can land on the wrong one. Decide with the engineer per phase: reuse or replace — never launch a duplicate. **Never fall back to `Agent` subagents** for these roles.
4. First time on this machine tell the engineer once: "Peers run in tmux session `handoff` (own socket). A terminal window attached to it opens automatically; to attach from an IDE tab: `tmux -L handoff attach -t handoff` (Ctrl-b n / Ctrl-b <number> to switch, Ctrl-b d to detach)."

## Phase 0 — Design (orchestrator only)

All shaping, spec and planning happen here, before anything is sent. Use whatever ticket/planning skills you have (a ticket-loading skill, `superpowers:brainstorming`, `superpowers:writing-plans`) or plain careful reading of the ticket and the code. Ask one or two sharp questions rather than guessing. **Nothing is sent, launched or committed until the engineer approves the plan.** Then write `plan.md`: goal · ticket link · acceptance criteria · exact files/functions · tests per criterion · verification commands (**test commands first and separately** — the reviewer runs only those) · out-of-scope · branch + base · commit convention · handoff dir · worktree paths (`<repo>/.worktrees/implementer`, `<repo>/.worktrees/reviewer`).

## Phase 1 — Implement (`implementer`)

1. Worktree: `setup-worktree.sh <repo> implementer --branch <branch> --base <base>`.
2. **Never a second `implementer`.** If `ListAgents` already lists one (e.g. an IDE tab the engineer opened, or last ticket's session), ask the engineer once: *reuse it* (send the brief there — it must then `cd` into the worktree itself; it may lack the v0.3 role instructions) or *replace it* (`recycle-peer.sh implementer --model opus --repo <repo>` — kills the old process, including an IDE tab's). Only when none is listed: `launch-peer.sh implementer --model opus --repo <repo>` (it refuses if a same-named process exists; `--force` overrides). Wait ~25 s, `ListAgents` must list `implementer` (Windows Git Bash has no `pgrep` — just wait). Not listed → `tmux -L handoff capture-pane -p -t handoff:implementer`, tell the engineer, stop.
3. Write the brief to `inbox/implementer/brief-N.md`, then `SendMessage` it to `implementer` (same text):

```
[DEV handoff] You are the IMPLEMENTER for <TICKET> (round <N>).
Worktree: <repo>/.worktrees/implementer on branch <branch> (base <base>). Work ONLY there.
Read ~/.claude/handoff/<TICKET>/plan.md fully (Amendments included)[ and review-report-<N-1>.md: fix every MUST-FIX, respond to each SHOULD-FIX (fix or justify)].
Rules: repo CLAUDE.md; TDD where the plan lists tests; run every verification command in plan.md and read the output; commit with the repo's convention; do NOT push, do NOT open a PR, do NOT touch anything outside plan.md scope — if the plan is wrong or blocked, stop and report.
Write ~/.claude/handoff/<TICKET>/impl-report-<N>.md with EXACTLY: ## Status (DONE|BLOCKED|PARTIAL) / ## Commit (10-char abbrev) / ## Changes / ## Verification / ## Deviations from plan / ## Open questions / risks.
Then SendMessage to "orchestrator" with the report path and its Status line. Nothing else.
```

4. On reply: read `impl-report-N.md`. `BLOCKED`/`PARTIAL`, or a deviation that changes the design → back to the engineer, not to the reviewer. Accepted deviations become a dated *Amendment* in `plan.md` so the reviewer judges the right spec. Take the `## Commit` value; confirm with `git -C <repo>/.worktrees/implementer rev-parse --short=10 HEAD`.

## Phase 2 — Review (`reviewer`, clean, exact commit)

1. Worktree at the exact commit: `setup-worktree.sh <repo> reviewer --commit <sha>`.
2. **Recycle** (never reuse, never a second one): `recycle-peer.sh reviewer --repo <repo>` (add `--model <strongest>` only if the session default is not the strongest). If the existing `reviewer` is a tab the engineer opened themselves, tell them the recycle will close it (ask once). Wait ~25 s, `ListAgents` must list `reviewer`; if `SendMessage` says unreachable, wait 10 s and retry once, then check `tmux -L handoff capture-pane -p -t handoff:reviewer`.
3. Write the brief to `inbox/reviewer/brief-N.md`, then `SendMessage` it. It references **only** `plan.md`, the commit and the test commands — never `impl-report-N.md`, never the implementer's message or your paraphrase of it, never a prior `review-report`.

```
[DEV handoff] You are the REVIEWER for <TICKET> (review round <N>). Fresh eyes: you have NOT seen how this was implemented and must not read the author's notes or reports.
Worktree: <repo>/.worktrees/reviewer, detached at commit <sha> (verify: git rev-parse --short=10 HEAD). Base: <base>. Spec: ~/.claude/handoff/<TICKET>/plan.md (Amendments included) — read nothing else in that directory.
Do: (1) run ONLY these test commands, one each: <list from plan.md>; do NOT run lint, build, or the full suite. (2) `code-review` skill on `git diff <base>...<sha>` at high effort — static, no full suite. (3) every acceptance criterion in plan.md vs the diff — spec compliance first, correctness second, structure third (see your role). (4) flag anything outside plan.md's scope as scope creep.
Write ~/.claude/handoff/<TICKET>/review-report-<N>.md with EXACTLY: ## Verdict (PASS|FAIL) / ## Commit / ## MUST-FIX / ## SHOULD-FIX / ## Verified OK. Terse; file:line per finding; do not modify any file.
Then SendMessage to "orchestrator" with the report path and the Verdict line. Nothing else.
```

## Phase 3 — Loop

```
impl-report-N (commit) → worktree@commit → recycle reviewer → review-N
  FAIL → implementer round N+1 (brief + review-report-N) → review round N+1 (new commit) → …
  PASS → Phase 4
```

Hard stop at **3 review rounds**: still failing → stop and bring the remaining items to the engineer. Also stop when the same MUST-FIX reappears twice (the plan, not the code, is probably wrong).

## Phase 4 — Final report, close

Write `final-report.md` and paste it in chat — shape, nothing else, ≤ ~150 words:

```
**<TICKET> — <one-line outcome>**  (branch `<branch>` @ <sha>, N impl rounds / M review rounds, review: PASS)
**Changed:** 3–6 bullets, file-level, what and why
**Verified:** commands + result
**Review notes accepted as-is:** SHOULD-FIX items deliberately not done, with the reason
**Next:** push / PR / deploy — what the engineer must decide (you did not do it, unless delegated)
```

Then `close-handoff.sh --repo <repo>` (add `--remove-worktrees` when the branch is pushed and the engineer agrees). Push/PR only if the engineer delegated them explicitly.

## Project-local rules

Repos can add `<repo>/.claude-handoff/local-engineering.md` and `local-<role>.md`; the hook appends them after the plugin's shared and role files. Use them for "only run these tests", commit conventions, forbidden directories — not for changing another role's ownership.

## Rules that are easy to rationalize away

| Temptation | Rule |
|---|---|
| "The peers aren't listed, I'll just spawn a subagent" | No. `launch-peer.sh`. Subagents are a different workflow. |
| "There's already an `implementer` but I'll launch mine anyway" | Never two peers with one name. Ask: reuse or replace (`recycle-peer.sh`). |
| "I'll launch with a bare `claude -n …`" | Use the script: env clearing, `bypassPermissions`, role file and first prompt are all required or the peer is invisible/unreachable/roleless. |
| "The implementer's summary is useful context for the reviewer" | Reviewer gets `plan.md` + commit + test list. Ever. |
| "Review the branch HEAD, it's the same thing" | Review the exact `commit:`. HEAD can move while the reviewer works. |
| "I'll just fix this small thing myself" | Orchestrator does not edit code. Back to `implementer`, even for one line. |
| "The reviewer already knows the code from round 1, reuse it" | `recycle-peer.sh reviewer` every round. Knowing the previous round is the contamination. |
| "Skip the review, the implementer ran the tests" | Tests passing ≠ spec met. The review always runs unless the engineer waives it. |
| "Let me poll / spawn something to check on the implementer" | Wait for the cross-session message. |
| "Round 4 will surely pass" | 3 rounds max. Then escalate. |
| "The report should list everything we did" | ≤150 words. Detail is in the files. |
| "Paste the plan into the message instead of writing the file" | Files are the handoff; the inbox copy is what survives a peer restart. |

## Common mistakes

- Sending to `implementer` before the engineer approved the plan.
- Using `Agent` for either role.
- Forgetting the "SendMessage to orchestrator when done" line → you never hear back.
- Reviewer worktree not moved to the new commit before a fix-round review (`setup-worktree.sh … --commit`).
- Reading `impl-report` and then writing the reviewer brief "with that in mind".
- Leaving the swarm running after the final report (`close-handoff.sh`).

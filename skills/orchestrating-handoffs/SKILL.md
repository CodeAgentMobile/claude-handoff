---
name: orchestrating-handoffs
description: Use when this session is the ORCHESTRATOR for a ticket or feature and the work must be handed to a separate implementer Claude Code session and then to a separate, clean reviewer session (peer sessions on this machine, e.g. tabs named "implementer" and "reviewer") — any task where planning, implementation and review run in different sessions/models with clean contexts between them.
---

# orchestrating-handoffs

Three **sessions**, three contexts, one baton. **You (this session, "orchestrator") never implement and never review the implementer's work** — you design, brief, relay, and decide. The other two roles are separate Claude Code sessions; you talk to them with `SendMessage`, never with `Agent`.

Each role has system instructions in this plugin's `roles/` folder (`ORCHESTRATOR.md`, `IMPLEMENTER.md`, `REVIEWER.md`). Sessions launched with `HANDOFF_ROLE=<role>` get theirs injected automatically by the plugin's SessionStart hook. **Read `roles/ORCHESTRATOR.md` now** (it is two directories above this file: `<skill dir>/../../roles/ORCHESTRATOR.md`) if this session was not started with `HANDOFF_ROLE=orchestrator`.

| Role | Where it runs | Model | Address (`SendMessage.to`) | Context |
|---|---|---|---|---|
| **Orchestrator** | this session | **the most capable model available** (Fable 5 today) | — | full conversation |
| **Implementer** | peer session named `implementer` | **the best coding model** (`opus` today) | `implementer` | receives the plan brief only |
| **Reviewer** | peer session named `reviewer` | **the most capable model available** (session default when that is the strongest — Fable 5 today; otherwise pass `--model`) | `reviewer` | receives the reviewer brief only — **never the implementer's output** |

Handoffs are **files, not chat**: every baton is a Markdown file under `~/.claude/handoff/<TICKET>/` — a **durable** location (the session scratchpad lives in `/private/tmp`, which is wiped on reboot; a laptop that overheats mid-review took `plan.md` with it once). Files make isolation enforceable — the reviewer is pointed at `plan.md` and the diff, and never receives `impl-report-N.md`.

```
~/.claude/handoff/<TICKET>/
  plan.md            # orchestrator → implementer (approved plan/spec)
  impl-report-N.md   # implementer → orchestrator (round N)
  review-report-N.md # reviewer → orchestrator (round N)
  final-report.md    # orchestrator → engineer
```

## Model policy

| Role | Model | Why |
|---|---|---|
| Orchestrator | the most capable model available (Fable 5 at the time of writing) | design, spec, judgment calls, reading reports critically |
| Implementer | the best coding model (`opus` at the time of writing) | precise, spec-bound implementation with TDD |
| Reviewer | the most capable model available (session default when that is the strongest; otherwise `--model <strongest>`) | adversarial spec-compliance + correctness review |

"At the time of writing" means: when a newer/stronger tier ships, move up — do not pin old names out of habit. The orchestrator cannot switch its own model; if this session is not on the strongest model, tell the engineer to run `/model` before Phase 0. Set the peers' models in the launch block (`MODEL=` for implementer; leave empty for reviewer only if the session default *is* the strongest, else set it).

## Phase −1 — Ensure the three sessions exist and are running

Run this at the start of every orchestration and again before each handoff (sessions get closed):

1. **Claim the orchestrator role — with confirmation.** Peers reply to the name `orchestrator`, and a session cannot rename itself (`/rename` is the engineer's command). So, on invocation:
   - `ListAgents`: if a peer named `orchestrator` is already listed, **another session holds the role** — say so and ask the engineer which one should orchestrate; do not proceed as a second orchestrator.
   - Otherwise ask one question: "This session will act as the orchestrator for <TICKET>. Confirm, run `/rename orchestrator` if the prompt box doesn't already show that name, and make sure this session is on the most capable model (`/model`)." Wait for the confirmation before anything else. (If the engineer says this session is already named `orchestrator`, take their word — you can't see your own name.)
2. `ListAgents` → "Peer sessions" must list `implementer` and `reviewer` (state `idle` or `busy`). Only *running* sessions are listed — a session that exists on disk but is closed does not count.
3. **Missing peer → launch it yourself.** Build the command once, then use **tmux** — install it with Homebrew if missing — (windows of one `handoff` session — the engineer sees all peers inside a single IDE terminal tab with `tmux attach -t handoff`), only if tmux cannot be installed (no Homebrew) fall back to a **Terminal.app** window. One `Bash` call per session; set `NAME`, `MODEL`, `REPO`; for `reviewer` drop the `--model` flag so it uses the session default:
   ```bash
   PLUGIN_ROOT=<this skill's base directory>/../..   # the claude-handoff plugin root (contains roles/ and hooks/)
   REPO=<repo>; NAME=implementer; MODEL=opus         # for reviewer: NAME=reviewer and leave MODEL empty (session default)
   ROLE_UPPER=$(printf '%s' "$NAME" | tr '[:lower:]' '[:upper:]')
   CMD="cd '$REPO' && for v in \$(env | sed -n 's/^\(CLAUDE[A-Za-z_]*\)=.*/\1/p'); do unset \$v; done && export HANDOFF_ROLE=$NAME && claude -n $NAME ${MODEL:+--model $MODEL} --permission-mode bypassPermissions --append-system-prompt-file '$PLUGIN_ROOT/roles/$ROLE_UPPER.md' 'You are the $NAME session in a multi-session workflow. Reply only: ready. Then wait for [DEV handoff] messages from the orchestrator and follow them exactly.'"
   command -v tmux >/dev/null || (command -v brew >/dev/null && brew install tmux)   # tmux missing → install it (macOS/Homebrew), then use it
   if command -v tmux >/dev/null; then
     tmux has-session -t handoff 2>/dev/null && tmux new-window -t handoff -n "$NAME" "$CMD" || tmux new-session -d -s handoff -n "$NAME" "$CMD"
   else   # no tmux and no brew → Terminal.app window (macOS)
     osascript -e "tell application \"Terminal\" to do script \"$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')\""
   fi
   ```
   - **tmux mode:** the first time, tell the engineer once: "Peers run in tmux session `handoff` — open an IDE terminal tab and run `tmux attach -t handoff` (Ctrl-b n / Ctrl-b <number> to switch between windows, Ctrl-b d to detach)." Inspect a peer with `tmux capture-pane -p -t handoff:<name>`; kill one with `tmux kill-window -t handoff:<name>`. `ListAgents` shows the tmux location (`tmux handoff:@N.%M`) next to each peer.
   - **Terminal.app mode:** inspect with `osascript -e 'tell application "Terminal" to get contents of tab 1 of front window'`; kill with `pkill -f "claude -n <name>"` + `osascript -e 'tell application "Terminal" to close (every window whose name contains "<name>")'`.
   - IDE-integrated terminal tabs (WebStorm/VS Code/Cursor) cannot be created from the CLI — that is why tmux is the way to get "tabs inside the IDE".

   Every piece of `CMD` is load-bearing (verified on macOS, Claude Code 2.1.x):
   - `for v in $(env | sed …); do unset $v; done` — a shell spawned from inside a Claude session inherits `CLAUDE_*` env vars; with them set the new session becomes a *child* session (no transcript, invisible to `ListAgents`, unreachable by `SendMessage`).
   - `cd '$REPO'` — trusted folder, so no trust prompt blocks startup.
   - `--permission-mode bypassPermissions` — the only mode that delivers cross-session messages without a manual "Deliver" click (`manual`, `acceptEdits`, `auto` all hold them for approval). This is the engineer's standing choice for peers; if they want a stricter mode they must approve every held message by hand — say so.
   - `export HANDOFF_ROLE=$NAME` + `--append-system-prompt-file roles/<ROLE>.md` — the role instructions reach the session two ways: the plugin's SessionStart hook injects `roles/<ROLE>.md` when `HANDOFF_ROLE` is set, and the flag appends the same file to the system prompt (works even if the hook is not installed).
   - the trailing quoted prompt — the session must complete one turn before it registers as a peer.
   - `--resume <session-id>` may be added to re-attach a previous session (ids from the `claude --resume` picker) — only when the engineer explicitly wants the old context back; **the reviewer is always fresh**, and the implementer is fresh unless the engineer says otherwise.
4. Wait ~20–30 s (`Bash`: `until pgrep -f "claude -n $NAME" >/dev/null; do sleep 1; done; sleep 25`), then `ListAgents` again. Not listed → inspect the pane/window (commands above), tell the engineer what it shows, and stop; never send briefs to a session that isn't listed. If `SendMessage` says the peer is unreachable right after it was listed, wait 10 s and retry once.
5. **Never fall back to spawning subagents** (`Agent`) for these roles — that is a different workflow.

## Mechanics (read once)

- **Discover peers:** `ListAgents` (see Phase −1).
- **Send:** `SendMessage({ to: "implementer", summary: "...", message: <brief> })`. Send the bare name; append the `[ref]` only if `ListAgents` shows two rows with the same name.
- **Receive:** peers reply with `SendMessage({ to: "orchestrator", ... })`; it arrives here as `<cross-session-message from="implementer">`. Every brief must end with that instruction, otherwise you never hear back.
- **Wait, don't poll:** after sending, stop and tell the engineer you're waiting; the reply arrives as a message. Do not spawn anything to "check".
- **Permission boundaries are per session:** never ask a peer to do something your session was denied or that you know its permissions would block.
- **Peer session state persists across rounds.** A session cannot `/clear` itself and you cannot clear it for it — so the reviewer is **recycled** (killed + relaunched fresh) before every review round; see Phase 2 step 1. Isolation is then guaranteed by a truly empty context plus *what you send*.

## Phase 0 — Design (Orchestrator only)

All shaping, spec and planning happen here, before anything is sent. Use whatever ticket/planning skills you have (e.g. a ticket-loading skill, `superpowers:brainstorming` for fuzzy ideas, `superpowers:writing-plans` for the plan) — or plain careful reading of the ticket and the code. **Nothing is sent to `implementer` until the engineer has approved the plan.** Write the approved plan to `plan.md` — the single spec every role reads.

`plan.md` must contain: goal · ticket link · acceptance criteria · exact files/functions to touch · tests that prove each criterion · verification commands (list the `jest` test commands first and separately from lint/build — the reviewer runs only the tests) · out-of-scope list · branch name + base branch · commit convention · handoff dir path.

## Phase 1 — Implement (`implementer` session)

`SendMessage` to `implementer` with this brief (fill the placeholders; do not paste the conversation):

```
[DEV handoff] You are the IMPLEMENTER for <TICKET>.
Read ~/.claude/handoff/<TICKET>/plan.md and implement it exactly, in repo <path>, on branch <branch> (create from <base> if missing).
Rules: follow repo CLAUDE.md; TDD where the plan lists tests; run the verification commands in plan.md and read the output; commit on the work branch with the repo's convention; do NOT push, do NOT open a PR, do NOT touch anything outside plan.md scope — if the plan is wrong or blocked, stop and report instead of improvising.
When done, write ~/.claude/handoff/<TICKET>/impl-report-<N>.md with EXACTLY these sections:
## Status  (DONE | BLOCKED | PARTIAL)
## Changes (file → what changed, one line each)
## Verification (each command run + pass/fail + key output lines)
## Deviations from plan (or "none")
## Open questions / risks
Then SendMessage to "orchestrator" with the report path and its Status line. Nothing else in the message.
```

Fix rounds (N ≥ 2) add: "Also read `review-report-<N-1>.md`; fix every MUST-FIX, respond to each SHOULD-FIX (fix or justify), and list each review item and what you did in the report."

On reply: read `impl-report-N.md`. `BLOCKED`/`PARTIAL`, or a deviation that changes the design → back to the engineer, not to the reviewer.

## Phase 2 — Review (`reviewer` session, clean)

1. **Recycle the reviewer — automatically, no engineer action.** Terminate any running `reviewer` session and relaunch a fresh one with the Phase −1 launch block (`NAME=reviewer`, no `--model`):
   ```bash
   tmux kill-window -t handoff:reviewer 2>/dev/null; pkill -f "claude -n reviewer"; osascript -e 'tell application "Terminal" to close (every window whose name contains "reviewer")' 2>/dev/null
   # then the Phase −1 launch block with NAME=reviewer (no --model), wait ~30 s, confirm with ListAgents
   ```
   If the engineer opened their own reviewer tab (e.g. in the IDE) instead of one you launched, ask once whether you may take it over (the kill closes their tab's process) — otherwise launch yours and leave theirs alone. Only send to a `reviewer` that `ListAgents` currently lists; if `SendMessage` says it is unreachable, wait 10 s and retry once, then re-check the process (`pgrep -f "claude -n reviewer"`) — a session whose window was closed must be relaunched.
2. `SendMessage` to `reviewer` with this brief. It references **only** `plan.md` and the diff — not `impl-report-N.md`, not the implementer's message, not your paraphrase of it.

```
[DEV handoff] You are the REVIEWER for <TICKET>. Fresh eyes: you have NOT seen how this was implemented and must not go looking for the author's notes or reports.
Inputs: repo <path>, branch <branch> vs <base>, spec at ~/.claude/handoff/<TICKET>/plan.md.
Do: (1) run ONLY the test commands listed in plan.md (the `jest` specs — do NOT run lint, build, or the full test suite; the implementer already ran those) and read the output; (2) run the `code-review` skill on the branch diff (`git diff <base>...HEAD`) at high effort; (3) check every acceptance criterion in plan.md against the diff — spec compliance first, code quality second; (4) flag anything in the diff that touches files or behaviour NOT listed in plan.md's scope — unlisted changes are scope creep to justify or revert, not a bonus.
Write ~/.claude/handoff/<TICKET>/review-report-<N>.md with EXACTLY these sections:
## Verdict  (PASS | FAIL)
## MUST-FIX  (bugs, spec gaps, failing checks — file:line + one-line reason each)
## SHOULD-FIX (quality/simplification — same format)
## Verified OK (which acceptance criteria you confirmed and how)
Be terse. No praise, no restating the diff. Do not modify any file in the repo.
Then SendMessage to "orchestrator" with the report path and the Verdict line. Nothing else in the message.
```

Never send the reviewer a `review-report` from a prior round — each round is a clean review of the current diff.

## Phase 3 — Loop

```
impl-report-N → (recycle reviewer) → review-N → verdict
  FAIL → implementer round N+1 with review-report-N → review round N+1 → …
  PASS → Phase 4
```

Hard stop at **3 review rounds**: still failing → stop and bring the remaining items to the engineer. Also stop when the same MUST-FIX reappears twice (the plan, not the code, is probably wrong).

## Phase 4 — Final report (Orchestrator → engineer)

Write `final-report.md` and paste it in chat. Shape — nothing else:

```
**<TICKET> — <one-line outcome>**  (branch `<branch>`, N impl rounds / M review rounds, review: PASS)
**Changed:** 3–6 bullets, file-level, what and why
**Verified:** commands + result (tests X passed, lint clean, build ok)
**Review notes accepted as-is:** SHOULD-FIX items deliberately not done, with the reason
**Next:** push / open PR / deploy — whatever the engineer must decide (you did not do it)
```

Under ~150 words. Details live in the handoff files — link them, don't inline them.

## Rules that are easy to rationalize away

| Temptation | Rule |
|---|---|
| "The peers aren't listed, I'll just spawn a subagent" | No. Launch the session with the Phase −1 launch block. Subagents are a different workflow. |
| "I'll launch the peer with a bare `claude -n …`" | Use the full launch block: without clearing `CLAUDE_*` env vars the session becomes an invisible child; without `bypassPermissions` every message is held for manual approval. |
| "The implementer's summary is useful context for the reviewer" | The reviewer gets `plan.md` + diff only. Ever. |
| "I'll just fix this small thing myself" | Orchestrator does not edit code. Send it back to `implementer`, even for one line. |
| "The reviewer already has the code in context from round 1, reuse it" | Recycle it every round. Knowing the previous round is the contamination. |
| "Skip the review, the implementer ran the tests" | Tests passing ≠ spec met. The review always runs unless the engineer explicitly waives it. |
| "Let me poll / spawn something to see if the implementer is done" | Wait for the cross-session message. |
| "Round 4 will surely pass" | 3 rounds max. Then escalate. |
| "The report should list everything we did" | Final report ≤ ~150 words. Detail is in the files. |
| "Paste the plan into the message instead of writing the file" | Files are the handoff. Messages carry paths and one status line. |

## Common mistakes

- Sending to `implementer` before the engineer approved the plan.
- Using `Agent` (subagent) for either role — the roles are peer *sessions*; use `SendMessage`.
- Forgetting the "SendMessage to orchestrator when done" line in a brief → you never get the reply.
- Sending the reviewer brief to a session that was not recycled for this round.
- Reading `impl-report` and then writing the reviewer brief "with that in mind" — write it from `plan.md` only.
- Letting the implementer push or open the PR. Outward actions stay with the engineer.

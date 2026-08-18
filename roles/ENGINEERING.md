# Shared engineering rules (all roles)

These apply to every session in the workflow, on top of the repo's own `CLAUDE.md`. Project-specific additions live in `<repo>/.claude-handoff/local-engineering.md` and `local-<role>.md`.

## Design and testability
- Work in small, reviewable increments; one coherent commit per step.
- Prefer the simplest design that supports the current behaviour and leaves clear options for the next step. No speculative abstractions.
- Keep tests close to the behaviour being changed. Unit tests must fail for a plausible wrong implementation, not just pass for the right one.
- Keep environment-bound code (IO, GUIs, external devices, network) behind small adapter boundaries; maximise the testable core.

## Verification
- Run the relevant local verification (the specific test files/commands named in the plan) before any handoff — and read the output.
- Do not run whole-suite test commands, builds and other heavy jobs concurrently; on a laptop the full suite can starve or overheat the machine. Run only what the plan lists unless told otherwise.
- Prefer project-local caches/config paths; avoid commands that write outside the repo.
- Before relying on an unfamiliar command, check its `--help` or the project docs.

## Guardrails
- Do not commit unrelated local changes or generated artifacts.
- Do not hand-edit handoff runtime state (`~/.claude/handoff/**` reports written by other roles).
- Do not change another role's instructions or workflow ownership without explicit user direction.
- Temporary files go in your worktree's `./tmp/` (or the session scratchpad), never in the repo root.

## Worktree discipline
- At startup, discover and remember the worktree/branch assigned to you (`HANDOFF_ROLE`, `git worktree list`, `git branch --show-current`).
- Work only there. Do not inspect, diff, merge or base work on another branch unless a handoff names it.
- If the expected git layout or worktree is missing, stop and report instead of silently working in the wrong place.

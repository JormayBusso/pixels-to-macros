---
name: delegate
description: Dispatch pending todos from the active plan-*.md file to sub-agents via the task tool and record delegation results. Runs automatically as the second phase right after `plan` finishes (part of the PLAN loop chain) — the user does not need to type "delegate". Can also be invoked directly if the user explicitly asks to assign/hand off todos from an existing plan.
---

# Delegate

Second phase of the plan → delegate → assess → codify loop. Reads the
active plan file, dispatches each `pending` todo to a sub-agent, and writes
results back into the same file.

Note: once a loop has been started with the uppercase `PLAN` trigger, this
phase runs automatically — it is invoked by `plan` itself (or by `assess`
looping back after a revision), not by the user typing "delegate".

## Find the plan

- Use the most-recently-modified `files/plan-*.md` in the session workspace
  unless the user names a specific file.
- If no plan file exists, tell the user to run `plan` first — do not
  invent todos.

## Execution mode

- **Sync by default.** Only use a background agent (task tool
  `mode: "background"`) when a todo is genuinely long-running or multiple
  `pending` todos are independent of each other and can run in true
  parallel. This mirrors the parent agent's own task-tool guidance — do not
  default to background just because it's available.
- One sub-agent invocation per todo. Give the sub-agent the todo's full
  Description and Acceptance Criteria verbatim as context — sub-agents are
  stateless and only see what you give them.
- Prefer `general-purpose` agent type unless a todo clearly fits a more
  specialized agent (e.g. `code-review` for a review-only todo).
- Model tier selection is independent of sync/background mode: choose mode
  only using the criteria above.

## Model routing

Read each todo's `Risk:` and `Recommended Delegate Model:` fields before
dispatching. Use the plan's recommendation when it is set and consistent with
the routing below; otherwise select the tier as follows:

| Todo risk and work type | Delegate tier | Effort |
| --- | --- | --- |
| LOW and clearly mechanical (docs, comments, formatting, simple test edits, trivial config edits, commit/changelog drafts) | cheap | low |
| LOW but changes runtime code behavior | standard | medium |
| MEDIUM | standard | medium |
| HIGH | strong | high |

- **Cheap tier:** `gpt-5.6-luna` at low effort; if unavailable, use
  `gemini-3.6-flash` at low effort, or `claude-haiku-4.5` (no effort
  parameter — invoke it without one).
- **Standard tier:** `gpt-5.6-terra` at medium effort; if unavailable, use
  `gpt-5.5` or `gpt-5.4` at medium effort.
- **Strong tier:** `claude-opus-4.8` at high effort; if unavailable, use
  `claude-opus-4.7` or `claude-sonnet-5` at high effort.

Follow the `plan` skill's Model tiers environment fallback rule: fall back to
the closest available tier rather than failing because a named model is
unavailable. Never default to flagship models such as `claude-opus-5` or
`gpt-5.6-sol`.

## Automatic escalation

- **Cheap → standard:** escalate during the task when it affects runtime
  behavior, the first attempt fails tests/typecheck/lint, repository patterns
  are unclear, more than one iteration is required, or a nontrivial logic
  issue or ambiguity is identified.
- **Standard → strong:** escalate when the task is reclassified HIGH (update
  the todo's `Risk:` field and record this in the Routing Log), it touches
  security, auth, payment, data migration, infrastructure, public API,
  concurrency, or destructive behavior; two focused implementation attempts
  fail; the solution needs a non-obvious design decision; or test failures
  indicate a deep or cross-module issue.

Record every escalation in the todo's `Routing Log:` with the tier before and
after and the reason.

## Delegate rules

- Before implementation, read the todo, its acceptance criteria, relevant
  files, and existing nearby tests. Implement only the approved scope.
- Run required focused checks, preferring deterministic evidence—tests, lint,
  typecheck, build, and `git diff`—over model reasoning wherever possible, in
  accordance with the project's existing `AGENTS.md` validation conventions.
- Do not claim success without reporting the actual commands run and concise
  results. Return a concise handoff with files changed, behavior implemented,
  tests/checks run and results, known limitations or uncertainties, and an
  exact diff summary.
- Do not modify lockfiles, generated files, dependencies, CI, infrastructure,
  or unrelated code unless they are explicitly included in the todo scope.
- If requirements become ambiguous after work begins, do not guess. Stop, set
  `Status: blocked`, record the open question, and let it return to `plan` for
  revision rather than improvising a design decision.

## What to update per todo after dispatch

In the todo's block in `plan-*.md`:

```md
- Status: delegated
- Delegation: agent=<agent name/id>; mode=sync|background;
  model=<tier>(<model-name>); model_reason=<why this tier>; result=<one-line
  summary of what the sub-agent did/changed>
```

- If a todo fails outright at delegation time (sub-agent errors, can't
  complete), set `Status: failed` and record the reason in Delegation notes
  instead of Assessment (assess hasn't run yet).
- Do not mark a todo `assessed` or `codified` here — that's not this
  skill's job.
- Only touch todos currently `Status: pending`. Leave `delegated`,
  `assessed`, `failed`, `blocked`, and `codified` todos untouched. In
  particular, skip `blocked` todos; a `failed` or `blocked` todo becomes
  `pending` again only via the `plan` skill's revise mode.

## After delegating

- Summarize, per todo: what was delegated, to what mode, and the outcome.
- If any todos were delegated in background mode, wait for their completion
  notifications first (per normal background-agent handling) — do not
  invoke `assess` on a todo whose background agent hasn't finished yet.
- Once every delegated todo's result is in hand, do not stop and wait for
  the user — immediately continue the loop yourself by invoking `assess`
  next. Tell the user you're proceeding straight to `assess`.
---
name: plan
description: Break a task into a written todo plan with acceptance criteria, stored as a markdown file, as the first step of the plan -> delegate -> assess -> codify loop. Use ONLY when the user types the exact uppercase word "PLAN" (case-sensitive) as a standalone trigger, or to revise a failed todo when assess sends work back. Do NOT trigger on lowercase "plan" or other casual plan-related phrasing.
---

# Plan

First phase of the plan → delegate → assess → codify loop. Produces (or
revises) the single markdown artifact the other three skills read and
mutate.

## Model tiers

- **Cheap tier:** Prefer `gpt-5.6-luna` at low effort for simple,
  low-cost work. If it is unavailable in this environment, use the closest
  available low-cost/fast model, such as `gemini-3.6-flash` or
  `claude-haiku-4.5`, at low effort. Fall back to the closest available tier;
  never fail merely because a named model is not configured.
- **Standard tier:** Use `gpt-5.6-terra` at medium effort for normal work.
  If unavailable, fall back to `gpt-5.5` or `gpt-5.4` at medium effort, or
  the closest available standard-tier model; never fail due to an unavailable
  model name.
- **Strong tier:** Use `claude-opus-4.8` at high effort for high-risk or
  complex work. If unavailable, fall back to `claude-opus-4.7` or
  `claude-sonnet-5` at high effort, or the closest available strong-tier
  model; never fail due to an unavailable model name.

Never use the most expensive/flagship tier (for example, `claude-opus-5` or
`gpt-5.6-sol`) as a default in this loop. Reserve it only for an explicit
manual user escalation outside normal routing.

## Trigger rule (case-sensitive)

- This skill starts a brand-new loop ONLY when the user's message contains
  the exact uppercase token `PLAN` (e.g. "PLAN this task", "PLAN: <goal>").
  Lowercase `plan`, `Plan`, or other casual phrasing ("can you plan this",
  "let's plan out...") must NOT trigger this skill — treat those as normal
  conversation instead.
- The one exception: revise mode (below) is still entered automatically
  after a `failed` todo is reported by `assess`, without the user needing to
  type `PLAN` again, since that is a continuation of a loop already started
  with `PLAN`.

## File location & naming

- Session workspace: `files/plan-<YYYY-MM-DD>.md` (use the current date; if a
  file for today already exists and is still active, append a short suffix,
  e.g. `plan-2026-08-05-2.md`, rather than overwriting it).
- Multiple loops can coexist as separate timestamped files. Other skills
  (delegate/assess/codify) always act on the most-recently-modified
  `plan-*.md` unless the user names a specific file.

## Two modes

1. **New plan** (default): no relevant active plan file exists, or the user
   is clearly describing a new task. Create a fresh `plan-<date>.md`.
2. **Revise mode**: the most-recently-modified `plan-*.md` has one or more
   todos with `Status: failed`. Open that same file and revise only the
   failed todo(s) — rewrite their Description/Acceptance Criteria based on
   the failure reason left by `assess`, reset `Status: pending`, reset Risk
   and Recommended-Model fields if the revision changes scope or risk, and
   clear stale Delegation/Assessment notes for that todo. Do not touch todos
   that are `delegated`, `assessed`, or `codified`.

## Risk classification

- **LOW:** documentation or comments; formatting; renaming with
  language-server support; straightforward test updates; simple configuration
  changes with clear existing patterns; small mechanical code edits with
  explicit acceptance criteria; commit message or changelog wording.
- **MEDIUM:** a focused bug fix; a small feature in an established module;
  business logic with clear expected behavior; internal refactoring with
  tests; API client changes that do not alter public contracts; changes
  requiring several related files but no security, data, or infrastructure
  impact.
- **HIGH:** authentication, authorization, permissions, secrets, encryption,
  or security controls; payments, billing, financial calculations,
  legal/compliance behavior; database schema/data migrations, destructive data
  changes, or retention; production infrastructure, CI/CD, deployment, IaC,
  or environment permissions; concurrency, distributed systems, caching
  correctness, race conditions; public API, SDK, backward compatibility, or
  major dependency upgrades; complex algorithms or changes difficult to test
  or verify; unclear requirements with significant user/business impact; a
  prior delegate or assessor failure.

Default upward if uncertain: classify as **MEDIUM** when uncertain, or
**HIGH** specifically when the uncertainty concerns security, data, or
production impact.

## Required file structure

```md
# Plan: <short title>
Created: <date>
Status: active

## Goal
<1-3 sentences: what done looks like for the whole loop>

## Todos

### [ ] <todo-id>: <short title>
- Status: pending
- Risk: LOW|MEDIUM|HIGH (set by plan)
- Recommended Delegate Model: <tier> (set by plan, per PLAN-phase routing rules)
- Recommended Assess Model: <tier> (set by plan, per PLAN-phase routing rules)
- Description: <what to do, concrete enough to hand to a sub-agent with no
  further context>
- Acceptance Criteria: <concrete, checkable conditions — assess will check
  these literally>
- Delegation: (empty until delegate runs)
- Assessment: (empty until assess runs)
- Codify: (empty until codify runs)
- Routing Log: (empty until delegate runs; a short machine-readable line
  updated by delegate/assess/codify as the todo progresses)
```

- Valid statuses are `pending`, `delegated`, `assessed`, `failed`, `blocked`,
  and `codified`. When a todo has unresolved design questions, plan must set
  `Status: blocked` rather than leaving it delegatable, and record the open
  question in Description or a `Blocked Reason:` field. Delegate must skip
  blocked todos. A blocked todo becomes `pending` again only through a plan
  revision that resolves its question, mirroring the `failed` → revise →
  `pending` pattern.
- The Routing Log must capture the risk level, model tier actually used per
  phase, the reason for that tier (including escalation reasons), commands run
  and their pass/fail result, and the assess decision. For example:
  `Routing Log: risk=MEDIUM; delegate_model=standard(gpt-5.6-terra); delegate_reason=established module fix; checks=pytest tests/test_x.py=pass; assess_model=standard(gpt-5.6-terra); assess_decision=PASS`
- Use kebab-case todo-ids, descriptive (not `t1`, `t2`).
- Break the goal into the smallest set of todos that are each independently
  delegatable and independently checkable. Avoid one giant todo.
- Acceptance Criteria must be concrete and testable (e.g. "new endpoint
  returns 404 for missing id" not "handle errors well").
- Do not add a Codify/commit todo — codify handles that automatically per
  assessed todo.

## PLAN-phase model routing

PLAN itself—the model that produces or revises the plan file—uses the standard
tier at medium effort by default for LOW and MEDIUM overall task complexity.
Escalate PLAN itself to the strong tier at high effort only when the overall
requested task is clearly HIGH risk or complex according to the classification
above.

- Do not use the strong tier for simple plans.
- Do not inspect unrelated code while planning.
- Prefer existing repository conventions and tests as evidence.
- Produce a concise plan, not an essay.

Split work until each todo is independently implementable and testable. Do not
combine refactoring, behavior changes, and migration work in one todo unless
unavoidable. Mark a todo `blocked` rather than delegating it if it has
unresolved design questions.

## After writing/revising the file

- Tell the user the file path and a one-line summary of the todos (or, in
  revise mode, which todo(s) were revised and why), including each new todo's
  risk level.
- Immediately continue the loop yourself: invoke `delegate` next in the same
  turn without waiting for the user to type anything. The full
  `delegate → assess → codify` chain runs automatically once `PLAN` has
  kicked off the loop — the user never needs to type those three names.
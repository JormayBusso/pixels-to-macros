---
name: plan
description: Break a task into a written todo plan with acceptance criteria, stored as a markdown file, as the first step of the plan -> delegate -> assess -> codify loop. Use ONLY when the user types the exact uppercase word "PLAN" (case-sensitive) as a standalone trigger, or to revise a failed todo when assess sends work back. Do NOT trigger on lowercase "plan" or other casual plan-related phrasing.
---

# Plan

First phase of the plan → delegate → assess → codify loop. Produces (or
revises) the single markdown artifact the other three skills read and
mutate.

## Model tiers

Single source of truth for model choice in this loop; `delegate`, `assess`,
and `codify` reference this table. Prices are Copilot input/output units
(Oct 2026).

| Tier | Role | Model (effort) | Price | Fallback |
| --- | --- | --- | --- | --- |
| cheap | any | `claude-haiku-5.5` (low) | 10/50 | `gpt-6-luna` (low) |
| standard | **implement** (delegate) | `claude-sonnet-5.5` (medium) | 200/1000 | `gpt-6.1-sol` (medium) |
| standard | **reason** (plan, assess) | `gpt-6.1-sol` (medium) | 200/1000 | `claude-sonnet-5.5` (medium) |
| strong | any | `claude-opus-5.5` (high) | 400/2000 | `gpt-6.1-sol` (xhigh) |

Why these (BenchLM, Artificial Analysis, DataCamp, explainx.ai — Oct 2026):

- **Standard is split by role.** Sonnet 5.5 and GPT-6.1 Sol cost the same.
  Sonnet 5.5 is #1 on coding (BenchLM coding 84 vs 71; Bug Hunt 51 vs 44
  fixes; AA Intelligence Index 56 vs 51.8), so it writes the code. GPT-6.1
  Sol leads on reasoning (ARC-AGI), rejects bad inputs rather than caveating
  them, and has half-price cache reads, so it plans and assesses. Assessing
  with a different vendor than the implementer is a deliberate
  **cross-check**: one model's blind spots get reviewed by another.
- **Strong is Opus 5.5.** It beats Opus 5 and Opus 4.8 on every shared
  benchmark (SWE-bench Pro 89.9% vs 79.2% vs 69.2%) at a lower price.
- **Cheap is Haiku 5.5.** It costs the same as GPT-6 Luna, edges it on coding,
  and Luna showed coding regressions after its reprice.

Off-roster (dominated — a same-or-cheaper roster model is better): Opus 4.8,
Opus 5, Sonnet 5, GPT-6 Sol (superseded by 6.1 Sol at the same price),
GPT-5.6 Sol/Terra/Luna, GPT-5.3-Codex, MAI-Code-1.1-Flash. `gemini-3.8-flash`
(75/375) is a last-resort cheap fallback only.

If a named model is unavailable, use its listed fallback, then the closest
available model of the same tier; never fail because a model name is not
configured. The top-priced models (Opus 5, Opus 4.8) are never used — Opus
5.5 is both stronger and cheaper.

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

## Step 0 — Improve the prompt (before researching or decomposing)

Whenever the user gives a prompt (the text after `PLAN`, or the failure
reason on a revise-mode re-entry), improve it using modern prompt-engineering
principles before doing any research or decomposition. **Do not blindly apply
a fixed template.** Add structure only when it improves clarity, accuracy,
consistency, or usefulness.

Analyze the prompt and, when relevant, incorporate:
- **Task** — clearly define what the AI needs to accomplish using specific
  action verbs.
- **Context** — relevant background, environment, data, and assumptions that
  materially affect the task (this repo's stack, relevant AGENTS.md sections,
  affected files/modules, the LiDAR/non-LiDAR split when applicable).
- **Requirements and Constraints** — technical, functional, compatibility,
  safety, or scope requirements, including what must be avoided.
- **Success Criteria** — what a successful result should accomplish and, where
  useful, how it can be evaluated.
- **Output Format** — the desired structure, format, schema, level of detail,
  or presentation.
- **Examples** — few-shot examples only when they would clarify the desired
  behavior or output. Do not add examples unnecessarily.
- **Role** — an appropriate role or perspective only when it provides
  meaningful value. Do not use exaggerated credentials or unnecessary persona
  descriptions.

Follow these principles:
- Prioritize clarity and specificity over unnecessary length.
- Include enough context to remove meaningful ambiguity, but do not add
  irrelevant information.
- Do not assume that a longer prompt produces a better result.
- Do not invent missing requirements, facts, data, or constraints. Clearly
  identify important missing information instead.
- Resolve contradictions in the original prompt where possible, and flag them
  when they cannot safely be resolved.
- Preserve the user's actual intent.
- Do not add unnecessary introductory text, motivational language, or generic
  prompt-engineering terminology.
- If the original prompt is already good, make only the changes that
  materially improve it.
- For complex tasks, make the prompt explicit about evaluation criteria and
  expected deliverables.
- If the task requires structured or machine-readable output, make the
  required structure explicit and unambiguous.
- Optimize the prompt for this task rather than forcing every prompt into the
  same structure.

Write the result into the plan file under a `## Improved Prompt` section (see
the required file structure below), with these parts:
- **Improved Prompt** — the complete optimized prompt, ready to use as the
  basis for research and decomposition.
- **What Changed** — briefly list the most important improvements and why
  they were made.
- **Missing Information** — only include this if important information is
  genuinely missing; omit the part entirely otherwise.

Then use the Improved Prompt — not the raw request — as the basis for
research (below) and for decomposing todos.

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
   that are `delegated`, `assessed`, or `codified`. Leave the file's existing
   `## Improved Prompt` section as-is unless the failure reason reveals the
   original task/constraints were themselves wrong — only then re-run Step 0
   for the affected part and update that section.

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

## Improved Prompt
<the complete optimized prompt>

### What Changed
<the most important improvements and why they were made>

### Missing Information
<only present if important information is genuinely missing; omit this
subsection entirely otherwise>

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
  `Routing Log: risk=MEDIUM; delegate_model=standard(claude-sonnet-5.5); delegate_reason=established module fix; checks=flutter test test/x_test.dart=pass; assess_model=standard(gpt-6.1-sol); assess_decision=PASS`
- Use kebab-case todo-ids, descriptive (not `t1`, `t2`).
- Break the goal into the smallest set of todos that are each independently
  delegatable and independently checkable. Avoid one giant todo.
- Acceptance Criteria must be concrete and testable (e.g. "new endpoint
  returns 404 for missing id" not "handle errors well").
- Do not add a Codify/commit todo — codify handles that automatically per
  assessed todo.

## PLAN-phase model routing

PLAN itself—the model that produces or revises the plan file—uses the standard
**reason** model (`gpt-6.1-sol`) at medium effort by default for LOW and
MEDIUM overall task complexity.
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

- Tell the user the file path, the Improved Prompt (or a concise summary of
  it) plus its What Changed / Missing Information notes so they can
  sanity-check the interpretation, and a one-line summary of the todos (or,
  in revise mode, which todo(s) were revised and why), including each new
  todo's risk level.
- Immediately continue the loop yourself: invoke `delegate` next in the same
  turn without waiting for the user to type anything. The full
  `delegate → assess → codify` chain runs automatically once `PLAN` has
  kicked off the loop — the user never needs to type those three names.
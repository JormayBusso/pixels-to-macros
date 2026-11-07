---
name: plan-loop
description: PLAN runs a verification-first delivery loop with difficulty-based tiers and selective delegation. Also use when explicitly requested.
---

# Plan Loop

**Understand -> Implement -> Verify -> Deliver.** Trigger: standalone uppercase
`PLAN`, not lowercase "plan". Research, recommendation, and plan-only requests
end with that deliverable; implementation requires implementation intent.

## Fast path

For one bounded LOW-risk change: establish criteria, edit, run required checks,
and report directly. Skip phase-file loads, plan artifacts, SQL bookkeeping,
and extra agents unless complexity or missing evidence requires them.
Repository instructions, authorization, and deployment requirements still apply.

## Token discipline

- One owner per coupled change. Delegate only substantial separable work that
  warrants its own context or independent judgment; parallel tools come first.
- Load only the active phase and needed references, once. Search scoped files
  and identifiers, batch independent reads, and request bounded output.
- Reuse verified research and worker findings. Investigate only decision-relevant
  gaps; stop searching when the contract and implementation are supported.
- Worker prompt: objective/IDs, paths, constraints, criteria/checks, stopping
  condition. Omit unrelated history. Handoff: verdict, changes, evidence, blockers;
  aim for 100 words on success, expand only for necessary failure detail.
- Save verbose logs outside the conversation; return exit codes and useful
  excerpts. Recover missing detail from those logs rather than rerunning work.
- Background agents need independent foreground work. Read known results after
  completion notification, without polling. Retain same-task context for repairs.
- Reuse valid check evidence under Verify. Stop after required criteria pass:
  no speculative cleanup, coverage chasing, redundant reviewers, or full-suite
  repetition without a new requirement, relevant change, or unresolved failure.

## Difficulty and model tiers

Difficulty is reasoning complexity; risk is the consequence of error. Choose per
objective, not phase. Routine command execution does not need strong reasoning.

| Tier | Difficulty | Preferred models | Starting effort |
| --- | --- | --- | --- |
| cheap | EASY: bounded lookup, mechanical edit, routine commands | `claude-haiku-5.5` up to 100K prompt tokens; `gpt-6-luna` above that only if quality is sufficient | low |
| standard | MODERATE: established-module change, testable contract | `gpt-6.1-terra` for bounded work; `gpt-6.1-sol` for demanding work; `claude-sonnet-5.5` when task-specific evidence favors it | medium |
| strong | HARD: novel algorithms, cross-module design, subtle correctness or substantial HIGH-risk reasoning | `claude-opus-5.5` | high |

Honor configured model/effort defaults; task overrides require explicit current
request or applicable user instructions. This table alone is not authorization.
For authorized selection, check availability once and respect explicit constraints
on fallbacks. Start difficult work at its tier; raise effort only for demonstrated
need, not a leaderboard's maximum setting.

**Dominance:** exclude demonstrably weaker choices at equal or lower expected
whole-task cost under the same quality/context/modality/latency constraints.
Include cache reads/writes, reasoning/output tokens, retries, and context repricing;
neither vendor diversity nor an aggregate score proves task-level superiority.
For prompts above 100K, alternative models, repricing, or ranking questions,
read [cost/evidence](plan/SKILL%202.md); otherwise use the table without re-research.

Risk: LOW mechanical; MEDIUM established-module behavior; HIGH security, payments,
data/migrations, production permissions, concurrency, public contracts, or hard-to-
verify algorithms (including scans). Uncertain -> MEDIUM; security/data/production
uncertainty -> HIGH. A failed command alone does not upgrade risk or model.

## Full loop

1. [Understand](plan/SKILL.md): contract, evidence, exact task IDs/dependencies.
2. [Implement](delegate/SKILL.md): smallest coherent change, appropriate owner.
3. [Verify](assess/SKILL.md): literal criteria, current evidence, scoped review.
4. [Deliver](codify/SKILL.md): required deployment, honest result, durable lessons.

Repair the affected task without weakening criteria. After two repair attempts on
the same failure without new evidence or measurable progress, report a blocker.
Honor user-set resource limits. Measure credits per verified successful task,
elapsed time, and repairs only when reported by the runtime; invent no metrics.

**Complete:** all this request's criteria and required delivery met. Git publication
is separately authorized. Blockers, approval gates, and pending device-only
confirmation are incomplete outcomes.

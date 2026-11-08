---
name: plan-loop
description: "PLAN runs a Plan -> Delegate -> Assess -> Codify delivery loop with requirement-level evidence and explicit assessment before completion. Use for standalone uppercase PLAN or an explicit plan-loop request."
---

# Plan Loop

**Plan -> Delegate -> Assess -> Codify.** Trigger: standalone uppercase
`PLAN`, not lowercase "plan". Research, recommendation, and plan-only requests
end with that deliverable; implementation requires implementation intent.

## Quality gates

1. [Plan](./plan/SKILL.md): map every requested change to a checkable criterion,
   affected paths, and a verification method before editing.
2. [Delegate](./delegate/SKILL.md): execute the contract, directly or with a
   justified delegate. A plan, worker handoff, or green build is not implementation.
3. [Assess](./assess/SKILL.md): perform a distinct read-only assessment of the
   current diff and every criterion. Required even when implementation checks pass.
4. [Codify](./codify/SKILL.md): close resolved findings, update relevant existing
   docs, meet delivery requirements, and report criterion-level evidence.

Load each phase before entering it. Advance only when its **Ready** gate holds.
Keep one compact acceptance record: criterion ID, requested outcome, implementation
location (or non-code deliverable), verification method/result, remaining obligation.
Missing implementation, failed checks, and missing evidence remain explicit gaps.
Efficient means less duplicate work per verified outcome, not fewer quality gates.

## Automated completion gate

The repository [hook](../../../.github/hooks/plan-loop.json) activates on uppercase
`PLAN` or `plan-loop` in a submitted prompt. For an explicit skill invocation not
visible in that prompt, activate it with
`ruby .github/hooks/plan-loop-gate.rb begin SESSION "request"`.
Use the current runtime session ID, not a shared placeholder. Hooks require a
trusted workspace and a supported/enabled runtime; start a new session after
configuration changes and verify an incomplete PLAN turn is actually blocked.

`ruby .github/hooks/plan-loop-gate.rb status SESSION` prints the acceptance JSON
path under the worktree's Git metadata. It is session-isolated and never committed.
Fill this record during Plan; SQL tasks reference its criterion IDs rather than
duplicating the acceptance record. Example fields (keep the generated `version`
and `request`):

```json
{
  "disposition": "active",
  "scope": ["lib/services/example.dart", "test/example_test.dart", "pubspec.lock"],
  "criteria": [
    {
      "id": "C1",
      "outcome": "Requested behavior, including its error case",
      "implementation": ["lib/services/example.dart"],
      "checks": ["analyze", "test"],
      "assessment": "PASS"
    }
  ],
  "checks": [
    {"id": "analyze", "argv": ["flutter", "analyze", "lib/services/example.dart"]},
    {"id": "test", "argv": ["flutter", "test", "test/example_test.dart"]}
  ]
}
```

Scope includes affected implementation, tests, config/dependencies, and inputs
needed to invalidate checks. Preserve unrelated user edits. Each criterion needs
an outcome, in-scope implementation paths, check IDs, and an assessment verdict.
Declare all repository-required checks and delivery commands. Commands use argv
arrays, execute from the repository root without implicit shell interpretation,
and run only through an ordinary permission-controlled tool call:
`ruby .github/hooks/plan-loop-gate.rb run SESSION CHECK_ID`.
This writes the real exit code and a local log, bound to the contract and scoped
file contents. Run checks after finalizing the record; relevant changes invalidate
receipts. Use existing checks for docs/skills and scripted device observations.

After actual read-only assessment, set every criterion's verdict and run
`ruby .github/hooks/plan-loop-gate.rb assess SESSION "concrete review summary"`.
Meet remaining delivery obligations, then set `disposition` to `complete`.
The Stop hook checks receipts, input freshness, assessment, and delivery status;
it runs no build, install, or arbitrary declared command during Stop.
Missing/failed/stale evidence blocks the turn with repair guidance.

To report an honest blocker, set `disposition: "blocked"` and a concrete `reason`;
for a requested plan-only deliverable, use `"plan-only"` and its delivery reason.
These allow a non-completion response, not a claim of verified implementation.
Follow-ups to active/blocked work invalidate prior evidence; a normal prompt after
complete/plan-only work deactivates the old gate. A new PLAN starts a new record.
This enforces declared evidence, not semantic requirement coverage or truthful
self-assessment. Hook disablement, runtime errors/timeouts, and edited gate state
are not security boundaries; report runtime enforcement separately from tests.

## Lightweight execution

For a single LOW-risk mechanical edit with fully known scope, inline the four
gates: state the criterion/check, edit, run it and inspect the diff read-only,
then report evidence and delivery. Skip phase-file loads, SQL, artifacts, and agents.
Behavior changes, bug fixes, workflow changes, or uncertain scope use the full loop.
An explicit `PLAN` or plan-loop execution request also uses the full loop.
Repository instructions, authorization, and deployment requirements always apply.

## Token discipline

- One owner per coupled change. Delegate only substantial separable work that
  warrants its own context or independent judgment; parallel tools come first.
- Load only the active phase and needed references. Search scoped files
  and identifiers, batch independent reads, and request bounded output.
- Reuse verified research and worker findings. Investigate only decision-relevant
  gaps; stop searching when the contract and implementation are supported.
- Worker prompt: objective/IDs, paths, constraints, criteria/checks, stopping
  condition. Omit unrelated history. Handoff: verdict, changes, evidence, blockers;
  summarize success, but retain evidence for every assigned criterion.
- Save verbose logs outside the conversation; return exit codes and useful
  excerpts. Recover missing detail from those logs rather than rerunning work.
- Background agents need independent foreground work. Read known results after
  completion notification, without polling. Retain same-task context for repairs.
- Reuse valid check evidence under Assess. Stop after assessment and delivery pass:
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
read [cost/evidence](./plan/SKILL%202.md); otherwise use the table without re-research.

Risk: LOW mechanical; MEDIUM established-module behavior; HIGH security, payments,
data/migrations, production permissions, concurrency, public contracts, or hard-to-
verify algorithms (including scans). Uncertain -> MEDIUM; security/data/production
uncertainty -> HIGH. A failed command alone does not upgrade risk or model.

## Repair and completion

Assessment gaps return to the affected implementation; specification gaps return
to Plan. Re-assess the changed scope before Codify. Preserve unaffected evidence
and criteria; narrowing a requirement needs user approval. After two repair attempts on
the same failure without new evidence or measurable progress, report a blocker.
Honor user-set resource limits. Measure credits per verified successful task,
elapsed time, and repairs only when reported by the runtime; invent no metrics.

**Complete:** all this request's criteria and required delivery met. Git publication
is separately authorized. Blockers, approval gates, and pending device-only
confirmation are incomplete outcomes.

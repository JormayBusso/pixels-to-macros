---
name: plan-loop
description: Runs a Plan -> Delegate -> Assess -> Codify delivery loop that researches the specific problem first and routes every task to the best agent for it. Use when the user types PLAN in all-caps, or wants work planned, delegated, executed, and closed out as a repeating loop.
---

# Plan Loop

A closed **PDCA** loop — **Plan -> Delegate -> Assess -> Codify** — circling until every todo is green and codified. Fires on all-caps `PLAN`; lowercase "plan" is ordinary conversation.

## Thin orchestrator (the cost rule)

The main session is the most expensive seat: every tool call re-sends its whole context. So the main session is a **dispatcher**, and all legwork happens inside subagents whose context is thrown away afterwards.

- The main session touches only `plan.md`, subagent handoffs, and `git status --short` / `git diff --stat`. Source reads, searches, edits, builds, tests, and diff review all run inside a subagent.
- Each subagent returns a **handoff** of at most ~150 words: verdict, files changed, commands run with pass/fail, open questions. The main session acts on the handoff and trusts it; a doubt becomes a narrower follow-up subagent.
- Subagent prompts carry the todo, the relevant file paths, and the AGENTS.md § numbers that apply. Point at sections by number (`follow AGENTS.md §5, §9`); quote only the one rule that is easy to miss.
- Background agents: dispatch, then end the turn and wait for the completion notification; read each result once.
- Load each phase file once per loop and keep it in context.

## Model tiers

Single source of truth; phases reference it. Pass `model` + `reasoning_effort` on every `task` call — the subagent default is the session's (expensive) model.

| Tier | implement role | reason role | Effort | Fallback |
| --- | --- | --- | --- | --- |
| cheap | `claude-haiku-5.5` | `claude-haiku-5.5` | low | `gpt-6-luna` |
| standard | `claude-sonnet-5.5` | `gpt-6.1-sol` | medium | the other standard model |
| strong | `claude-opus-5.5` | `claude-opus-5.5` | high | `gpt-6.1-sol` (xhigh) |

Standard implement and reason use different vendors so assess **cross-checks** delegate. Choose the tier per todo, never per session. If a model is unavailable, use its fallback, then the closest same-tier model.

## Risk

- **LOW** — docs, comments, formatting, renames, simple test/config edits.
- **MEDIUM** — focused bug fix or feature in an established module; several related files.
- **HIGH** — auth/security/secrets, payments, DB schema or data migration, infra/CI/deploy, concurrency, public API, hard-to-verify algorithms (incl. the §9 scan pipeline), or a prior failure.

Uncertain → MEDIUM; uncertain about security/data/production → HIGH.

## Phases

Run in order; on red from `assess`, loop back to `plan` (revise mode).

1. [plan/SKILL.md](plan/SKILL.md) — sharpen the prompt, research via subagents, write `plan.md`.
2. [delegate/SKILL.md](delegate/SKILL.md) — one implement subagent per pending todo.
3. [assess/SKILL.md](assess/SKILL.md) — one reason subagent checks the batch; mark green or red.
4. [codify/SKILL.md](codify/SKILL.md) — commit + push each green todo; one deploy at the end.

**Completion:** every todo in `plan.md` is `codified` and the deploy reported real `rc=0` (or was skipped as non-app-bundle) — or the loop has stopped on a red/blocked todo or an approval gate.

---
name: plan-loop
description: Runs a Plan -> Delegate -> Assess -> Codify delivery loop that researches the specific problem first and routes every task to the best agent for it. Use when the user types PLAN in all-caps, or wants work planned, delegated, executed, and closed out as a repeating loop.
---

# Plan Loop

A closed **PDCA** delivery loop — **Plan -> Delegate -> Assess -> Codify** — that keeps circling until the work is done and the learnings are captured. The two things it never skips: **research the specific problem before decomposing it**, and **route every task to the agent that will do it best**.

Fire it when the user types `PLAN` in all-caps. Lowercase "plan" is ordinary conversation and does not force the loop. (This is a delivery loop, distinct from VS Code's built-in Plan mode.)

## Phase 1 — Plan (research-gated)

**Research is the gate. No decomposition before the specific problem is researched.** Not the general area — the exact problem in front of you, against reliable/primary sources per [AGENTS.md](../../../AGENTS.md) §13 (official docs, source, specs; EU-grounded for any nutrition/health figure). For deep or long reading, delegate now to the `research` skill (background agent) and keep planning while it reads.

Then decompose the work into discrete tasks. Every task carries two things:
- a **checkable completion criterion** — done vs not-done is observable, not a vibe.
- a **candidate agent** — your first guess at who runs it (Phase 2 confirms).

**Completion:** a task list where every task names a criterion and a candidate agent, and the problem has been researched (state the sources you relied on).

## Phase 2 — Delegate (best agent per task)

Match each task to the agent that will do it best, using the matrix. One task, one agent, one line of rationale.

| Task shape | Best agent |
|---|---|
| Ambiguous design, architecture, tradeoffs, hard reasoning | Strongest model (e.g. Opus), inline |
| Broad read-only codebase exploration | Read-only search subagent (context isolation) |
| Deep primary-source reading / long research or builds | Background agent -> `research` skill |
| Well-specified mechanical edits / refactors | Faster, cheaper model |
| Hard bug or performance regression | `diagnosing-bugs` skill |
| Test-first feature or bugfix | `tdd` skill |
| Merge / rebase conflict | `resolving-merge-conflicts` skill |
| Module interface / seam design | `codebase-design` skill |
| Domain terms / ubiquitous language / ADR | `domain-modeling` skill |
| Review changes vs standards & spec | `code-review` skill |
| Stress-test a plan before building | `grilling` skill |
| Steps only a human can do (dashboards, secrets, cutover) | `wizard` skill (human-in-loop) |

Pick a **subagent** when the task needs context isolation (it returns one clean result) or a different tool/permission set. Pick **model choice** on the reasoning-vs-mechanical axis. Pick an **existing skill** whenever the task lands in that skill's domain — the skills are the specialists.

**Completion:** every task is assigned to exactly one agent, with a one-line reason.

## Phase 3 — Assess (red/green)

Run each task's completion criterion. **Green** = accept. **Red** = loop back to **Plan** — re-research, re-decompose, or re-delegate the task that failed. Never advance to Codify on red.

**Completion:** every task is green against its own criterion.

## Phase 4 — Codify

Capture what the loop learned so the next run starts ahead. Each learning goes to **exactly one home** — single source of truth, never duplicated across homes:

- **Repo memory** (`/memories/repo/`) — a durable codebase convention or verified command.
- **Session memory** (`/memories/session/`) — task context for this conversation only.
- **AGENTS.md** — a durable repo rule. **Propose the edit for approval; do not write repo rules silently** (AGENTS.md §0.3).
- **New/updated skill** (`.agents/skills/`) — a reusable workflow worth its own trigger.
- **Session plan** — the living plan for the work still in flight.

Then **close the loop**: pick the next task, or start the next iteration back at Plan.

**Completion:** every learning has one home, AGENTS.md changes are proposed not forced, and the loop has either advanced to the next task or reported that all tasks are green and codified.

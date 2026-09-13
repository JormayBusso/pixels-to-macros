---
name: plan-loop
description: Runs a Plan -> Delegate -> Assess -> Codify delivery loop that researches the specific problem first and routes every task to the best agent for it. Use when the user types PLAN in all-caps, or wants work planned, delegated, executed, and closed out as a repeating loop.
---

# Plan Loop

A closed **PDCA** delivery loop — **Plan -> Delegate -> Assess -> Codify** — that keeps circling until the work is done and the learnings are captured. The two things it never skips: **research the specific problem before decomposing it**, and **route every task to the agent that will do it best**.

Fire it when the user types `PLAN` in all-caps. Lowercase "plan" is ordinary conversation and does not force the loop. (This is a delivery loop, distinct from VS Code's built-in Plan mode.)

Each phase is its own skill file, in its own subfolder. Run them in order, looping back to `plan` on any red from `assess`:

1. [plan/SKILL.md](plan/SKILL.md) — first improve the user's raw request using adaptive prompt-engineering principles (structure added only where it helps; no fixed template), then research the specific problem, decompose it into tasks, and write `plan.md` (a markdown todo plan with a completion criterion and candidate agent per task) in the session workspace. Also the re-entry point when `assess` sends a task back red.
2. [delegate/SKILL.md](delegate/SKILL.md) — assign each task in `plan.md` to exactly one agent using the task-shape matrix.
3. [assess/SKILL.md](assess/SKILL.md) — run each task's completion criterion; check it off green in `plan.md`, or leave it red and hand it back to `plan`.
4. [codify/SKILL.md](codify/SKILL.md) — once every task is green, capture learnings to exactly one durable home, commit and push each todo's change, then close the loop (next task, or next iteration from `plan`). Once the whole plan is codified, build and deploy the update to the phone automatically.

**Completion:** all tasks in `plan.md` are green and their learnings are codified — or the loop has explicitly looped back to `plan` on a red task.

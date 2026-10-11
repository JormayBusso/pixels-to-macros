# Plan

Produces or revises `plan.md`, the one artifact the other phases read.

## Step 1 — Sharpen the prompt

Rewrite the user's request (text after `PLAN`) into a precise task: action verbs, the constraints that matter (relevant AGENTS.md §s, LiDAR/non-LiDAR split for scan work), and checkable success criteria. Preserve intent; add structure only where it removes ambiguity; flag missing facts and contradictions instead of inventing them. A good prompt gets light edits.

## Step 2 — Research (in subagents)

Dispatch `explore` subagents (cheap tier, parallel, one per independent question) to locate the files, current behaviour, and existing tests the work touches. Each returns file paths + line numbers + a ≤150-word answer. For external facts (APIs, research, EFSA figures), use one `research` subagent. The plan is built from these reports; re-reading the same files in the main session duplicates their cost.

## Step 3 — Write `plan.md`

Location: session workspace `files/plan-<YYYY-MM-DD>.md` (suffix `-2`, `-3` if today's is still active). Later phases use the most recently modified `plan-*.md`.

```md
# Plan: <title>
Status: active

## Goal
<1–3 sentences>

## Prompt
<the sharpened prompt; add "Missing:" lines only if something is genuinely missing>

## Todos
### [ ] <kebab-id>: <title>
- Status: pending
- Risk: LOW|MEDIUM|HIGH
- Files: <paths from research>
- Do: <self-contained instruction a subagent can run with no other context>
- Done when: <concrete, checkable criteria + the exact check command(s)>
- Log: <one line, appended by later phases>
```

- Statuses: `pending`, `delegated`, `assessed`, `failed`, `blocked`, `codified`.
- Smallest set of todos that are each independently implementable and checkable; keep refactor, behaviour change, and migration in separate todos.
- A todo with an open design question gets `Status: blocked` + the question.
- Mark independent todos so delegate can run them in parallel (`Parallel: yes`), and list touched files so parallel agents never share a file.
- Commits are codify's job; add no commit todos.

## Revise mode

When `assess` reports a `failed` todo (or a `blocked` question is answered): edit only that todo — rewrite `Do` / `Done when` from the failure reason, reset `Status: pending`, re-rate `Risk`. Leave other todos and the Prompt untouched unless the failure shows the task itself was wrong. Revise mode needs no new `PLAN`.

## Hand off

Tell the user: file path, the sharpened prompt in ≤3 lines, and one line per todo with its risk. Then continue straight into `delegate`.

# Delegate

Dispatches every `Status: pending` todo in `plan.md` to one implement subagent. Skip all other statuses.

## Routing (per todo)

| Todo | Tier (implement role) |
| --- | --- |
| LOW, mechanical (docs, comments, formatting, simple tests/config) | cheap |
| LOW touching runtime behaviour, or MEDIUM | standard |
| HIGH | strong |

Use `general-purpose` for code changes, `task` for run-a-command todos. Independent todos (`Parallel: yes`, disjoint files) go out together in `background` mode; otherwise sync, one after another.

## Subagent prompt

Include, verbatim: the todo's `Do`, `Files`, `Done when`; the repo path and branch; the applicable AGENTS.md § numbers. Then require:

- Implement only this todo's scope; leave lockfiles, generated files, CI, and other todos' files alone.
- Run the todo's check command(s) plus `flutter analyze <changed files>`; for Swift changes, the §4 simulator `xcodebuild` (pipe its output through `tail -20`). The release build and phone deploy belong to codify.
- On ambiguity, stop and report the question instead of choosing a design.
- Return a ≤150-word handoff: files changed, commands + pass/fail, open questions.

## Escalation

Retry once one tier up when the first attempt fails its checks or reports a non-trivial ambiguity; a second failure marks the todo `failed`. A todo that turns out to touch a HIGH area is re-rated HIGH and redone at strong.

## Record

Per todo: `Status: delegated` (or `failed` / `blocked` with the reason) and append to `Log`: `delegate=<tier>(<model>) checks=<cmd>=pass|fail`.

When every dispatched agent has reported, continue straight into `assess`.

---
name: assess
description: Verify delegated todos in the active plan-*.md file against their acceptance criteria and the project's existing lint/build/test commands, then mark them assessed or failed. Runs automatically as the third phase right after `delegate` finishes (part of the PLAN loop chain) — the user does not need to type "assess". Can also be invoked directly if the user explicitly asks to check/verify/review delegated work from a plan.
---

# Assess

Third phase of the plan → delegate → assess → codify loop. Checks each
`delegated` todo against two things — its own acceptance criteria and the
project's existing validation commands — and records a pass/fail verdict.

Note: once a loop has been started with the uppercase `PLAN` trigger, this
phase runs automatically — it is invoked by `delegate` itself, not by the
user typing "assess".

## Find the plan

- Use the most-recently-modified `files/plan-*.md` in the session workspace
  unless the user names a specific file.
- Only process todos with `Status: delegated`. Ignore `pending`,
  `assessed`, `failed`, and `codified` todos.

## Model routing

Use the same **Model tiers** mapping and environment fallback rule defined in
`plan`'s Model tiers section: cheap is `gpt-5.6-luna` at low effort (fallback
`gemini-3.6-flash` at low effort, or `claude-haiku-4.5` with no effort
parameter), standard is
`gpt-5.6-terra` at medium effort (fallback `gpt-5.5` or `gpt-5.4` at medium
effort), and strong is `claude-opus-4.8` at high effort (fallback
`claude-opus-4.7` or `claude-sonnet-5` at high effort). Always fall back to
the closest available model rather than failing; never default to flagship
models such as `claude-opus-5` or `gpt-5.6-sol`.

| Todo risk | Assess tier | Effort |
| --- | --- | --- |
| LOW, but only when every LOW-risk condition below is met | cheap | low |
| MEDIUM | standard | medium |
| HIGH | strong | high |

- A LOW-risk todo may use the cheap tier only when the change is limited to
  docs, comments, formatting, or changelog content; has no runtime behavior
  change; has a small, deterministic diff; and all required checks pass.
  Otherwise assess it as MEDIUM for assess-model purposes, even if plan tagged
  it LOW.
- Assess may use a stronger tier than delegate used, but never a weaker tier
  than the risk actually warrants once real evidence is in hand.
- HIGH-risk work always uses the strong tier, even if delegate used a cheaper
  tier. Assess is the trust boundary: it must never be weaker than delegate
  for HIGH-risk work, and when in doubt use the stronger tier here.

## What to check, per delegated todo

1. **Acceptance criteria** — re-read the todo's Acceptance Criteria and
   verify each one literally against the actual current state of the repo
   (inspect the real files/diff/behavior; review the actual `git diff`, not
   only the Delegation notes).
2. **Project validation commands** — run the smallest existing
   lint/build/test command(s) that cover the changed area (per this
   project's AGENTS.md: targeted `ruff`/`pytest`/prek checks, or the
   relevant PowerShell fixture tests under `test_sandbox/`, or any
   project-specific existing check for a different repo). Never introduce
   new lint/test tooling — only run what already exists.
3. Review the actual diff for unrelated or out-of-scope changes, missing
   tests, scope expansion, error-handling gaps, compatibility issues, and
   security or data risks. For MEDIUM and HIGH todos, review boundary
   conditions and failure paths, not only the happy path.
4. A todo passes only if **both** checks pass. A passing test suite alone is
   not sufficient when the acceptance criteria themselves are not met.
5. If required evidence is incomplete—for example, a required check could not
   be run—record the todo as `failed` with the missing-evidence reason. Never
   invent a PASS without real evidence.
6. If the actual current diff changes after it was reviewed earlier in this
   assess pass (for example, because the user or another process changed
   files), stop and re-run the full assessment against the current diff rather
   than reporting on stale state.

## HIGH-risk requirements

For HIGH-risk todos, obtain stronger evidence appropriate to the specific
change beyond the normal LOW/MEDIUM checks: targeted tests, integration tests,
migration checks, security review, compatibility checks, or rollback
validation, as applicable. Record `Human Approval Required: yes` whenever
`Risk: HIGH`; record `Human Approval Required: no` otherwise.

Even when a HIGH-risk todo passes and is recorded as `Status: assessed`,
codify/commit must not proceed automatically without explicit human approval.
When `Human Approval Required: yes`, the After assessing behavior changes:
stop and explicitly ask the user for approval before `codify` may run. This is
an exception to automatic continuation; LOW and MEDIUM todos continue
automatically unchanged.

## What to update per todo

```md
- Status: assessed        # if both checks passed
- Assessment: criteria=pass; checks=<command(s) run>=pass;
  model=<tier>(<model-name>); human_approval_required=yes|no
- Human Approval Required: yes|no
```

or on failure:

```md
- Status: failed
- Assessment: criteria=<pass|fail, which criterion failed>;
  checks=<command(s) run>=<pass|fail, what failed>; reason=<concrete
  failure detail a plan revision could act on>; model=<tier>(<model-name>);
  human_approval_required=yes|no
- Human Approval Required: yes|no
```

- Never retry the todo yourself and never silently fix the code yourself —
  assess is read/verify-only. If something is fixable in two seconds you
  still record it as `failed` with the reason; fixing is `plan`'s
  (revision) and `delegate`'s job next.
- Do not touch `Codify` notes.
- Update the todo's `Routing Log:` with the actual assess tier/model, evidence
  and commands run, any escalation reason, and the PASS/FAIL decision, using
  the plan skill's machine-readable style (for example,
  `assess_model=standard(gpt-5.6-terra); assess_decision=PASS`).

## After assessing

- Summarize per todo: pass/fail and why.
- If any todo is `failed`, stop the automatic chain here and tell the user
  the loop routes back to `plan` to revise that todo (do not invoke `plan`
  yourself — propose it as the next step; revision still requires the
  `PLAN` trigger or an explicit user go-ahead since it changes scope).
- If all processed todos passed but any has `Human Approval Required: yes`,
  stop and explicitly ask the user to approve before `codify` may run.
- If all processed todos passed, do not stop and wait for the user —
  immediately continue the loop yourself by invoking `codify` next, unless a
  Human Approval Required field says `yes`. Tell the user you're proceeding
  straight to `codify`.
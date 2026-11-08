# Codify

Use [Plan Loop](../SKILL.md) for completion rules. Preserve unrelated user changes.

1. Update existing docs only for changed documented conventions or required
   corrections. Keep useful verified lessons, not routine notes. Relevant code/
   config edits return to Assess; assess documentation edits against their criteria.
2. Confirm integrated changes still match the check evidence. Build/deploy once
   for the integrated request, serially, following AGENTS.md's exact clean/release/
   `devicectl` retry sequence with real exit codes. Retain full failure logs.
   Docs/skill-only changes: explicitly report no app deployment needed.
3. Scanner recognition/geometry/color changes require device confirmation.
   Request the named logs and re-scan through the user-input tool. Installation
   is not visual proof; outstanding device criteria stay pending or `blocked`.
4. Mark current-request tasks `done` only when acceptance and required delivery
   are met. Integration/deployment failure returns to targeted repair, not a restart.
5. Reconcile the final diff and acceptance record with the user's original request
   and follow-ups. Every outcome needs implementation/deliverable, an assessment
   verdict, and current evidence. Any remaining gap is an incomplete outcome.
   Set the gate disposition to `complete` only after these obligations pass.
   For blocked or plan-only outcomes, use the root's explicit non-completion route.

## Optional publication

Commit, push, rebase, and PR creation require explicit authorization under repository
rules. PLAN, PASS, and HIGH-risk approval are not blanket Git consent.
When authorized, inspect staged/unstaged content and stage precise intended paths/
hunks, excluding pre-existing changes. Use the required trailer. On rejection,
report the cause; no automatic pull/rebase or force-push.

**Complete:** all current-request obligations met; otherwise report progress and
the exact blocker. Final report: implemented outcomes, assessment/check evidence,
delivery, limitations. Include concise criterion IDs/results so the user can see
what was actually assessed; distinguish implemented, locally verified, and confirmed
on-device. A passing build or successful install alone cannot imply all three.
Use only runtime-reported cost/time/repair metrics; collecting them is not a new
agent task. Suggest an improvement only when a concrete better option was found.

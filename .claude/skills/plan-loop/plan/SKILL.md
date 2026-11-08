# Plan

Use [Plan Loop](../SKILL.md) for shared rules.

1. Read applicable repository instructions and relevant code/tests. Capture the
   starting worktree state to preserve unrelated changes.
2. Re-read the user's request, including follow-ups. Assign a criterion ID to
   every requested outcome and constraint; preserve implementation intent.
   Define non-goals and observable expected behavior, not merely a file list.
   For bugs, reproduce the failure before editing where feasible; otherwise
   record available evidence and the missing reproduction.
3. Research non-trivial external facts from current primary sources per AGENTS.md.
   Reuse applicable session evidence; stop once remaining uncertainty cannot
   affect the decision. A lookup is not automatically a research-agent task.
4. Use existing patterns for low-impact details. Ask through the user-input tool
   for material scope/design decisions or required authorization; record blockers.
5. Trace each outcome through relevant entry points, shared helpers, consumers,
   persistence, and alternative paths. Record affected surfaces and preserved
   behavior; inspect only applicable branches. For scans, account separately for
   LiDAR and non-LiDAR. A filename search alone is not an impact assessment.
6. Fill the acceptance record from the root: each criterion gets its implementation
   scope, exact check or observation, and expected result/threshold. Include
   relevant error/edge cases and regressions. Distinguish local checks from device
   or delivery evidence. Use existing tooling; a build proves compilation, not UX.
   Unknown material behavior or an unverifiable criterion is an explicit gap.
   Initialize and populate the automated gate record as described in the root.
   Include all required checks and relevant inputs before collecting receipts.

## Task state

For multi-step work, use existing `todos` and `todo_deps`, not a duplicate plan.
Pass exact request-specific task IDs; preserve unrelated todos. Each description
contains scope/paths/constraints, difficulty/risk reason, owner, criterion IDs/
checks, dependencies/shared resources, and progress/evidence references.

Dependency milestones distinguish locally verified output from actual delivery;
the former can unblock implementation before final integrated deployment.
Statuses: `pending`, `in_progress`, `done`, `blocked`; `done` requires the task's
acceptance and delivery obligations. For cross-session handoff, use one named
session artifact and its exact path, not modification-time selection.

**Ready:** every requested outcome is mapped, relevant paths are accounted for,
and actionable tasks have criteria/checks and prerequisite milestones.
Material unresolved decisions are blocked; independent ready tasks may proceed.
Briefly state the intended change and assessment approach, then continue to
[Delegate](../delegate/SKILL.md),
or return the requested research/plan-only deliverable.

On repair, revise only the affected task and stale evidence. Criteria change only
for a justified specification correction; material scope changes require approval.

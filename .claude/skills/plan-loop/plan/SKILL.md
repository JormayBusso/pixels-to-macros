# Understand

Use [Plan Loop](../SKILL.md) for shared rules.

1. Read applicable repository instructions and relevant code/tests. Capture the
   starting worktree state to preserve unrelated changes.
2. Define behavior, constraints/non-goals, and literal acceptance criteria.
   For bugs, obtain a reproduction or state the available evidence.
3. Research non-trivial external facts from current primary sources per AGENTS.md.
   Reuse applicable session evidence; stop once remaining uncertainty cannot
   affect the decision. A lookup is not automatically a research-agent task.
4. Use existing patterns for low-impact details. Ask through the user-input tool
   for material scope/design decisions or required authorization; record blockers.

## Task state

For multi-step work, use existing `todos` and `todo_deps`, not a duplicate plan.
Pass exact request-specific task IDs; preserve unrelated todos. Each description
contains scope/paths/constraints, difficulty/risk/tier reason, owner, criteria/
checks, dependencies/shared resources, and progress/evidence references.

Dependency milestones distinguish locally verified output from actual delivery;
the former can unblock implementation before final integrated deployment.
Statuses: `pending`, `in_progress`, `done`, `blocked`; `done` requires the task's
acceptance and delivery obligations. For cross-session handoff, use one named
session artifact and its exact path, not modification-time selection.

**Ready:** actionable tasks have explicit contracts and prerequisite milestones;
material unresolved decisions are blocked. Continue to [Implement](../delegate/SKILL.md),
or return the requested research/plan-only deliverable.

On repair, revise only the affected task and stale evidence. Criteria change only
for a justified specification correction; material scope changes require approval.

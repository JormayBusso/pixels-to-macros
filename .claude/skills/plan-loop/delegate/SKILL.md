# Implement

Use [Plan Loop](../SKILL.md) for ownership, prompts, handoffs, and model rules.

1. Work only on this request's ready tasks; mark tracked tasks `in_progress`.
   Check dependency milestones: locally verified output can unblock implementation;
   delivery-dependent tasks wait for delivery. Blocked tasks are never ready.
2. Execute focused changes and continuous debugging traces directly. When
   delegation meets the root rules, match the agent's capabilities to the objective.
   Keep same-task repairs with the existing owner instead of restarting exploration.
3. Parallel work needs independent contracts and no shared mutable files,
   generated outputs, build directories, or device resources. Disjoint filenames
   are insufficient. Isolate only when authorized/justified; serialize shared builds.
4. Read local context, make the smallest coherent change, and update dependent
   call sites. Use existing tools for required generated/manifest edits. Add
   focused regression tests for new/fixed behavior, not implementation restatements.
5. Run appropriate existing checks; record evidence under [Verify](../assess/SKILL.md).
   Preserve real command exit codes: unpiped execution or `pipefail` with captured
   producer status. Successful logs stay summarized; retain full failure logs.

Follow applicable AGENTS.md validation, localization, and separate scanner-path
requirements. Docs-only work uses documentation checks if provided; release build
and phone installation belong to Deliver.

**Ready:** implementation plus evidence, or a concrete failure/blocker. Continue
to Verify. Diagnose code, specification, environment, or missing evidence before
repair/escalation; signing/connectivity recovery is not a reason to regenerate code.
Rerate risk only when actual scope warrants it; use the root no-progress bound.

# Delegate

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
   Fix the supported root cause; when evidence contradicts it, return to Plan.
   Cover every mapped path, including errors and applicable localization.
5. Update the acceptance record with actual implementation locations and test
   evidence for each assigned criterion. Inspect the resulting diff for omitted
   requirements. A suggestion or TODO leaves an implementation criterion unmet.
6. Run appropriate existing checks; record evidence under [Assess](../assess/SKILL.md).
   Preserve real command exit codes: unpiped execution or `pipefail` with captured
   producer status. Successful logs stay summarized; retain full failure logs.

Follow applicable AGENTS.md validation, localization, and separate scanner-path
requirements. Docs-only work uses documentation checks if provided; release build
and phone installation belong to Codify.

**Ready:** all assigned outcomes are implemented with locations and check results.
Unimplemented criteria and failures route to repair or an explicit blocker, not
Codify. Continue to Assess; implementation checks do not replace that phase.
Diagnose code, specification, environment, or missing evidence before
repair/escalation; signing/connectivity recovery is not a reason to regenerate code.
Rerate risk only when actual scope warrants it; use the root no-progress bound.

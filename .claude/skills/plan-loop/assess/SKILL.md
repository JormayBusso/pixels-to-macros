# Verify

Use [Plan Loop](../SKILL.md) for shared rules. Verify the actual outcome, not a PASS
assertion or passing tests that leave acceptance criteria untested.

## Evidence

Keep one compact record per check batch: exact commands, cwd, true exit codes,
criteria/scope, code-state fingerprint, and log/artifact paths. Include affected
source, tests, config, dependencies, and relevant untracked files; add environment/
input conditions when material. Hash only the verification scope, not unrelated
workspace content.

Reuse passing evidence while those inputs remain current. Inspect referenced logs
as needed; unsupported claims are missing evidence. Relevant edits/environment
changes invalidate affected checks; shared helpers may invalidate several tasks.
Combine related test selectors in one runner. Required checks stay mandatory.

## Validate and route

1. Check every criterion literally; demonstrate bug fail-to-pass where feasible
   and preserve existing behavior. State when reproduction is unavailable.
2. Run missing/stale focused lint/tests/build/integration checks using existing
   tooling. Broaden only for an uncovered requirement, relevant edit, or failure.
3. Review the scoped diff against the starting worktree: scope, call sites,
   failure paths, compatibility, and applicable AGENTS.md invariants.
4. Review directly when evidence fits this context. Substantial complex/high-risk
   work gets independent review when separate context is warranted. Give the diff,
   rubric, and existing evidence; request concrete defects, not speculative style
   changes or duplicate tests. Follow explicit security-review routing when requested.
   Repeat review only for relevant edits or unresolved findings.
5. Record `locally-verified` with evidence references only when all required local
   criteria/checks pass. Unavailable required local evidence -> `blocked`.

Defect -> repair the affected implementation and stale checks; keep `in_progress`.
Contract change -> Understand. Pending device criteria are not `done`, but may
proceed to [Deliver](../codify/SKILL.md) for installation and observation.
**Ready:** local evidence passes, findings resolved, delivery obligations named.

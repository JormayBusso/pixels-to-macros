# Assess

Use [Plan Loop](../SKILL.md) for shared rules. Verify the actual outcome, not a PASS
assertion or passing tests that leave acceptance criteria untested.
Assessment is a distinct read-only phase: inspect code, run checks, and record
findings; code fixes return to Delegate before another assessment.

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
For the automated gate, run declared checks through its `run` command to create
real receipts. After reviewing the current diff and criteria, use `assess` with
a concrete summary; this records the review fingerprint, not a substitute review.

## Validate and route

1. Re-read the request and follow-ups independently of the implementation summary.
   Reconcile them with the acceptance record; add any omitted criterion and return
   it to Plan/Delegate. Inspect the actual implementation for every requested
   outcome and affected path, not just the worker's changed-file list.
2. Check every criterion literally; demonstrate bug fail-to-pass where feasible
   and preserve existing behavior. Verify assertions exercise the changed behavior
   and relevant failure/edge cases; mocks must not bypass the behavior being claimed.
   State when reproduction is unavailable.
3. Run missing/stale focused lint/tests/build/integration checks using existing
   tooling. Broaden only for an uncovered requirement, relevant edit, or failure.
4. Review the scoped diff against the starting worktree: scope, call sites,
   failure paths, compatibility, and applicable AGENTS.md invariants.
   Examine the strongest plausible counterexample to the fix and check whether
   existing evidence rules it out. An unresolved correctness issue needs a focused
   check or finding, not a confidence claim.
5. Review directly when evidence fits this context. Substantial complex/high-risk
   work gets independent review when separate context is warranted. Give the diff,
   rubric, and existing evidence; request concrete defects, not speculative style
   changes or duplicate tests. Follow explicit security-review routing when requested.
   Repeat review only for relevant edits or unresolved findings.
6. Record each criterion as `PASS`, `FAIL`, or `BLOCKED`, separating local and
   delivery obligations. PASS cites implementation/deliverable and current evidence;
   FAIL names the concrete mismatch; BLOCKED names missing evidence or authorization.
   Review findings need an explicit disposition backed by evidence.
   Record `locally-verified` only when all required local criteria/checks pass
   and correctness findings are resolved. Unavailable required local evidence -> `blocked`.

Defect -> repair the affected implementation and stale checks; keep `in_progress`.
Contract change -> Plan. Pending device criteria are not `done`, but may
proceed to [Codify](../codify/SKILL.md) for installation and observation.
**Ready:** local evidence passes, findings resolved, delivery obligations named.
Record a concise assessment verdict with criterion IDs, evidence references, and
gaps before advancing. Elapsed time and test count are not correctness evidence.

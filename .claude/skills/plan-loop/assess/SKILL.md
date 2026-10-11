# Assess

Verifies `Status: delegated` todos. Assess is read-only: it records verdicts and never fixes code.

## Dispatch

One reason-role subagent per batch, at the tier of the riskiest todo in it (LOW docs-only → cheap; anything with runtime change or MEDIUM → standard; HIGH → strong, assessed in its own batch). Standard reason (`gpt-6.1-sol`) cross-checks Sonnet's implementation.

Give it: each todo's `Do` + `Done when`, the file list, and the delegate handoff. Instruct it to:

1. Check every `Done when` criterion literally against the current files and `git diff -- <files>`.
2. Re-run each todo's check command(s) (`flutter analyze`, targeted `flutter test`, simulator `xcodebuild` for Swift) — never new tooling.
3. Flag out-of-scope edits, missing l10n (§5), contrast/theming violations (§7), and, for MEDIUM/HIGH, failure paths and edge cases.
4. Return per todo: `PASS` or `FAIL: <criterion> — <concrete reason>`, plus the commands run. A PASS needs every criterion met and every check green; missing evidence is a FAIL.

## Record

- PASS → `Status: assessed`; append `assess=<tier>(<model>) PASS` to `Log`. HIGH-risk also gets `Approval: needed`.
- FAIL → `Status: failed`; append `assess=<tier>(<model>) FAIL <reason>` to `Log`.

## Next

- Any `failed` → stop the chain, report the reasons, and propose the `plan` revision.
- Any `Approval: needed` → ask the user to approve before codify.
- Otherwise continue straight into `codify`.

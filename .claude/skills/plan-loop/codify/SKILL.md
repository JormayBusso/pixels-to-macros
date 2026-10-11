# Codify

Turns each `Status: assessed` todo into a pushed commit, then deploys once when the whole plan is codified. Runs in the main session with plain git commands (no model subagent needed); it trusts assess's verdict.

## Per todo, in order

1. **Gate:** a HIGH todo needs explicit user approval in the conversation; record `Approval: yes (<when>)`. No approval → stop and ask.
2. **Docs:** if the todo changed a documented convention, update that doc (usually AGENTS.md) for this todo only.
3. **Stage:** `git add <this todo's files>` — never `-A`. If `git status --short` shows files that belong to no todo, stop and ask.
4. **Commit:** title + short body from the todo, ending with `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
5. **Push:** `git push` on the current branch (standing user instruction for this loop). On rejection, `git pull --rebase` once and retry; then stop and report. Never force-push; never open a PR.
6. **Record:** `Status: codified`; append `commit=<sha> pushed=yes|no` to `Log`.

## Deploy (once, after every todo is codified)

Skip and say so if no codified change touches the app bundle. Otherwise dispatch one `task` subagent (cheap tier) to run AGENTS.md §4 steps 1–3 exactly — `flutter clean && flutter build ios --release`, then the `devicectl` retry loop with the real `rc` (unpiped) — and return only `INSTALL_OK rc=0` or the last error. Update in place: no uninstall, no signing/bundle-id change.

## Close

Set the plan's `Status: complete` when every todo is codified. Report per todo: sha, pushed, docs touched; then the deploy result. For scan render/shape changes, remind the user they are device-only validatable and name the logs to paste (AGENTS.md §9).

---
name: codify
description: Update relevant docs, commit and push each assessed todo from the active plan-*.md file, marking each codified, then build and deploy the updated app to the phone once the whole plan is codified. Runs automatically as the fourth and final phase right after `assess` finishes with all todos passing (part of the PLAN loop chain) — the user does not need to type "codify". Can also be invoked directly if the user explicitly asks to commit/finalize/document/deploy work from a plan.
---

# Codify

Fourth and final phase of the plan → delegate → assess → codify loop.
Turns each `assessed` todo into a permanent, documented commit.

Note: once a loop has been started with the uppercase `PLAN` trigger, this
phase runs automatically — it is invoked by `assess` itself once every
todo has passed, not by the user typing "codify". This is also the natural
end of the automatic chain: after codify finishes, stop and report. Per the
user's explicit standing instruction for this loop, codify also pushes each
commit and — once the whole plan file is fully codified — builds and
deploys to the phone automatically (see "Push" and "Deploy to phone" below).
Opening a PR remains a separate manual step.

## Find the plan

- Use the most-recently-modified `files/plan-*.md` in the session workspace
  unless the user names a specific file.
- Only process todos with `Status: assessed`. Ignore `pending`,
  `delegated`, `failed`, and `codified` todos.

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

- Prefer deterministic tooling with no model call where possible. Staging
  files, running `git status`/`git diff`, and committing via a fixed message
  template are mechanical Git operations, not model reasoning.
- When model assistance is used for wording, use the cheap tier for simple
  commit-message or changelog wording.
- Use the standard tier only when a release note or migration note needs
  careful technical wording.
- Never use the strong tier for codify unless a human explicitly requests it
  for that specific commit.

## HIGH-risk approval gate

Before performing Step 2 or Step 3 for a todo whose `Risk:` field is `HIGH`,
check its Assessment notes for `Human Approval Required: yes`. If present, do
not commit until the user has explicitly confirmed approval in the
conversation. Do not infer approval from silence or from the mere fact that
assess said PASS.

Before staging, record the explicit confirmation in the todo's Codify notes:

```md
- Human Approved: yes (<short note of who/when confirmed>)
```

If this field is not already present for a HIGH-risk todo, ask the user
directly for approval and stop; do not proceed to stage or commit.

## Per todo, in order

1. **Update docs** for that todo's change only — e.g. this project's
   `AGENTS.md` tables/conventions, relevant README, or inline doc comments
   — whatever the project's existing documentation convention already is.
   Only document what that todo actually changed; do not bundle unrelated
   doc edits from other todos into the same step.
   Before staging (Step 2), re-verify that `git status` and `git diff` match
   what assess actually reviewed. If the working tree changed since assess
   ran, stop and report that assess must be re-run; do not stage or commit
   possibly different content.
2. **Stage only that todo's changes** (code + its doc update). If other
   todos' changes are mixed into the working tree, stage precisely the
   files belonging to this todo (`git add <specific paths>`), not `git add
   -A`.
3. **Commit** with a message summarizing the todo (title + short body from
   its Description), including the standard
   `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
   trailer.
4. **Push immediately** (`git push`, current branch). If the push is
   rejected (e.g. remote moved on), `git pull --rebase` once and retry; if it
   still fails, stop and report — do not force-push.
5. Record in the todo block:

```md
- Status: codified
- Codify: commit=<short sha>; pushed=yes|no (reason if no); docs=<file(s) updated, or "none needed">; model=<tier>(<model-name>) [only if used for wording]
```

## Boundaries

- **Push every commit, but never open a PR.** Per the user's explicit
  standing instruction for this loop, each todo's commit is pushed
  immediately (Step 4 above); PR creation stays a separate manual step for
  the user.
- Never `--force` push. If a normal push is rejected, rebase once and retry
  (see Step 4); if that fails, stop and report rather than forcing.
- Do not re-run assessment checks — codify trusts `assess`'s verdict.
- If staging reveals unexpected unrelated changes mixed in, stop and ask
  the user rather than guessing which files belong to the todo.

## Deploy to phone (once the whole plan is codified)

Only after **every** todo in the plan file is `Status: codified` (i.e. this
is the last todo of the loop, not each individual todo) — deploy the updated
app to the phone automatically, once per full plan loop. Skip this step
entirely if none of this loop's codified changes touch the app bundle (e.g.
the whole loop was docs-only) and say so instead.

Follow [AGENTS.md](../../../../AGENTS.md) §4 exactly, in order:

1. `flutter clean && flutter build ios --release` — always clean first (a
   stale `build/ios` breaks code signing on install).
2. Install with `devicectl`, retrying on transient wireless errors, and
   checking the real `rc` (never pipe to `tail`/`head`/`grep`, which masks
   it):
   ```
   for i in 1 2 3 4 5 6; do
     xcrun devicectl device install app \
       --device 80E158A2-4911-5ED4-A203-7E18D81AEC34 \
       build/ios/iphoneos/Runner.app > /tmp/dcinstall.log 2>&1
     rc=$?
     if [ $rc -eq 0 ]; then echo "INSTALL_OK rc=0"; break; fi
     echo "install failed rc=$rc, retrying"; sleep 4
   done
   ```
3. **Do not uninstall the app first, and do not change signing
   identity/team/bundle id.** `devicectl device install app` updates the
   already-installed app in place; since the developer certificate was
   trusted once already, this does **not** re-trigger the "Untrusted
   Developer" prompt in Settings → General → VPN & Device Management — the
   user should never need to re-approve there for a routine update. Only a
   genuinely new signing identity or a manual uninstall would require that.
4. Confirm the real `rc=0` from the log before reporting the deploy as
   done. If all retries fail, report the failure and the last error instead
   of claiming success.

## After codifying

- Summarize per todo: commit sha, whether it pushed, and docs touched.
- Report the overall plan file status: if every todo is now `codified`,
  mark the file's top-level `Status: complete`, and report the phone-deploy
  result (installed rc=0, or skipped because the loop was non-app-bundle,
  or failed with the reason); otherwise leave `Status: active` and note
  which todos remain (still `pending`/`delegated`/`failed`) for a future
  loop pass — no deploy happens until the whole plan is codified.
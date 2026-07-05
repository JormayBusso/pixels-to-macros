#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PreToolUse hook — GitHub push guard.
#
# Enforces the AGENTS.md rule: "Never commit, push, force-push ... without
# asking" and "only push to GitHub when the user says so."
#
# Reads the tool-call payload (JSON) on stdin. When a terminal command invokes
# `git push` (any variant, including --force / -f), it returns
# permissionDecision "ask" so the user must explicitly approve the push.
# Every other tool call passes through untouched (no output = default allow).
# ---------------------------------------------------------------------------

payload="$(cat)"

# Match a terminal "command" field whose value runs `git push` (optionally with
# leading global flags like `git -c x=y push`). The pattern is scoped to the
# "command" key so it does NOT fire on file edits that merely mention "git push"
# in their content.
if printf '%s' "$payload" | grep -qiE '"command"[[:space:]]*:[[:space:]]*"[^"]*git([[:space:]]+-[^"[:space:]]+)*[[:space:]]+push'; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "AGENTS.md: pushing to GitHub requires explicit user approval. Approve only if you (the user) asked for this push."
  }
}
JSON
fi

exit 0

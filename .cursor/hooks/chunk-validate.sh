#!/usr/bin/env bash
#
# Cursor `stop` hook — the Cursor equivalent of the Claude Code Stop hook in
# .claude/settings.json. After every agent turn, run `chunk validate` (the same
# 12 gates CI runs, on the sidecar). If a gate fails, return the failure output
# to the agent as a follow-up so it fixes the problem; the hook then runs again,
# bounded by `loop_limit` in .cursor/hooks.json. When everything is green, the
# agent is allowed to stop.
#
# Contract: this must stay behaviourally identical to the Claude Code Stop hook
# (`chunk validate`). Don't add gates here — gates live in .chunk/config.json.

set -uo pipefail

# Consume the hook JSON payload Cursor sends on stdin (we don't need its fields,
# but we must drain it so the pipe closes cleanly).
cat >/dev/null 2>&1 || true

# Project hooks run from the project root, but resolve the repo root from this
# script's location too, so it works regardless of cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 0

# Run the gates on the sidecar. Redirect stdin from /dev/null: chunk does a
# blocking stdin read to detect a hook payload, which would otherwise hang now
# that we've already drained stdin above.
output="$(chunk validate </dev/null 2>&1)"
status=$?

emit() { # $1 = followup message
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg m "$1" '{followup_message: $m}'
  else
    python3 -c 'import json,sys; print(json.dumps({"followup_message": sys.argv[1]}))' "$1"
  fi
}

if [ "$status" -ne 0 ]; then
  # A gate failed. Feed the output back so the agent fixes it and validation
  # re-runs (bounded by loop_limit in .cursor/hooks.json).
  emit "chunk validate failed — the sidecar caught an issue before this change can be pushed. Fix the problem(s) below with the smallest possible edit, then validation will run again automatically:

${output}"
  exit 0
fi

# Green. Report each distinct green state exactly once (the report changes no
# files, so the next run matches the marker and stops cleanly — no loop).
STATE_HASH="$(git diff HEAD 2>/dev/null | shasum 2>/dev/null | awk '{print $1}')"
MARKER="$REPO_ROOT/.chunk/.reported-green"
if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$STATE_HASH" ]; then
  exit 0
fi
printf '%s' "$STATE_HASH" > "$MARKER"

emit "Sidecar validation PASSED — all gates are green. Do NOT edit any files. Report this to the user now: say that chunk validate passed on the sidecar and the change is safe to push, and summarize the gate set (install, lint, scan, test, bundle across the payments and transfers mini-apps). Validation output:

${output}"
exit 0

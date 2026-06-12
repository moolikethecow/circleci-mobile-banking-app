#!/usr/bin/env bash
#
# Claude Code `Stop` hook — runs `chunk validate` (the same 12 gates CI runs,
# on the sidecar) after every agent turn.
#
#   - RED  : block the stop and feed the failure back so the agent fixes it.
#            The hook then runs again (bounded by Claude Code's own
#            stop_hook_active protection once the agent reports/finishes).
#   - GREEN: block the stop ONCE and tell the agent to report the green result
#            to the user, so the audience always sees the sidecar verdict — even
#            when everything passes. A marker keyed on the working-tree diff
#            ensures we report each green state only once (no infinite loop:
#            the agent's report changes no files, so the next run matches the
#            marker and exits cleanly).
#
# Contract: stays behaviourally identical to the Cursor stop hook
# (.cursor/hooks/chunk-validate.sh). Gates live in .chunk/config.json only.

set -uo pipefail

# Drain the hook JSON payload Claude Code sends on stdin so the pipe closes.
cat >/dev/null 2>&1 || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 0

emit() { # $1 = decision, $2 = reason  -> Claude Code Stop hook JSON
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg d "$1" --arg r "$2" '{decision:$d, reason:$r}'
  else
    python3 -c 'import json,sys; print(json.dumps({"decision":sys.argv[1],"reason":sys.argv[2]}))' "$1" "$2"
  fi
}

# Run the gates on the sidecar (stdin from /dev/null: chunk blocks on a stdin
# read otherwise, and we already drained the payload above).
output="$(chunk validate </dev/null 2>&1)"
status=$?

if [ "$status" -ne 0 ]; then
  emit block "chunk validate failed — the sidecar caught an issue before this change can be pushed. Fix the problem(s) below with the smallest possible edit, then validation runs again automatically:

${output}"
  exit 0
fi

# Green. Report each distinct green state exactly once.
STATE_HASH="$(git diff HEAD 2>/dev/null | shasum 2>/dev/null | awk '{print $1}')"
MARKER="$REPO_ROOT/.chunk/.reported-green"
if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$STATE_HASH" ]; then
  exit 0
fi
printf '%s' "$STATE_HASH" > "$MARKER"

emit block "Sidecar validation PASSED — all gates are green. Do NOT edit any files. Report this to the user now: say that \`chunk validate\` passed on the sidecar and the change is safe to push, and summarize the gate set (install, lint, scan, test, bundle across the payments and transfers mini-apps). Here is the validation output:

${output}"
exit 0

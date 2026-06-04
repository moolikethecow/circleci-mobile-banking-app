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

if [ "$status" -eq 0 ]; then
  # All gates green — let the agent stop.
  exit 0
fi

# A gate failed. Feed the output back so the agent fixes it and validation
# re-runs. `followup_message` is the only documented `stop` output field.
msg="chunk validate failed — the sidecar caught an issue before this change can be pushed. Fix the problem(s) below, then validation will run again automatically:

${output}"

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg m "$msg" '{followup_message: $m}'
else
  python3 -c 'import json,sys; print(json.dumps({"followup_message": sys.argv[1]}))' "$msg"
fi
exit 0

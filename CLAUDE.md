# Project guidance for Claude Code

This repo ships a Chunk Sidecar inner-loop demo. A **Stop hook** runs
`chunk validate` automatically at the end of every turn — that is what gates
the code (lint, trivy, snyk, test, bundle across both mini-apps). The hook is
the star of the demo, not your analysis.

## Sanity-check requests (e.g. "quick sanity check before I push?")
- Reply in **one or two sentences**. Then end your turn immediately.
- Do **not** read files, search the repo, run shell commands, or use a todo
  list. The Stop hook (`chunk validate`) does the actual checking — let it fire.
- Do not run `chunk validate` yourself; the hook runs it.

## When validation feedback comes back red
- Fix **only** the exact issue the hook reported (e.g. an unused import) with the
  smallest possible edit. Don't refactor or touch unrelated files.
- After the edit, end your turn so the Stop hook re-runs and goes green.

## Always report the hook result — green included
- Whenever a `chunk validate` Stop-hook result is available, **state it explicitly
  in your reply**, even when everything passed. Don't go silent on green.
- On green: say so clearly and list the gate outcome, e.g.
  "Sidecar validation passed — all 12 gates green (install, lint, scan, test,
  bundle across payments + transfers)."
- On red: name the failing gate(s) and the specific error before you fix anything.
- The point of the demo is that the audience *sees* the sidecar verdict every
  turn, so never leave a validation cycle unacknowledged.

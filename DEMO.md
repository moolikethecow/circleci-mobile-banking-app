# Chunk Sidecars — Live Demo Script
### CircleCI · Generative AI Summit NYC · ~6 minutes

---

## PRE-FLIGHT (run backstage before the talk)

```bash
cd ~/code/circleci-mobile-banking-app               # the demo repo
git status                                          # confirm clean main
chunk sidecar current                               # confirm sidecar is up
chunk validate                                      # warm it (green in ~30s on a cold sidecar, ~13s warm)
./scripts/seed-broken.sh                            # apply the broken-agent state
```

Then open the agent **from inside the repo** so its stop hook activates:

- **Cursor:** open this repo folder in Cursor; the `.cursor/hooks.json` `stop` hook is already wired.
- **Claude Code:** run `claude` from inside the repo; the `.claude/settings.json` Stop hook is already wired.

Either agent runs the identical `chunk validate` loop. The rest of this script is agent-agnostic.

**Have open before you go on stage:**
- Editor with `miniapps/payments/src/App.js` visible (left half of screen)
- A second editor tab with `.chunk/config.json` and `.circleci/config.yml` side by side (for the contract beat)
- Claude Code terminal (right half of screen)
- Browser tab pre-loaded to your CircleCI pipeline page

> ⚠️ Do not run `chunk validate` again after seeding — the first failure needs to happen live.

---

## INTRO (0:00 → 0:30)

> **[Face the audience. No commands yet.]**
>
> Intro to yourself.
> Intro to SOSDR.

AI coding agents are fast. Claude Code, Cursor — they ship code at a pace no developer could match manually.

Fast doesn't mean correct.

The problem usually isn't that agents write bad code, though sometimes they do. The problem is that by the time CI tells you something is broken, the agent has moved on. The context is gone. You're debugging a change from the agent you've already forgotten.

What if validation happened *before* the commit? Before the push. Before CI sees it at all.

That's what Chunk Sidecars do. Here's how.

---

## WHAT IS THE INNER LOOP? (0:30 → 1:15)

> **[Image on screen: the two-loop diagram — Inner Loop (Plan → Code → Validate → Debug) on the left, Outer Loop (Build → Test → Deploy → Release) on the right, joined by "Change" and "Feedback" arrows.]**

Quick framing. Every change lives in two loops.

The **inner loop** — on the left — is where you actually work: plan, code, validate, debug, on your machine, in seconds. The **outer loop** — on the right — is what happens after you push: build, test, deploy, release, in CI, in minutes.

For years those were balanced. Then AI showed up and made the inner loop much faster — but because we rely on CI to validate, the validate step on the inner loop is shallow. Incomplete changes sail through the inner loop and pile up in the outer loop, where every failure costs a full CI cycle and a context switch.

> **[Point to the "Validate" node on the inner-loop side.]**

The fix isn't a faster outer loop. It's putting real validation back *here* — on the Validate step, inside the inner loop — so a change is correct before it ever becomes CI's problem.

That's the gap sidecars close.

---

## WHAT IS A SIDECAR? (1:15 → 1:45)

> **[Optional: switch to terminal, run `chunk sidecar current` and `chunk validate --list`]**

A sidecar is a remote sandbox running on CircleCI that mirrors your CI environment exactly. Same install commands. Same lint rules. Same test suite.

> **[Point to the list of gates if visible.]**

Here's mine. Twelve gates — install, lint, **scan**, test, build — across both mini-apps. Trivy and Snyk run alongside the unit tests, so a transitive CVE blocks the agent the same way a failing test does. Same commands my CircleCI pipeline runs. The difference is *when* they run.

---

## THE CONTRACT — SIDECAR ≡ CI (1:45 → 2:45)

> **[Switch to the editor tab with `.chunk/config.json` and `.circleci/config.yml` side by side.]**

People hear "runs on a sidecar" and assume it's an approximation — a linter that's *close* to CI's, tests that are *mostly* the same. That gap is where "works on my machine" lives.

Look at this. On the left, `.chunk/config.json` — what the sidecar runs. On the right, `.circleci/config.yml` — what CI runs.

> **[Point to the Snyk gate in each.]**

The sidecar's `scan-payments-snyk` gate:

```
cd miniapps/payments && snyk test --severity-threshold=high
```

The CircleCI step, *Scan: Snyk (severity high+)*:

```
cd miniapps/payments && snyk test --severity-threshold=high
```

Character for character, the same command. Same for Trivy — `trivy fs --severity HIGH,CRITICAL --exit-code 1` in both. Same install, same lint, same test, same bundle.

This isn't *similar* to CI. It **is** CI's command set, pulled forward to the inner loop.

> **[Run `chunk validate` once locally to show the green baseline before the agent gets involved.]**

---

## WHAT IS A STOP HOOK? (2:45 → 3:15)

Here's the part that makes this interesting. I'm not going to type `chunk validate` once for the rest of this demo.

The agent has a **stop hook** — a shell command that fires automatically every time the agent finishes a turn. You configure it once. In Claude Code it lives in `.claude/settings.json` (generated by `chunk init`); in Cursor it lives in `.cursor/hooks.json`. This repo ships both, wired to the same command.

Claude Code:

```json
"hooks": {
  "Stop": [
    { "hooks": [{ "type": "command", "command": "chunk validate" }] }
  ]
}
```

Cursor:

```json
"hooks": {
  "stop": [
    { "command": ".cursor/hooks/chunk-validate.sh", "loop_limit": 5 }
  ]
}
```

That's it. Every time the agent finishes a reply, the sidecar runs. If something fails, that failure is fed back into the conversation. The agent sees it. The agent fixes it. Before anything is pushed.

> **[Pause. Let that land.]**

Validation in the inner loop. Not as an afterthought. As part of the agent's lifecycle.

---

## THE DEMO (3:15 → 4:55)

> **[Screen: editor on left showing `miniapps/payments/src/App.js`, Claude Code terminal on right.]**

Here's the scenario. I asked Claude to make the Payments screen feel more welcoming. It added a welcome line and started importing `TouchableOpacity` for some interactivity it never finished.

To a human skimming the diff, this looks shippable. Let's see what the sidecar thinks.

> **[Switch to Claude Code terminal. Type:]**

```
Quick sanity check on the Payments changes before I push?
```

> **[Claude replies. Stop hook fires automatically. ~7 seconds later:]**

```
✗ lint-payments
  'TouchableOpacity' is defined but never used  no-unused-vars
```

Seven seconds. Dead import. Same lint rule CI would have caught, minutes earlier, with zero pipeline spend.

> **[Type:]**

```
go ahead
```

> **[Claude removes the unused import. Stop hook fires again and runs the full gate set — install, lint, scan, test, bundle across both mini-apps — and comes back all 12 green.]**

One fix. The agent never touched CI. The scan gates went green alongside lint and tests — vulnerability checking happens in the same loop, not as a separate PR check that runs hours later.

---

## THE PUSH (4:55 → 5:45)

> **[In the terminal, type:]**

```bash
git add miniapps/payments/
git commit -m "feat(payments): add welcome message"
git push
```

> **[Switch to the CircleCI pipeline tab in the browser. Pipeline runs. Goes green.]**

When the sidecar says green, CI agrees. First push. First pass. No pipeline failures. No re-runs. No context switching.

> **[Face the audience.]**

That's what validation in the inner loop looks like. Not faster machines. Not more parallelism. The right answer, at the right moment, before it costs you anything.

That's Chunk Sidecars.

---

## ANTICIPATED QUESTIONS

**"How does it know to run after every turn?"**
A stop hook in the agent's config. For Claude Code, `chunk init` generates `.claude/settings.json` pointing at `chunk validate`. For Cursor, `.cursor/hooks.json` runs the same command via a small wrapper. Either way the agent fires it automatically — you don't type `chunk validate`.

**"What if the sidecar and CI disagree?"**
They run the same commands. `.chunk/config.json` and `.circleci/config.yml` are the same gates. We treat them as one contract.

**"Doesn't this slow every Claude turn down?"**
By about 20–30 seconds on turns that change code, on a warm sidecar. Scans add a few seconds; the vuln DBs are pre-cached on the sidecar snapshot. That's CI's job, including security scanning, done in seconds instead of minutes, once per turn rather than once per PR.

**"Why two scanners?"**
Trivy and Snyk catch overlapping but not identical CVEs. Trivy reads the package-lock and matches against the Aqua advisory DB; Snyk does graph-aware analysis with its own DB. Running both is cheap on a warm sidecar (~5–10s combined) and the union of findings is broader than either alone.

---

## IF SOMETHING GOES WRONG

| What happened | Do this |
|---|---|
| `chunk validate` hangs past 30s | Run `chunk sidecar current` in another pane. If healthy, retry. Otherwise fall back to `cd miniapps/payments && npm run lint && npm test` |
| Stop hook didn't fire | You opened the agent outside the repo. In Cursor, open the repo folder as the workspace; in Claude Code, quit and run `claude` from inside the repo |
| Claude fixed the import before validating | Re-seed (`./scripts/seed-broken.sh`) and restart. The agent should *report* the sidecar's finding, not pre-fix it |
| CI takes longer than 2 minutes | Have a screenshot of a previous green run ready. *"In a previous run, you can see…"* |

---

## RESET BETWEEN RUNS

```bash
./scripts/reset-clean.sh
git reset --hard origin/main
```

Then re-run pre-flight from the top.

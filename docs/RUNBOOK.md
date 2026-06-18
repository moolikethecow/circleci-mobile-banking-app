# Runbook — standing up and running the Chunk Sidecar demo

This is the backstage operator guide: how to build the whole demo from a clean
machine, how to run it, and how to recover when something breaks. The on-stage
script lives in [`DEMO.md`](../DEMO.md); this file is everything that happens
*before* you walk on stage.

Fixed values for this fork:

| Thing | Value |
|---|---|
| Source repo | `AwesomeCICD/circleci-mobile-banking-app` |
| This fork | `moolikethecow/circleci-mobile-banking-app` |
| CircleCI org ID | `efc130dc-284f-4533-964e-844f5c173860` |
| Sidecar name | `moo-chunk-demo` |
| Clone path | `~/code/circleci-mobile-banking-app` |
| Branch | `chunk-sidecar-demo` |

---

## 0. Prerequisites

- macOS with Homebrew, `git`, and the GitHub CLI (`gh`) authenticated to your account.
- A CircleCI account on a **Performance or Scale plan** (sidecars are preview-gated to those plans).
- Tokens, one of each:
  - CircleCI personal API token
  - Anthropic API key
  - Snyk **service-account** token (the `snyk_uat…` style token, not the short legacy API key)
- The `gh` CLI signed in: `gh auth status` should show your account as active. If a
  stale `GITHUB_TOKEN` env var is set and invalid, `unset GITHUB_TOKEN` first.

Keep tokens in a secrets manager (1Password, etc.). Nothing below writes a token
to disk or to the repo.

---

## 1. Install the chunk CLI

Textbook:

```bash
brew install CircleCI-Public/circleci/chunk
chunk --version
```

If `brew` can't build it (e.g. Command Line Tools too old for your Xcode), grab
the release binary directly:

```bash
ARCH=$(uname -m); case "$ARCH" in arm64) A=arm64;; *) A=x86_64;; esac
gh release download -R CircleCI-Public/chunk-cli \
  -p "chunk-cli_Darwin_${A}.tar.gz" -D /tmp/chunk --clobber
tar -xzf /tmp/chunk/chunk-cli_Darwin_${A}.tar.gz -C /tmp/chunk
mkdir -p ~/.local/bin && mv /tmp/chunk/chunk ~/.local/bin/chunk && chmod +x ~/.local/bin/chunk
# ensure ~/.local/bin is on PATH (or symlink into an existing PATH dir):
ln -sf ~/.local/bin/chunk /opt/homebrew/bin/chunk
chunk --version
```

---

## 2. Authenticate chunk (one-time, interactive)

Run these at your own terminal and paste each token when prompted. They land in
your macOS keychain, so you only do this once per machine:

```bash
chunk auth set circleci
chunk auth set anthropic
chunk auth set github
chunk auth status      # all three should read ✓ Valid
```

> `chunk auth set` is interactive by design — it reads the token from a hidden
> prompt. Don't try to pipe a token into it; paste it when asked.

---

## 3. Fork + clone (skip if already done)

```bash
gh repo fork AwesomeCICD/circleci-mobile-banking-app --clone=false
mkdir -p ~/code && cd ~/code
git clone https://github.com/moolikethecow/circleci-mobile-banking-app.git
cd circleci-mobile-banking-app
git remote add upstream https://github.com/AwesomeCICD/circleci-mobile-banking-app.git
git checkout chunk-sidecar-demo   # the personalized branch
```

Pull future updates from Derry's upstream with:

```bash
git fetch upstream && git merge upstream/main
```

---

## 3b. Set up CircleCI on the fork (one-time, for the push beat)

The on-stage finale (`DEMO.md` step 4 / §8 below) pushes to the fork and shows the
CircleCI pipeline go green. That only works if **the fork itself is a CircleCI
project**. The fork builds under its own CircleCI org — `gh/moolikethecow` (org id
`49bdbed5-309d-401c-b65b-932f6c3fd56e`) — which is *separate* from AwesomeCICD, so it
cannot use AwesomeCICD's `derry-snyk` context. It needs its own `SNYK_TOKEN` context.

```bash
# 1. Follow the fork so CircleCI builds it (or click "Set Up Project" in the CircleCI UI).
curl -s -X POST -H "Circle-Token: $CIRCLE_TOKEN" \
  https://circleci.com/api/v1.1/project/gh/moolikethecow/circleci-mobile-banking-app/follow

# 2. Create the moo-snyk context in the fork's org.
curl -s -X POST -H "Circle-Token: $CIRCLE_TOKEN" -H "Content-Type: application/json" \
  https://circleci.com/api/v2/context \
  -d '{"name":"moo-snyk","owner":{"id":"49bdbed5-309d-401c-b65b-932f6c3fd56e","type":"organization"}}'
# -> note the returned context id (currently 263f7227-3630-4f21-80bd-282bc324aba0)

# 3. Put the Snyk service-account token into the context (reads from 1Password;
#    approve the Touch ID prompt). The value never touches disk or shell history.
SNYK_PAT="$(op read 'op://Private/Snyk PAT/chunk-pat')"
curl -s -X PUT -H "Circle-Token: $CIRCLE_TOKEN" -H "Content-Type: application/json" \
  https://circleci.com/api/v2/context/263f7227-3630-4f21-80bd-282bc324aba0/environment-variable/SNYK_TOKEN \
  --data-binary "$(jq -nc --arg v "$SNYK_PAT" '{value:$v}')"
unset SNYK_PAT
```

`.circleci/config.yml` references `context: moo-snyk` for both jobs (it does **not**
use `derry-snyk` — that context lives in AwesomeCICD and is unreachable from this org).

Verify: push any commit to `chunk-sidecar-demo` and confirm the pipeline goes green:

```bash
git push origin chunk-sidecar-demo
# the Payments + Transfers jobs should both end "success"; PR #1 then shows
# ci/circleci: Payments and ci/circleci: Transfers as passing checks.
```

> If the Snyk jobs 401, the `moo-snyk` context is missing `SNYK_TOKEN` (or it's the
> short legacy key, not the `snyk_uat…` service-account token) — re-run step 3.

---

## 4. Create the sidecar (one-time)

```bash
chunk sidecar create \
  --org-id efc130dc-284f-4533-964e-844f5c173860 \
  --name moo-chunk-demo
```

Save the sidecar ID it prints. It's set as the active sidecar automatically.
Confirm any time with `chunk sidecar current`.

---

## 5. Provision the sidecar (one-time, ~90s)

The sidecar starts as a clean Ubuntu box. The scan gates need Trivy and Snyk,
and Snyk needs Node. Install all three:

```bash
# Trivy
chunk sidecar ssh -- bash -lc \
  'curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin'

# Node LTS (Snyk's runtime) + Snyk CLI
chunk sidecar ssh -- bash -lc \
  'curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs'
chunk sidecar ssh -- bash -lc 'sudo npm install -g snyk'

# verify
chunk sidecar ssh -- bash -lc 'trivy --version; snyk --version'
```

> If `chunk sidecar ssh` errors that no key is registered, add one once:
> ```bash
> ssh-keygen -t ed25519 -f ~/.ssh/chunk_ai -N "" -C chunk-demo
> chunk sidecar add-ssh-key --public-key-file ~/.ssh/chunk_ai.pub
> ```

### Authenticate Snyk on the sidecar (one-time)

The Snyk gate runs `snyk test`, which needs auth available on the sidecar. Pass
the token through the SSH session's environment (so it never sits in your shell
history) and persist it to Snyk's config store:

```bash
chunk sidecar ssh -e SNYK_TOKEN="$(op read 'op://Private/Snyk PAT/chunk-pat')" -- bash -lc '
  mkdir -p ~/.config/configstore
  printf "{\"api\":\"%s\"}" "$SNYK_TOKEN" > ~/.config/configstore/snyk.json
  chmod 600 ~/.config/configstore/snyk.json
  snyk whoami --experimental
'
```

The last line should print your Snyk account email. This persists on the
sidecar, so you only do it once.

---

## 6. Warm the sidecar

```bash
chunk validate
```

First run is ~2–4 minutes (npm ci from scratch on the sidecar, Trivy downloads
its vuln DB). After that, runs are ~60s warm. You should see **all 12 gates
green** and an exit code of 0:

```
install-payments, install-transfers,
lint-payments, lint-transfers,
scan-payments-trivy, scan-transfers-trivy,
scan-payments-snyk, scan-transfers-snyk,
test-payments, test-transfers,
bundle-payments, bundle-transfers
```

If a run dies mid-gate with `ssh exec: wait: remote command exited without exit
status or exit signal`, that's a transient sidecar SSH drop, not a gate failure
— just re-run `chunk validate`.

---

## 7. Verify the broken/clean cycle (rehearsal)

```bash
./scripts/seed-broken.sh
chunk validate            # expect lint-payments to FAIL (unused TouchableOpacity import)
./scripts/reset-clean.sh
chunk validate            # expect all 12 gates green again
```

This is the exact state the live demo relies on. If `seed-broken` doesn't trip
`lint-payments`, stop and investigate before going on stage.

---

## 8. Run the live demo

Pre-flight, backstage:

```bash
cd ~/code/circleci-mobile-banking-app
git status                 # confirm clean
chunk sidecar current      # confirm sidecar is up
chunk validate             # warm it (green)
./scripts/seed-broken.sh   # apply the broken-agent state
```

Then open your agent **from inside the repo** so its stop hook activates:

- **Cursor:** open this repo folder as the Cursor workspace. The `.cursor/hooks.json`
  `stop` hook runs `.cursor/hooks/chunk-validate.sh` after every agent turn.
- **Claude Code:** run `claude` from inside the repo. The `.claude/settings.json`
  Stop hook runs `chunk validate` after every turn.

> If you open the agent from outside the repo, the hook won't fire. Both hooks
> run the identical `chunk validate` loop, so the on-stage beat is the same in
> either agent.

Then follow [`DEMO.md`](../DEMO.md) for the on-stage walkthrough. The beat:

1. Ask Claude for a "quick sanity check on the Payments changes."
2. Claude replies; the **Stop hook auto-runs `chunk validate`** — `lint-payments`
   comes back red on the unused import. You never type `chunk validate`.
3. Say "go ahead." Claude removes the import; the Stop hook fires again and all
   12 gates go green.
4. `git commit` + `git push`, switch to the CircleCI pipeline tab — it goes
   green first try. *"When the sidecar says green, CI agrees. First push, first pass."*

Reset between runs:

```bash
./scripts/reset-clean.sh
git reset --hard origin/main   # only if you committed during a run
```

---

## How the contract works (why this is believable)

- `.chunk/config.json` defines the 12 gates the sidecar runs.
- `.circleci/config.yml` runs the **same commands, character-for-character** —
  install / lint / Trivy / Snyk / test / bundle, for both mini-apps.
- A stop hook fires `chunk validate` after every agent turn, wired for both
  agents: `.claude/settings.json` (`Stop` hook, plus a `PreToolUse` hook on
  `git commit`) for Claude Code, and `.cursor/hooks.json` → `.cursor/hooks/chunk-validate.sh`
  for Cursor. The Cursor hook feeds gate failures back to the agent as a
  `followup_message` and re-runs up to `loop_limit` times.

That 1:1 match is the whole story. **Do not edit `.chunk/config.json` or
`.circleci/config.yml` independently** — if they drift, "sidecar green" stops
meaning "CI green" and the demo's claim breaks. If you change a gate, change it
in both files in the same commit.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `chunk validate` hangs forever with no output (non-interactive shell/CI) | chunk does a blocking stdin read to detect a Claude Code hook payload. In a real terminal this is fine. In scripts/CI, redirect stdin: `chunk validate < /dev/null`. |
| `ssh exec: wait: remote command exited without exit status…` | Transient sidecar SSH drop on a long step (usually a bundle). Re-run `chunk validate`. |
| Snyk gate 401 / "credentials not recognized" | Wrong Snyk token (the short legacy API key won't work) or auth not persisted on the sidecar. Re-run the Snyk auth step in §5 with the `snyk_uat…` service-account token. |
| `chunk sidecar ssh` says no SSH key | Generate `~/.ssh/chunk_ai` and `chunk sidecar add-ssh-key` (see §5 note). |
| Stop hook didn't fire | You opened the agent outside the repo. Cursor: open the repo folder as the workspace and check the **Hooks** settings tab / output channel. Claude Code: quit and run `claude` from inside the repo. |
| Cursor `stop` hook not loading | Cursor watches `.cursor/hooks.json` and reloads on save; if it still doesn't load, restart Cursor. Confirm `.cursor/hooks/chunk-validate.sh` is executable (`chmod +x`). |
| `gh`/git push rejected with token error | A stale invalid `GITHUB_TOKEN` env var is shadowing your keychain login. `unset GITHUB_TOKEN`. |
| Sidecar feels cold / first validate very slow | Expected on first run (npm ci + Trivy DB). Warm it before going on stage. |

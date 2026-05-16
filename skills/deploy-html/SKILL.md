---
name: deploy-html
description: Use this skill ANY time the user wants to put an HTML file online, get a shareable link, ship a page, host something, "make this live", "send this to someone", "give me a URL for this", "deploy this", "publish", or asks "how do I share this HTML". Also triggers on "set up Vercel", "ship to vercel", or any mention of getting a link for a generated HTML file. Handles first-time Vercel setup end-to-end (Node check, CLI install, auth) in plain language for non-technical users. After first setup, every later deploy is silent — just returns the URL. Falls back to local-save with manual upload instructions if anything breaks.
---

# deploy-html

Take any HTML file (or a folder with index.html) and put it on a live URL via Vercel.

**Critical architecture note:** Operational logic (env checks, auth polling, deploy state) lives in an executable shell script — `shared/lib/deploy.sh` — NOT in this prompt. Your job here is:

1. Ask the user the right plain-language setup questions (first run only).
2. Invoke `deploy.sh` with the right arguments.
3. Translate its output into a clean, brief message back to the user.

**You must not re-implement what the script already does.** Don't shell out `vercel` commands yourself; call the script. The script handles retries, phase tracking, auth polling, URL capture, fallbacks, and diagnostic file writing.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` — for user name / company (used in project naming).
2. Read `../../shared/design-tokens.css` — not used directly, but the file you're deploying probably uses them.
3. Read `## User Preferences` AND `## Saved Config` at the bottom of this file.
4. Locate `deploy.sh`. In order of preference:
   - `$HTML_SKILLS_LIB/deploy.sh` if `HTML_SKILLS_LIB` is set.
   - `~/.claude/skills/html-skills/shared/lib/deploy.sh`
   - `~/.codex/skills/html-skills/shared/lib/deploy.sh`
   - `../../shared/lib/deploy.sh` (relative to this SKILL.md when running from a repo clone)

   Store the resolved path in a shell variable `DEPLOY_SH` for the rest of this run.

5. Run `bash "$DEPLOY_SH" status` once and read the output. The `phase:` field is the source of truth for whether setup is needed:
   - `fresh` or `awaiting-auth` → run first-time setup (Step 1).
   - `ready` or `deployed` → skip Step 1 entirely. Go to Step 3.

## Step 1: First-Time Setup (only if phase is fresh/awaiting-auth)

Ask the user, in plain language, one question at a time. Save each answer to `Saved Config` IMMEDIATELY (don't wait for the full walkthrough to finish, in case something fails).

**Question 1 — file:**
> *"Cool, let's get this online. Which HTML file should I ship? (paste the path or say 'the one we just made')"*

**Question 2 — project name:**
> *"What should I call your Vercel project? Something short — like 'outreach-pages' or '`{user-company}-decks`'. Founders only see the subdomain so keep it clean."*

**Question 3 — custom domain (optional):**
> *"Got a custom domain you want to use, or is the free `*.vercel.app` link fine?"*

**Question 4 — notification webhook (optional):**
> *"Want me to ping a Slack/Discord channel whenever a page goes live? Paste the webhook URL or skip."*

**How to ask — coworker, not robot:**

Good: *"Cool, let's get this online. Which HTML file — the one we just made, or paste a path?"*
Bad: *"Provide source_file_path parameter for deployment artifact."*

Good: *"Got a custom domain you want to use, or is the free vercel.app link fine?"*
Bad: *"Configure custom_domain (optional, leave empty for default subdomain)."*

## Step 2: Run Setup (ONE shell call, no user prompts during)

Once you have Q1–Q4 answers, run **one** command. This is critical for the bug fix:

```bash
bash "$DEPLOY_SH" setup \
  --project "<project-name>" \
  ${custom_domain:+--domain "$custom_domain"} \
  ${webhook:+--webhook "$webhook"}
```

The script handles everything: Node install, Vercel CLI install, browser-open login, **polling `vercel whoami` every 5s for up to 90s until auth lands**, and project linking. It will return when the phase is `ready`, or fail loudly with an exit code AND a diagnostic file at `~/.cache/html-skills/last-error.md`.

**Do NOT pause for user input between `setup` and `ship`.** Once setup returns 0, immediately proceed to Step 3.

## Step 3: Ship (silent on success, plain-language on failure)

```bash
bash "$DEPLOY_SH" ship "<html-file>"
```

The script:
- Re-verifies auth quickly (auth can expire between runs).
- Creates a temp project dir, writes `index.html` + `vercel.json`.
- Runs `vercel link` (idempotent — re-uses the project).
- Runs `vercel --prod --yes` with a 180s timeout.
- Parses the URL robustly (regex + `vercel ls --json` fallback).
- Aliases the custom domain if configured.
- Pings the webhook if configured.
- Saves the deploy URL + timestamp to state.
- Cleans up the temp dir.
- Emits the URL on the LAST line of stdout.

**Capture the URL from the last line.** Use that in your message back to the user.

## Step 4: Report Back

ALWAYS plain language. Never paste CLI output. Two lines max.

**Success:**
> *"✓ Live at: https://acme-pitch.vercel.app — copy that and DM John. (Also pinged your Slack channel.)"*

**With custom domain:**
> *"✓ Live at: https://pitch.yourcompany.com (and at the vercel.app backup URL if you need it: …)"*

## Step 5: Handle Failures

If `deploy.sh` exits non-zero, it has already written `~/.cache/html-skills/last-error.md`. Your job:

1. Read `~/.cache/html-skills/last-error.md`.
2. Translate the failure into one plain-language line.
3. Decide: retry once silently, or fall back to local-save.

**Common exit codes from `deploy.sh`:**

| Code | Meaning | What you do |
|------|---------|-------------|
| 10   | Node or Vercel CLI couldn't install | Tell user, point at `last-error.md`, stop. |
| 11   | Auth didn't complete in 90s | *"Still need a sec? Type 'go' once you're signed in."* — then re-run `setup`. |
| 12   | Link or deploy failed | Retry `ship` once silently. If it fails again, fall back. |
| 124  | A subcommand timed out | Treat like 12. |
| 20   | User aborted | Quiet exit. |

**Local-save fallback:**
- Copy the file to `~/Downloads/<filename>`.
- *"Saved locally to `~/Downloads/acme-pitch.html`. When you're ready, drag it into [vercel.com/new](https://vercel.com/new) and you'll get a link in 30 seconds."*

## Step 6: Update Preferences (rarely) and Saved Config (always)

- `Saved Config` mirrors the state file (`~/.cache/html-skills/state/deploy.json`) — the script is the source of truth, but you can update this section so it stays human-readable.
- `User Preferences` only changes for consistent patterns (e.g. user always skips Slack webhook → drop that question).

## Common Mistakes to Avoid

1. **Re-implementing deploy logic in prose.** The script is the source of truth. Call it.
2. **Pausing between `setup` and `ship`.** Once setup is fired and returns 0, ship immediately. No "ready to deploy?" check-in.
3. **Pasting raw CLI output.** The script already translates failures and writes `last-error.md`. Read that, summarize, move on.
4. **Asking setup questions every time.** If `bash "$DEPLOY_SH" status` says phase is `ready` or `deployed`, skip Step 1.
5. **Forgetting auth can expire.** The script handles it, but if you're tempted to call `vercel` directly: don't.
6. **Auto-aliasing a custom domain that isn't DNS-ready.** The script wraps this in retry/warn already; trust it.

---

## User Preferences (Auto-Updated)

<!--
  Only true USER preferences here. Setup state goes in Saved Config below.
  Rewritten after a successful run. Max 20 lines.
-->

- Slack/Discord webhook for deploys: [not yet learned — ask first time only]
- Open browser to URL after deploy: ask (default)
- Last updated: [never]

---

## Saved Config (Human-Readable Mirror)

<!--
  This block is a human-readable mirror of ~/.cache/html-skills/state/deploy.json.
  The JSON file is the source of truth; this section gets refreshed on a successful run.
-->

- Setup complete: no
- Project name: [not set]
- Custom domain: [none]
- Notification webhook: [none]
- Last deploy URL: [none]
- Last deploy timestamp: [never]
- State file: `~/.cache/html-skills/state/deploy.json`

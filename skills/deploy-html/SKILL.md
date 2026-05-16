---
name: deploy-html
description: Use this skill ANY time the user wants to put an HTML file online, get a shareable link, ship a page, host something, "make this live", "send this to someone", "give me a URL for this", "deploy this", "publish", or asks "how do I share this HTML". Also triggers on "set up Vercel", "ship to vercel", or any mention of getting a link for a generated HTML file. Handles first-time Vercel setup end-to-end (Node check, CLI install, auth) in plain language for non-technical users. After first setup, every later deploy is silent — just returns the URL. Falls back to local-save with manual upload instructions if anything breaks.
---

# deploy-html

Take any HTML file (or a folder with index.html) and put it on a live URL via Vercel. First run is a guided walkthrough — install Node, install Vercel CLI, log in, deploy. Every later run is silent. Errors are translated to plain language. Falls back to local-save + manual instructions if anything fails.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` — for user name / company (used in project naming).
2. Read `../../shared/design-tokens.css` — not used directly, but the file you're deploying probably uses them.
3. Read `## User Preferences` AND `## Saved Config` at the bottom of this file.
4. **If `Saved Config → Setup complete: yes`** — skip ALL of Step 1. Go straight to Step 3 (deploy silently).

## Step 1: First-Time Setup (only if Saved Config is empty)

Walk the user through, one question at a time. Each prompt should sound like a coworker, not a wizard.

**Question 1 — what file/folder?**
> *"Cool, let's get this online. Which HTML file should I ship? (paste the path or say 'the one we just made')"*

**Question 2 — project naming**
> *"What should I call your Vercel project? Something short — like '`outreach-pages`' or '`{user-company}-decks`'. Founders only see the subdomain so keep it clean."*

**Question 3 — custom domain (optional)**
> *"Got a custom domain you want to use, or is the free `*.vercel.app` link fine? (totally fine for outreach — most founders click without thinking about the domain)"*

**Question 4 — notification webhook (optional)**
> *"Want me to ping a Slack/Discord channel whenever a page goes live? Paste the webhook URL or skip."*

Save every answer to `## Saved Config` IMMEDIATELY as it comes in — don't wait for the full walkthrough to finish, in case something fails.

**How to ask — coworker, not robot:**

Good: *"Cool, let's get this online. Which HTML file should I ship — the one we just made, or paste a path?"*

Bad: *"Provide source_file_path parameter for deployment artifact."*

Good: *"Got a custom domain you want to use, or is the free vercel.app link fine? (most founders click without thinking about the domain)"*

Bad: *"Configure custom_domain (optional, leave empty for default subdomain)."*

## Step 2: Environment Checks (silent unless something is missing)

Run these in order. Translate everything to plain language.

**2a. Node.js check**
- Run `node --version`. If exit 0 and >= 18, silently pass.
- If missing or < 18:
  > *"Looks like Node isn't installed (or is too old). Vercel needs it. Want me to install it via Homebrew? (it's free, takes about a minute)"*
- On yes: detect OS. macOS → `brew install node`. Linux → use system package manager (apt/dnf). Windows → instruct user to install via [nodejs.org](https://nodejs.org) and pause.
- If Homebrew is missing on macOS, install it first with the official one-liner, asking permission.
- **Never paste raw terminal output to the user.** Just: *"Node's installed, we're good. Moving on..."*

**2b. Vercel CLI check**
- Run `vercel --version`. If found, silently pass.
- If missing: *"Installing the Vercel command-line tool now — takes about 20 seconds."*. Run `npm install -g vercel`. On permission error, retry with `sudo` asking first.
- Save the resolved path (`which vercel`) to `Saved Config → Vercel CLI`.

**2c. Auth check**
- Run `vercel whoami`. If returns email, silently pass.
- If not authed:
  > *"One last thing — you need to log in to Vercel. I'll open the browser for you. Pick whichever account you want pages deployed under."*
- Run `vercel login`. This opens a browser. Wait for completion.
- Once authed, save email to `Saved Config → Auth account`.

## Step 3: Deploy

Once environment is ready (silently every later run, after walkthrough on first):

1. Create a temp project directory: `~/.cache/html-skills/deploy-{timestamp}/`.
2. Copy the source HTML in as `index.html` (rename if needed — the source filename is preserved in metadata, not URL).
3. Write a minimal `vercel.json`:
   ```json
   { "cleanUrls": true, "trailingSlash": false }
   ```
4. From inside that directory, run:
   ```
   vercel --prod --yes --name {project-name-from-config} --scope {auth-account}
   ```
5. Capture the URL from stdout (last line that starts with `https://`).
6. If a custom domain is configured and not yet aliased, run `vercel alias set <deployment-url> <custom-domain>`.
7. Clean up the temp directory.
8. If webhook configured, POST `{ "text": "New page live: <url>" }` to it.
9. Save to `Saved Config → Last deploy`: URL, source filename, timestamp.

## Step 4: Report Back

ALWAYS plain language. Never paste CLI output.

**Success:**
> *"✓ Live at: https://acme-pitch.vercel.app — copy that and DM John. (Also pinged your Slack channel.)"*

**With custom domain:**
> *"✓ Live at: https://pitch.yourcompany.com (and at the vercel.app backup URL if you need it: ...)"*

Brief, two lines max. Don't summarize what you did unless asked.

## Step 5: Errors — Always Plain Language

Translate every error to a one-line plain message + a one-line "what I'm doing about it".

**Auth expired / 401:**
> *"Your Vercel login expired — opening browser to re-login real quick."*  
Run `vercel login`, retry deploy once.

**Build error:**
> *"Hit a small issue building the page — let me try once more."*  
Retry once silently. If it fails again, fall back to local-save (below).

**Network / timeout:**
> *"Internet seems flaky. Saving the file locally for now — you can deploy it later by running this skill again."*  
Fall back to local-save.

**Custom domain not yet pointed:**
> *"Your custom domain isn't pointing at Vercel yet. Here's the one-time DNS setup: [link]. For now, the page is live at the vercel.app URL."*

**Disk / permission:**
> *"My temp folder isn't writable. Trying your home directory instead..."*  
Retry with `~/html-skills-deploy/` instead.

**Local-save fallback:**
- Copy the file to `~/Downloads/{filename}` (or current dir).
- Tell user: *"Saved locally to `~/Downloads/acme-pitch.html`. When you're ready, drag it into [vercel.com/new](https://vercel.com/new) and you'll get a link in 30 seconds."*

## Step 6: Update Saved Config (always) and User Preferences (rarely)

- `Saved Config` updates EVERY run — it's the source of truth for setup state.
- `User Preferences` only changes for consistent patterns (e.g. user always skips Slack webhook → drop the question).

## Common Mistakes to Avoid

1. **Pasting raw `vercel` output** — translate everything. The user is non-technical.
2. **Asking setup questions every time** — if `Saved Config → Setup complete: yes`, deploy SILENTLY. No questions.
3. **Forgetting to handle the case where Vercel CLI exists but auth is stale** — `vercel --version` passing doesn't mean `whoami` will.
4. **Storing webhook URLs in `User Preferences`** — they're config, not preferences. Goes in `Saved Config`.
5. **Failing loudly** — every error needs a graceful path (retry, fallback, or honest "here's what to do manually").
6. **Auto-aliasing a custom domain that isn't DNS-ready** — check first or wrap in try/catch.

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

## Saved Config (Auto-Updated)

<!--
  Setup state, not preferences. Updated EVERY run when something changes.
  If "Setup complete" is yes, skip all first-time questions.
-->

- Setup complete: no
- Node.js: [not detected yet]
- Vercel CLI path: [not detected yet]
- Auth account: [not authed yet]
- Project name: [not set]
- Custom domain: [none]
- Notification webhook: [none]
- Last deploy URL: [none]
- Last deploy source: [none]
- Last deploy timestamp: [never]

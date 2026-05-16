---
name: outreach-html
description: Use this skill ANY time the user wants to reach out to, pitch, DM, message, contact, or "send something to" a specific founder, prospect, or person on behalf of their company. Triggers include "outreach to John at Acme", "pitch this founder", "send Sarah from X a page", "DM the CEO of Y", "make a personalized page for [name]", "do an outreach for me", "I want to reach out to X". This is the full pipeline — research the target, build a personalized animated HTML page (with optional OTP gate and workflow comparison), deploy it to Vercel, and hand back the link + a suggested LinkedIn DM. SELF-CONTAINED — does NOT require research-html, present-html, or deploy-html to be installed. Default to this skill whenever the goal is "reach out to a specific person with a tailored page".
---

# outreach-html

End-to-end personalized outreach pipeline. Research the target → build a one-of-one HTML page that shows you understand their business → deploy to Vercel → hand back URL + LinkedIn DM suggestion. Fully self-contained — duplicates inline what research-html, present-html, and deploy-html do, so it works even if those aren't installed.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` — name, company, pitch angle, brand voice are LOAD-BEARING here. This whole pipeline personalizes around them.
2. Read `../../shared/design-tokens.css` — copy into the HTML page's `<style>` block.
3. Read `## User Preferences` AND `## Saved Config` at the bottom of this file.
4. If `profile.md` is mostly `[will be learned]`, you MUST ask Step 1's "About your company" block this run, then write it to profile.md.

## Step 1: Gather What You Need

**Always ask (every run):**
- Who are we reaching out to? (founder name + company)
- Their LinkedIn or company URL, if you have it (saves research time)

**First use only — about THEIR company (these go to `shared/profile.md`):**
- What's your company called?
- One-liner: what do you do?
- Your pitch angle — what's the wedge you usually lead with?
- Brand voice — warm/sharp/playful/technical?
- Any signature phrases or things you always include (booking link, calendar, etc)?

**First use only — about the outreach pattern:**
- Should pages always have an OTP gate? (default yes — feels exclusive)
- Should pages always include the animated workflow comparison? (default yes — highest-impact section)
- Custom domain to use, or vercel.app default?

**Every run (quick check-in):**
- Anything different this time? (e.g. "they're technical, lead with metrics" or "skip the workflow, just a hero + CTA")

**How to ask — coworker, not robot:**

Good: *"Okay — reaching out to John at Acme. Drop me his LinkedIn if you have it, otherwise I'll go find it. And anything different this time, or same vibe as the Stripe one?"*

Bad: *"Provide target_name, target_company, target_linkedin_url, and outreach_modifiers."*

Good: *"This is your first run — quick one: what does YOUR company do in one line, and what's the angle you usually pitch with?"*

Bad: *"Initialize company profile parameters."*

## Step 2: Research The Target (INLINE — no dependency on research-html)

Use WebSearch, WebFetch, and any research tools available. Aim for **deep enough to write 2-3 specific, surprising lines about them** — not a Wikipedia entry.

**Must find:**
- Company: what they actually do (in the founder's own words if possible — pull from their site's hero or their LinkedIn About).
- Size & stage (employees, funding round, year founded).
- Founder background — previous roles, their public voice (Twitter/LinkedIn posts, podcasts).
- Their current process for the area YOU'RE selling into. (e.g. if you sell AI outreach, how are they doing outreach today? Job postings, sales hires, tools mentioned anywhere — all clues.)
- Pain points — from reviews, job postings, founder's complaints on socials.

**Try to find:**
- Recent news / product launches (last 3 months)
- Tools/tech they use (BuiltWith, GitHub, job descriptions)
- Who they consider competitors

**Then SUMMARIZE to the user and PAUSE for confirmation:**

> *"Done digging. Here's the gist:*
> *• Acme is a 40-person Series A doing AI customer support, founded by John (ex-Stripe Support Lead).*
> *• They're hiring 3 SDRs right now — looks like outbound is mostly manual cold email.*
> *• John posts weekly on LinkedIn about 'humanizing support' — values matter to him.*
> *• Pain point: their G2 reviews mention slow response times during onboarding.*
>
> *Sound right? Anything to add before I build the page?"*

WAIT for the user's reply. They might correct you ("actually they just hired a head of growth, skip the SDR angle"). Bake corrections in before moving on.

## Step 3: Build The Personalized HTML Page

Single self-contained `.html` file. Tokens copied from `shared/design-tokens.css`. Google Fonts in `<head>`.

**Section order (all full-viewport, scroll-snap proximity):**

1. **OTP Gate** (if enabled)
   - Big: company name + "John, this is for you"
   - One-line teaser: *"A 90-second look at where Acme's outreach could be in 6 weeks"*
   - 4-digit code input (digits-only, monospace, auto-advance)
   - Correct → smooth fade + content reveal. Wrong → shake + danger border, reset after 600ms. 3 wrong → friendly "double-check the code from your DM?"

2. **Hero** — headline references THEIR specific situation. Pull from research.
   - GOOD: *"You're hiring 3 SDRs to do what could take 1."*
   - BAD: *"Welcome to your personalized pitch from [Your Company]."*

3. **"We Get You"** — 3-4 cards, each citing a real research finding.
   - GOOD card: *"You wrote last week: 'we'll never sacrifice human-feeling for speed.' We built our outreach engine around that exact tension — speed AND voice, not one or the other."*
   - BAD card: *"We understand your business needs."*

4. **The Problem** — describe THEIR current process, with specifics from research.
   - "Right now your team is sending ~80 cold emails/day per SDR. After 2 weeks of follow-up, reply rate sits around 1.2%. ..." (numbers from research, OR honest estimates flagged as "from typical SaaS benchmarks at your size")

5. **Workflow Comparison** (if enabled) — the animated race. See full implementation spec below.

6. **The Solution** — what you do, in 3-4 sentences. Bullet-light. Reference how it solves THEIR specific problem, not generic features.

7. **How It Works** — 3 steps max. Visual: numbered cards with icons, connecting arrows.

8. **Results / Proof** — metrics at THEIR scale, not yours.
   - GOOD: *"For a 40-person Series A like Acme, this typically replaces 2 SDR hires (~$200k/year) with $X/month of tooling."*
   - BAD: *"Our customers see 10x improvement."*

9. **Next Step** — ONE button, ONE ask. Calendly link or DM reply.
   - Headline: *"15 minutes, John. Pick a slot."*
   - Button: bold, `accent-primary`, with subtle glow.

### Workflow Comparison — Full Implementation Spec

Two vertical SVG node graphs side-by-side, racing.

**Build the data:** From research, sketch THEIR current process step-by-step. Then sketch the same process WITH your service. Both must have real labels, real durations.

**Visual:**
- Each node: circle (r=36px), icon (centered SVG), step number badge (top-right), label below, duration badge bottom (`"6 days"`, `"4 min"`).
- Path between nodes: SVG bezier, `stroke-width: 2`, `--border-soft`. Active edge: `accent-primary`, animated dash offset.
- Section title pulls real names: *"How [Acme] does it now vs with [YourCo]"*.

**Animation (requestAnimationFrame loop):**
- Slow pipeline: particles 4-6s per edge, r=4, `text-muted`, slight wobble.
- Fast pipeline: particles 0.4-0.8s per edge, r=3, `accent-secondary`, with trail (3 fading copies).
- Active node: dashed `accent-primary` ring spinning (8s linear rotation). Pulsing halo: `box-shadow` breathing 0.4 → 1.0 opacity over 1.5s.
- On node complete: 8-12 particles burst outward, fade over 600ms, then particles start traveling to next node.

**Bottleneck markers:**
- Any old-pipeline node > 1 day duration: ⚠️ in `accent-warning` + slow red halo pulse.

**Controls:**
- Big "▶ Run Comparison" button beneath the graphs. Disabled while running.
- "↺ Replay" button appears after first finish.
- Both pipelines start on the same click.

**Live clocks above each pipeline:**
- Old: "Day X of N" — scaled so a day = ~1 second.
- New: "Minute X of N" — scaled so a minute = ~0.1 second.

**Win banner (auto-appears):**
- When fast finishes while slow is still mid-process, banner slides down from top of section: *"✓ With us, John's team is done. The other side is still on step 3 of 7."*

**Final metrics panel (appears when both finish):**
- 3 stat cards, count up from 0 over 1.2s.
- Card 1: "Time saved" — "12 days → 8 minutes"
- Card 2: "Steps eliminated" — "7 → 3"
- Card 3: "Bottlenecks removed" — "2 → 0"

**Accessibility:**
- Respect `prefers-reduced-motion` — drop particles & spin, keep state changes.
- Every node has `<title>` for screen readers.

### Personalization Rules — non-negotiable

- **Tone matching:** detect founder's communication style from research.
  - Technical (engineering background, writes about systems) → more data, fewer adjectives, code-ish details.
  - Business (sales/ops background, writes about growth) → more ROI, more story, more "your team will feel this".
  - Creative (design background, writes about taste) → more visual, more whitespace, more references to their aesthetic.
- **Their words back to them:** if research pulled a real quote or phrase the founder uses publicly, reuse it (carefully — once, not five times).
- **No generic ANY** — generic hero, generic CTA, generic "we understand". If a section can't be personalized, cut it.

### Design rules

- Dark theme default. Use tokens — no hardcoded hex.
- Never use placeholder text ("Lorem ipsum", "[insert their pain here]"). If a section can't be filled with real research, cut it.
- Never use stock images or emoji clipart. Typography + color + layout only.
- Scroll progress bar at top (`accent-primary`).
- One pop accent, used sparingly.
- Mobile-first. Workflow stacks vertically under 720px, animations preserved.
- Page loads <1s on 4G. No external JS libs beyond what's inline.

## Step 4: Deploy (INLINE — no dependency on deploy-html)

Use the saved Vercel config from `## Saved Config` below. If not set up:

**First run — quick setup walkthrough:**

1. Check Node: `node --version`. If missing/old → ask permission, `brew install node` (macOS) or appropriate.
2. Check Vercel CLI: `vercel --version`. If missing → `npm install -g vercel`.
3. Check auth: `vercel whoami`. If not authed → `vercel login` (opens browser).
4. Ask once: project name (default: `{user-company}-outreach`), custom domain (optional), Slack/Discord webhook (optional).
5. Save everything to `## Saved Config` IMMEDIATELY.

**Every later run — silent deploy:**

1. Create temp dir `~/.cache/html-skills/outreach-{timestamp}/`.
2. Copy HTML in as `index.html`.
3. Minimal `vercel.json`: `{ "cleanUrls": true, "trailingSlash": false }`.
4. `vercel --prod --yes --name {project-name}`.
5. Capture URL. Alias to custom domain if set.
6. Cleanup. Ping webhook if set.
7. Save to Saved Config → Last deploy.

**Errors → plain language:**
- Auth expired → *"Re-login real quick"*, run `vercel login`, retry.
- Build error → silent retry once, then fallback to local save.
- Network → *"Saved locally to ~/Downloads/{file}. Drag it into vercel.com/new when you're back online."*

## Step 5: Hand Back The Deliverable

Final message to user has FOUR things:

1. **The live URL** — one line, copyable.
2. **The OTP code** — if used, one line, big and obvious.
3. **A one-line page summary** — what's in it, vibe.
4. **A suggested LinkedIn DM** — 2-4 sentences max, casual, references the page link.

Example:

> *"✓ Live: https://acme-john.outreach.yourcompany.com*  
> *✓ Code: 4271*
>
> *Page is 7 sections — hero hits on the SDR-hiring angle, includes the workflow race showing 12 days → 8 min for their outbound, ends with a Calendly link.*
>
> **Suggested DM to John:**  
> *"John — saw you're hiring 3 SDRs. Built you a quick page on what that could look like with our setup instead. Code's 4271: [link]. 90 seconds, then you tell me if it's worth a call."*"

Then ask: *"Want any tweaks before you send it?"*

## Step 6: Update Preferences & Profile

**`shared/profile.md`** — update IMMEDIATELY when you learn company-level info (company name, pitch angle, brand voice, signature phrases). These are global, used by every skill.

**`## User Preferences`** (this file, at bottom) — rewrite at END of successful run. Only for consistent patterns:
- "Always OTP gated" → if user said yes 2+ runs in a row.
- "Always workflow comparison" → same.
- "Always lead with [angle]" → if pitch angle is now stable.

**`## Saved Config`** (this file, at bottom) — update EVERY run with deploy state.

DO NOT update preferences for one-off tweaks ("make this one shorter, just this time").

## Common Mistakes to Avoid

1. **Skipping the research summary checkpoint** — always pause for confirmation BEFORE building the page. Founders catch errors there.
2. **Generic hero headlines** — the headline is the most expensive viewport. It MUST reference something specific to them.
3. **Inventing numbers** — if you don't know their reply rate, say "typical for your size" and flag it. Never make up a stat to make a stat card look full.
4. **Pasting `vercel` output to the user** — they're non-technical. Translate everything.
5. **Asking setup questions after first run** — if Saved Config has a deploy URL, just ship. No questions.
6. **Forgetting to ask the LinkedIn URL** — having it saves 5+ minutes of research.
7. **Using stock images or emoji clipart** — typography & color only. The page should feel one-of-one.

---

## User Preferences (Auto-Updated)

<!--
  Rewritten after every successful run. Max 20 lines.
-->

- OTP gating default: ask (until learned)
- Workflow comparison default: ask (until learned)
- Hero style: specific-fact-from-research (default)
- DM length: 2-4 sentences (default)
- Tone matching from research: yes (default)
- Last updated: [never]

---

## Saved Config (Auto-Updated)

<!--
  Setup + deploy state. Updated EVERY run when something changes.
-->

- Setup complete: no
- Vercel CLI path: [not detected]
- Auth account: [not authed]
- Project name: [not set]
- Custom domain: [none]
- Notification webhook: [none]
- Last deploy URL: [none]
- Last target: [none]
- Last deploy timestamp: [never]

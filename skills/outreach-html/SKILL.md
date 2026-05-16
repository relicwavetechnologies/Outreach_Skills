---
name: outreach-html
description: Use this skill ANY time the user wants to reach out to, pitch, DM, message, contact, or "send something to" a specific founder, prospect, or person on behalf of their company. Triggers include "outreach to John at Acme", "pitch this founder", "send Sarah from X a page", "DM the CEO of Y", "make a personalized page for [name]", "do an outreach for me", "I want to reach out to X". This is the full pipeline — research the target, build a personalized animated HTML page (with optional OTP gate and workflow comparison), deploy it to Vercel, and hand back the link + a suggested LinkedIn DM. SELF-CONTAINED — does NOT require research-html, present-html, or deploy-html to be installed. Default to this skill whenever the goal is "reach out to a specific person with a tailored page".
---

# outreach-html

End-to-end personalized outreach pipeline. Research the target → build a one-of-one HTML page that shows you understand their business → deploy to Vercel → hand back URL + LinkedIn DM suggestion. Fully self-contained — duplicates inline what research-html, present-html, and deploy-html do, so it works even if those aren't installed.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` (and `~/.cache/html-skills/memory/profile.json` if present — JSON wins). Pitch angle, brand voice, and signature phrases are LOAD-BEARING here.
2. Read `../../shared/design-tokens.css` — copy into the HTML page's `<style>` block.
3. Read `../../shared/SCHEMAS.md` once per session — that's the memory contract.
4. Read `../../shared/components/{otp-gate,sources-footer,confidence-dot,insight-block}.html` — paste these into the HTML you generate where applicable.
5. Read `## User Preferences` AND `## Saved Config` at the bottom of this file.
6. If `profile.md`/`profile.json` are mostly empty, you MUST ask Step 1's "About your company" block this run, then write to BOTH.
7. **Check for existing target file.** Slugify the company name. If `~/.cache/html-skills/memory/targets/<slug>.json` exists:
   - **Read it** — facts, people, public quotes, past_outreach are all gold.
   - Check `past_outreach[]` for prior attempts to THIS person. If found, surface to user: *"You DMed John on May 17 with the SDR-hiring angle, no reply yet. Want a different angle this time?"* and require an angle different from any in `do_not_use_angles` or unsuccessful past outreaches.
   - If `research_freshness_score > 0.7` and `last_researched` within 14 days, **skip Step 2's research entirely** and go straight to Step 3 with stored facts.
   - If older, do a quick refresh (Step 2 lite) and run diff mode.

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

## Step 2: Research The Target (slot-based, source-diversified)

Same engine as `research-html`. Use WebSearch, WebFetch, etc. Aim for **deep enough to write 2-3 specific, surprising lines about them** — not a Wikipedia entry.

**Build a slot plan first.** Slots needed for outreach (subset of research-html's deep dive):
- `company_basics` — what they actually do (in the founder's own words — site hero or LinkedIn About).
- `founder_basics` — previous roles, public voice (LinkedIn/Twitter/podcasts), values signals.
- `their_current_process` — how they do TODAY what YOU sell (clues: job postings, hires, tools mentioned, public complaints). This is the heart of the workflow comparison.
- `pain_signals` — reviews, job postings, founder complaints on socials.
- `recent_news` — last 90 days.

**Source diversification** — don't just Google:
- Their site (hero / about / careers).
- LinkedIn (founder + company).
- **Job listings** — best signal for "what they don't have yet."
- G2 / Capterra / Trustpilot reviews.
- Founder's X/Twitter, podcast appearances.
- Recent news (Google News + TechCrunch + Hacker News).

**Confidence rules** (same as research-html):
- `high` = 2 independent sources OR primary source.
- `medium` = 1 plausible source.
- `low` = inferred. Show confidence dots in the page.

**Write findings to memory before building the page:**

```bash
. "${HTML_SKILLS_LIB}/memory.sh"
slug="$(memory::slugify "<company>")"
memory::init_target "$slug" "<Company>"
memory::add_fact "$slug" "<claim>" "<source>" "high"
memory::add_person "$slug" "<Name>" "<Role>" "<linkedin>"
memory::mark_researched "$slug" "0.9"
```

**Then SUMMARIZE and PAUSE for confirmation:**

> *"Done digging. Here's the gist:*
> *• Acme is a 40-person Series A doing AI customer support, founded by John (ex-Stripe Support Lead).*
> *• They're hiring 3 SDRs right now — outbound is mostly manual cold email.*
> *• John posts weekly on LinkedIn about 'humanizing support' — values matter to him.*
> *• Pain point: G2 reviews mention slow response times during onboarding.*
>
> *Sound right? Anything to add before I build the page?"*

WAIT for the user's reply. Corrections go into `user_corrections[]` in the target file:

```bash
echo "{\"user_corrections\": [{\"date\": \"$(date -u +%FT%TZ)\", \"correction\": \"<text>\"}]}" \
  | memory::merge_target "$slug"
```

Bake corrections into the page before moving on.

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

10. **Sources Footer** — slim, dim, end of page. Pull from `shared/components/sources-footer.html`. Cites every URL you used + fetch date. Builds trust; founders click.

### Insight workstream — synthesize BEFORE writing the page

These are the artifacts that turn outreach from "informed" into "persuasive." Generate them once you have the research summary confirmed (after Step 2 pause). Most of these go directly into the page; the ones that don't go into your final hand-back message.

- **Hooks (3–5, ranked)** — specific opener sentences. Most-promising first, ranked by likely punch. The TOP hook becomes the Hero headline. The next 1–2 become "We Get You" card themes.
- **Trojan-Horse one-liner** — *"If I had to pitch them in 1 sentence: ___."* This becomes the page subhead AND the first line of the suggested DM. Forces synthesis.
- **Why This Matters For You (per pain)** — every pain point gets framed through `profile.json`'s `pitch_angle`. These are the labels under each "We Get You" card.
- **Probably Already Considered** — what they've likely tried. Use this to NEGATIVE-frame the Solution section: avoid pitching what they've obviously already evaluated.
- **Risk Flags** — disqualifiers. **If any risk flag is severe** (e.g., they're exclusive-vendor-locked on a competing platform, or recent scandal), STOP and tell the user before generating the page. Don't waste effort on a page that shouldn't be sent.

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

## Step 4: Deploy (via shared/lib/deploy.sh — single source of truth)

**Critical:** operational deploy logic lives in `shared/lib/deploy.sh`. Do NOT shell out `vercel` commands here yourself; call the script. The script handles Node/CLI install, browser-open login with `vercel whoami` polling (every 5s for up to 90s — fixes the "auth landed but skill stopped" bug), `vercel link` for project stickiness, robust URL capture, custom-domain aliasing, webhook pings, and writes `~/.cache/html-skills/last-error.md` on failure.

**Locate the script:**

```
$HTML_SKILLS_LIB/deploy.sh
  → ~/.claude/skills/html-skills/shared/lib/deploy.sh
  → ~/.codex/skills/html-skills/shared/lib/deploy.sh
  → ../../shared/lib/deploy.sh   (when running from a repo clone)
```

Store as `DEPLOY_SH`.

**Check state first:**

```bash
bash "$DEPLOY_SH" status
```

If `phase:` is `fresh` or `awaiting-auth` → run setup. Otherwise skip to ship.

**First-run setup (asks user nothing during execution):**

Default the project name to `{user-company}-outreach` from `shared/profile.md`. Ask user once for custom domain + webhook (or pull from Saved Config). Then:

```bash
bash "$DEPLOY_SH" setup \
  --project "<user-company>-outreach" \
  ${custom_domain:+--domain "$custom_domain"} \
  ${webhook:+--webhook "$webhook"}
```

**Critical for the bug fix:** once `setup` returns 0, IMMEDIATELY proceed to `ship`. Do NOT pause for "ready to deploy?" — the user's already approved the page in Step 3.

**Ship the page (every run):**

```bash
bash "$DEPLOY_SH" ship "<html-file>"
```

The URL appears on the LAST line of stdout. Capture it for the hand-back message.

**Failure → read `~/.cache/html-skills/last-error.md`, translate to one line, decide retry vs fallback.** Exit codes: 10 = env missing, 11 = auth timeout, 12 = deploy failed, 124 = command timeout. Fall back to local-save in `~/Downloads/` if retry doesn't help.

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

## Step 6: Record the Run + Update Memory

After a successful deploy, immediately:

```bash
. "${HTML_SKILLS_LIB}/memory.sh"
slug="$(memory::slugify "<company>")"

# Record this outreach attempt against the target.
memory::add_outreach "$slug" "$HTML_SKILLS_RUN_ID" "<live-url>" "<angle-used>" "pending"

# Log the full run (insights generated, sections shipped, edits user made).
memory::quick_run skill=outreach-html target_slug="$slug" \
  angle="<angle-used>" otp=true workflow=true \
  url="<live-url>" html_path="<absolute-path>"
```

**Why this matters:** tomorrow's run (or `mailmerge-html`'s 20-target batch) reads `past_outreach[]` to avoid repeating angles, and the run record is what `patterns.json` consolidation distills from. Without these two writes, the system can't learn.

## Step 7: Update Preferences & Profile

**`~/.cache/html-skills/memory/profile.json`** (and mirror to `shared/profile.md`) — update IMMEDIATELY when you learn company-level info (company name, pitch angle, brand voice, signature phrases). These are global, used by every skill.

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

---
name: research-html
description: Use this skill ANY time the user wants to research, dig into, look up, profile, investigate, scope out, or "do a deep dive on" a company, founder, person, product, or competitor. Triggers include phrases like "research X", "tell me about Acme Corp", "dig into this founder", "look up their company", "competitive analysis on", "background on", "scope out X for me", "who is X", "what does X do", "profile this person". Produces a rich, interactive HTML research report — not plain markdown, not a chat summary. Default to this whenever research output is expected, even if the user does not say the word "html".
---

# research-html

Generate a rich, interactive HTML research report on a company, founder, product, or competitor. Output is a single self-contained HTML file with smooth scroll, animated cards, and a dark theme by default — never plain markdown or chat summary.

---

## Step 0: Read Shared Context

Before asking the user anything:

1. Read `../../shared/profile.md`. Note their name, company, pitch angle, brand voice. These tell you WHY the user is researching and HOW deep they likely want to go.
2. Read `../../shared/design-tokens.css`. You will copy these tokens into the `<style>` block of the HTML you generate.
3. Read the `## User Preferences` section at the bottom of THIS file. If a default is already learned (e.g. "always deep dive"), skip the question about it.

Never re-ask anything that's already in profile or preferences.

## Step 1: Gather What You Need

**Always ask:**
- Who are we researching? (company name, founder name, or both)
- Why? (one short line — feeds tone & emphasis of the report)

**First use only (skip if already in preferences):**
- How deep — quick scan, standard, or deep dive?
- Anything specific to focus on? (tech stack? recent fundraise? founder background?)
- Anything to skip? (e.g. "don't bother with financials")

**Never ask:**
- Output format (always interactive HTML)
- Theme (default dark, only override if user says so)
- Whether to include sources (always include them)

**How to ask — conversational, not robotic:**

Good: *"Cool — researching Acme Corp. Quick one: do you want a fast overview or should I go deep into their tech stack, competitors, and the founder's background?"*

Bad: *"Specify research depth parameter: [quick|standard|deep]."*

Good: *"Anything you specifically want me to dig into, or just a general profile?"*

Bad: *"Provide focus areas as comma-separated list."*

## Step 2: Do The Research

Pick the tier based on user's answer (or learned default). Use WebSearch, WebFetch, and any other research tools available.

**Quick scan (~5 min of research):**
- Company overview (what they do, in one sentence the founder would actually say)
- Founder name + role
- Rough size (employees, stage)
- One interesting thing (recent news, unique angle, anything memorable)

**Standard (quick scan + the below):**
- Founder background (previous companies, education if notable, public writing)
- Products / services (real list, not marketing fluff)
- Pain points you can infer (from reviews, job postings, public complaints)
- Recent news (last 6 months)

**Deep dive (standard + the below):**
- Competitive landscape (top 3 competitors + how this company differs)
- Tech stack (from job postings, BuiltWith, GitHub, public engineering posts)
- Funding history & investors
- Culture signals (Glassdoor themes, founder's public posts on hiring/values)
- Growth trajectory (headcount over time, product launches, market expansion)
- Opportunities — where THIS user's company (per profile.md) could plug in

**Quality rules — non-negotiable:**
- Cite a source for every non-obvious claim (URL or "from their careers page", etc.)
- Never invent numbers. If you don't know headcount, say "couldn't find" — don't guess.
- Never use placeholder text like "Lorem ipsum" or "[founder background here]". If a section has no real content, DELETE the section entirely.
- Never use stock images. Use typography, color, and layout instead.
- Be specific. "John worked at Stripe 2017-2021 on the Connect team" not "John has fintech experience".

## Step 3: Build The HTML Report

Single self-contained `.html` file. Copy the design tokens from `shared/design-tokens.css` into a `<style>` block. Load fonts via the Google Fonts link in that file's footer comment.

**Page structure (top to bottom):**

1. **Header** — company name big (font-display, fs-5xl), one-line description, generated date.
2. **At a Glance** — card grid (3-4 cards): size, stage, location, one notable fact. Glassmorphism look using `bg-card` with subtle border.
3. **The Company** — what they do, products, business model. Prose with pull-quotes for sharp insights.
4. **The Founder** — only if researched. Background, public voice, what they care about.
5. **Pain Points & Opportunities** — bulleted, each backed by a source link. The most valuable section — make it visually punchy.
6. **Competitive Landscape** — deep-dive only. 3 competitor cards side-by-side with "how THIS company differs" callouts.
7. **Tech Stack** — deep-dive only. Visual chip cloud, grouped (frontend / backend / data / infra).
8. **Recent Activity** — timeline of last 6 months. Use a vertical line with dots.
9. **Key Takeaways** — 3-5 punchy bullets. The "if you only read one section" payoff.

**Design rules:**
- Dark theme default (use design tokens — don't hardcode hex).
- Smooth-scroll nav bar at top with section anchors, highlights active section on scroll.
- Cards, NEVER tables, for structured data.
- Fade-in + slide-up animations on scroll (IntersectionObserver, 400ms ease-smooth).
- Mobile responsive — collapse grid to single column under 720px, nav becomes hamburger.
- "Copy Key Takeaways" button (top-right of takeaways section) — copies plain text to clipboard with subtle confirmation.
- Floating "Back to Top" button bottom-right, appears after 600px scroll.
- All external links open in new tab with `rel="noopener"`.

**Interactive details:**
- Hover on competitor cards: lift + glow shadow.
- Click on a source citation: smooth scroll to source list at bottom.
- Pain point cards: hover reveals a "why this matters for [user's company from profile]" overlay.

## Step 4: Save and Present

- Filename: `research-{company-slug}-{YYYY-MM-DD}.html` (lowercase, hyphens).
- Save to current working directory.
- Open in browser if running locally (`open <file>` on macOS, `xdg-open` on Linux).
- Brief summary to user (3-4 lines max): what was found, what stood out, where the file is.
- Ask: *"Anything you'd like me to dig deeper on, or want me to ship this to a link?"* (the second half hints at deploy-html).

## Step 5: Update Preferences

At the END of a successful run, rewrite the `## User Preferences` section below — never append. Update ONLY when:
- The user explicitly changed a default ("nah, just quick scan from now on").
- They've made the same correction 2+ runs in a row.
- They confirmed a non-obvious choice with no pushback ("yes deep dive every time").

DO NOT update for one-off requests like "make this one shorter, just this once."

Also: if you learned something company-level about the user (their company, pitch angle, brand voice), update `shared/profile.md` too — but keep that file tight; rewrite the field, don't append.

## Common Mistakes to Avoid

1. **Placeholder text** — "[insert founder background here]" or "TBD" is always wrong. Delete the section instead.
2. **Generic descriptions** — "Acme Corp is a leading provider of innovative solutions" tells the founder you didn't research. Be specific or cut it.
3. **Tables for everything** — use cards, timelines, chip clouds. Tables read as dry.
4. **Stock images** — never. Lean on typography, color, and layout.
5. **Skipping sources** — every non-obvious claim needs a citation, even if just a URL hostname.
6. **Asking questions already answered** — always read profile.md and the preferences section first.

---

## User Preferences (Auto-Updated)

<!--
  This section is rewritten by the skill after every successful run.
  Max 20 lines. Don't append — replace.
  Only update for consistent patterns, not one-off requests.
-->

- Research depth default: [not yet learned]
- Focus areas: [not yet learned]
- Skip areas: [not yet learned]
- Source citation style: inline links (default)
- Output sections to always include: [not yet learned]
- Last updated: [never]

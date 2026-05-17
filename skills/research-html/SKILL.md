---
name: research-html
description: Use this skill ANY time the user wants to research, dig into, look up, profile, investigate, scope out, or "do a deep dive on" a company, founder, person, product, or competitor. Triggers include phrases like "research X", "tell me about Acme Corp", "dig into this founder", "look up their company", "competitive analysis on", "background on", "scope out X for me", "who is X", "what does X do", "profile this person". Produces a rich, interactive HTML research report — not plain markdown, not a chat summary. Default to this whenever research output is expected, even if the user does not say the word "html".
---

# research-html

Generate a rich, interactive HTML research report on a company, founder, product, or competitor. Output is a single self-contained HTML file with smooth scroll, animated cards, dark theme by default, **confidence indicators on every non-obvious claim, a sources footer, and insight sections that translate facts into action** — not a summary.

The skill also writes everything it learned to `~/.cache/html-skills/memory/targets/<slug>.json` so future runs (and every other skill) can read it without re-researching.

---

## Step 0: Read Shared Context

Before asking the user anything:

1. Read `../../shared/profile.md` (and `~/.cache/html-skills/memory/profile.json` if it exists — JSON wins).
2. Read `../../shared/design-tokens.css`. You'll inline these tokens in the HTML's `<style>` block.
3. Read `../../shared/SCHEMAS.md` if you have not in this session — that's the contract for what gets written to memory.
4. Read `../../shared/components/sources-footer.html`, `confidence-dot.html`, `insight-block.html` — paste these into the HTML you generate.
5. Read `## User Preferences` at the bottom of this file.
6. **Check for existing target file.** Slugify the company name (`memory::slugify` semantics — lowercase, alphanum, hyphen-separated). If `~/.cache/html-skills/memory/targets/<slug>.json` exists, **load it** and use it as your starting baseline. If `research_freshness_score` is > 0.7 and `last_researched` is < 14 days ago, ask the user *"I have recent research on Acme from 3 days ago — refresh, or use as-is?"*

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

Good: *"Cool — researching Acme Corp. Quick one: fast overview or deep dive into their tech stack, competitors, and founder background?"*
Bad: *"Specify research depth parameter: [quick|standard|deep]."*

## Step 2: Build the Research Plan (BEFORE any web searches)

Build a structured plan as JSON. This is the spine of the run — it's what makes research repeatable and what produces the "slots filled vs. not found" honesty in the final report.

Slots by tier:

**Quick scan:**
```
{ company_basics, founder_basics, one_interesting_thing }
```

**Standard:**
```
{ company_basics, founder_basics, products, pain_signals, recent_news }
```

**Deep dive:**
```
{ company_basics, founder_basics, products, pain_signals, recent_news,
  competitors, tech_stack, funding_history, culture, growth_trajectory,
  opportunities_for_user }
```

For each slot, attach 1–3 targeted queries. Don't just "Google it."

## Step 3: Run the Research — Source-Diversified

For each slot, hit the right source. Do NOT rely on a single search engine.

| Slot | Primary sources |
|---|---|
| `company_basics` | Their own website (about/team page), Crunchbase, LinkedIn company page |
| `founder_basics` | LinkedIn, founder's personal site, podcast appearances |
| `products` | Their site (pricing/features pages), changelog if public |
| `pain_signals` | **G2 / Capterra / Trustpilot reviews**, public Twitter complaints, **their own job postings** (highest signal — "what they don't have yet") |
| `recent_news` | Last 90 days only. Google News, TechCrunch, Hacker News, founder's own posts |
| `competitors` | Their site's comparison pages, G2 alternatives, "vs" search |
| `tech_stack` | BuiltWith (via search), Wappalyzer, **job descriptions**, GitHub org if engineering-led |
| `funding_history` | Crunchbase, PitchBook public profile, SEC filings if applicable |
| `culture` | Glassdoor themes (not stars — themes), founder's posts on hiring/values |
| `growth_trajectory` | LinkedIn headcount history, product launch cadence, market expansion |
| `opportunities_for_user` | Cross-reference everything above against `profile.md`'s pitch angle |

**Recency rule:** discount any source > 12 months old except foundational facts (founding year, founder previous roles).

**Confidence rule:** every claim gets `high | medium | low`:
- `high` = two independent sources agree, OR primary source (their own site / their public filing).
- `medium` = single reasonable source, plausible, not cross-verified.
- `low` = inferred / guessed / single noisy source. Show with a dim indicator. Never present without the indicator.

**Cross-verification:** if two independent sources contradict on a fact (e.g., different headcounts), keep BOTH facts in memory and render a "sources disagree" callout. Never silently pick one.

## Step 4: Write Findings to Memory FIRST (before HTML)

Slugify the company name. Then:

```bash
. "${HTML_SKILLS_LIB}/memory.sh"
memory::init_target "<slug>" "<Display Name>"

# For every confirmed fact:
memory::add_fact  "<slug>" "<claim>" "<source url or origin>" "<high|medium|low>"

# For each person you found:
memory::add_person "<slug>" "<Name>" "<Role>" "<linkedin-url-or-empty>"

# At the end:
memory::mark_researched "<slug>" "0.85"   # freshness 0..1, 1.0 = fresh deep dive
```

You can also merge structured fields (URLs, voice, public quotes) in one shot:

```bash
echo '{
  "urls": {"site": "https://acme.com", "linkedin": "..."},
  "people": [...]
}' | memory::merge_target "<slug>"
```

(`merge_target` overwrites arrays — use the helpers for facts/people/outreach.)

## Step 5: Build the HTML Report

Single self-contained `.html` file. Copy `shared/design-tokens.css` into a `<style>` block. Google Fonts link in `<head>` per the comment at the bottom of that file.

### Page structure (top to bottom)

1. **Header** — company name (font-display, fs-5xl), one-line description, generated date.
2. **At a Glance** — card grid (3-4 cards): size, stage, location, one notable fact. Glassmorphism, `bg-card` with subtle border. Each card with a low-confidence claim shows the confidence dot.
3. **The Company** — what they do, products, business model. Pull-quotes for sharp insights.
4. **The Founder** — only if researched. Background, public voice, what they care about. If you have a real public quote, use it once in a pull-quote.
5. **Pain Points** — bulleted, each linked to its source. Most valuable section — visually punchy.
6. **Competitive Landscape** *(deep dive only)* — 3 cards side-by-side with "how THIS company differs" callouts.
7. **Tech Stack** *(deep dive only)* — chip cloud, grouped (frontend / backend / data / infra).
8. **Recent Activity** — vertical timeline with dots, last 90 days only.
9. **Insight sections** — these are NEW and required. See below.
10. **Key Takeaways** — 3-5 punchy bullets. The "if you only read one section" payoff.
11. **Sources Footer** — every URL + fetch date you used. See the component.

### Insight sections (required — these are what make this a "report" not a "summary")

Use `shared/components/insight-block.html` as the structure for each:

#### 9a. Why This Matters for You
For each major pain point, frame it through your profile's `pitch_angle` from `profile.json`. If your wedge is "AI replaces SDR teams," every pain → that lens.

> Example: *"Their G2 reviews complain about slow onboarding response times — that's exactly the latency problem your AI-first approach removes in week 1."*

#### 9b. Hooks (3–5, ranked)
Specific outreach hooks, most-promising first. Each hook = a sentence the user could actually open a DM with.

> Example: *"They posted last week about hiring 3 SDRs — opener: 'saw you're hiring 3 SDRs to do what could take 1.'"*

#### 9c. Probably Already Considered
List 2-3 things the target has likely tried. For each, one line on why your offer is different. Prevents embarrassing "did you know AI exists?" pitches.

#### 9d. Risk Flags
Disqualifiers. Things that should kill the outreach.
- Exclusive vendor lock (e.g., "they're a Salesforce-only shop, your tool is HubSpot-native")
- Recent bad PR or scandal
- Misalignment with ICP (size, stage, geo)

#### 9e. Trojan-Horse One-Liner
ONE sentence: *"If I had to pitch them in one sentence, I'd say: ___."* Forces synthesis. This is the highest-value artifact for the user.

### Confidence dots

Every non-obvious claim gets a `<span class="confidence-dot confidence-{high|medium|low}">` next to it (tiny circle, color-coded). Tokens already define the colors. Tooltip on hover: "high confidence — 2 sources" / "medium — 1 source" / "low — inferred". See `shared/components/confidence-dot.html`.

### Sources footer

Every URL you fetched, with the date. Two columns: source / used for. See `shared/components/sources-footer.html`.

### Design rules

- Dark theme default. Use tokens — no hardcoded hex.
- Smooth-scroll nav bar, highlights active section.
- Cards, NEVER tables, for structured data.
- Fade-in + slide-up animations on scroll (IntersectionObserver, 400ms ease-smooth).
- Respect `prefers-reduced-motion` — drop animations, keep state changes.
- Mobile responsive — collapse to single column under 720px.
- "Copy Key Takeaways" button copies plain text to clipboard.
- Floating "Back to Top" button after 600px scroll.
- All external links: new tab, `rel="noopener"`.
- `@media print` rules so the report prints cleanly.

### Quality rules — non-negotiable

- Cite a source for every non-obvious claim (URL or "from their careers page").
- Never invent numbers. If you don't know headcount, say "couldn't find" — don't guess.
- Never use placeholder text (`[founder background here]`, Lorem ipsum). If a section has no real content, DELETE it.
- Never use stock images. Typography, color, layout only.
- Be specific. "John worked at Stripe 2017-2021 on the Connect team" not "John has fintech experience."

## Step 6: Save, Log the Run, and Present

- **Filename:** `research-<slug>-<YYYY-MM-DD>.html`. Save to current working directory.
- **Open in browser** if running locally: `open <file>` on macOS, `xdg-open` on Linux.
- **Log the run** before reporting to user. The skill is expected to have already populated `$slug`, `$depth`, `$slots_filled`, `$sources_count`, `$html_path`, and the section CSV variables earlier in the run:

```bash
. "${HTML_SKILLS_LIB}/memory.sh"

# Quick form — scalar fields.
memory::quick_run skill=research-html target_slug="$slug" \
  depth="$depth" slots_filled="$slots_filled" sources="$sources_count" \
  html_path="$html_path"

# Rich form — section survival data for consolidation.
echo "$(jq -nc \
    --arg rid "$HTML_SKILLS_RUN_ID" --arg sk research-html \
    --arg sl "$slug" --arg dp "$depth" \
    --arg draft "$draft_sections_csv" --arg ship "$shipped_sections_csv" \
    '{run_id:$rid, skill:$sk, target_slug:$sl, depth:$dp,
      draft_sections: ($draft|split(",")|map(select(length>0))),
      shipped_sections: ($ship|split(",")|map(select(length>0)))}')" \
  | memory::write_run >/dev/null
```

Also consult learned patterns before drafting heavy insight sections — `patterns::section_recommendation "<section>"` returns `always | usually | rarely | skip`. Skip sections the user has cut 4+ runs in a row.

- **Brief summary to user** (3-4 lines max):
  - What was found (1 line)
  - What stood out — your Trojan-Horse one-liner
  - File path
  - One offer: *"Want me to ship this to a link, or build an outreach page from it?"* (hints at deploy-html or outreach-html).

## Step 7: Diff Mode (if re-researching)

If a target file already existed at Step 0 and you re-researched, surface what changed since `last_researched`:

- New facts not in the old list
- Facts whose source moved up in confidence (or down)
- New people, new past_outreach entries, new news items

Render this as a small "What Changed Since [date]" callout right under the header. Helps the user catch up in 10 seconds.

## Step 8: Update Preferences (rarely)

Rewrite `## User Preferences` below ONLY when:
- User explicitly changed a default ("nah, just quick scan from now on").
- They've made the same correction 2+ runs in a row.
- They confirmed a non-obvious choice with no pushback.

DO NOT update for one-off requests like "make this one shorter, just this once."

Company-level info (their company, pitch angle, brand voice) — update `~/.cache/html-skills/memory/profile.json` AND mirror to `shared/profile.md`.

## Common Mistakes to Avoid

1. **Skipping the research plan.** The slot-based plan is what makes the report honest — "slots not found" is a feature, not a bug.
2. **Single-source claims marked `high`.** Two independent sources OR a primary source. Don't inflate confidence.
3. **Generic descriptions.** "Acme Corp is a leading provider of innovative solutions" tells the founder you didn't research. Be specific or cut it.
4. **Tables for everything.** Cards, timelines, chip clouds. Tables read as dry.
5. **Stock images.** Never. Typography, color, layout.
6. **Skipping the insight sections.** Without "Why this matters for you" + "Hooks" + "Trojan-horse one-liner," this is just a summary. The insight sections are the product.
7. **Not writing to `targets/<slug>.json`.** Every other skill depends on this. If you skip it, tomorrow's outreach-html is research-blind.
8. **Placeholder text.** If you can't fill it, cut it.

---

## User Preferences (Auto-Updated)

<!--
  Rewritten by the skill after every successful run. Max 20 lines. Don't append.
  Only update for consistent patterns, not one-off requests.
-->

- Research depth default: [not yet learned]
- Focus areas: [not yet learned]
- Skip areas: [not yet learned]
- Source citation style: inline links + sources footer (default)
- Output sections to always include: header, at-a-glance, company, pain, hooks, trojan-horse, sources-footer (default)
- Confidence dots: always shown (default)
- Last updated: [never]

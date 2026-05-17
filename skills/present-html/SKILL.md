---
name: present-html
description: Use this skill ANY time the user wants to turn content into a presentation, deck, slides, pitch, walk-through, landing page, or scroll-driven story. Triggers include "make a presentation", "build a deck", "turn this into slides", "make a pitch page", "create a landing for X", "present this", "make this look good", "build a page for", "show this off". Produces a scroll-driven, animated, single-file HTML presentation — NOT PowerPoint, NOT markdown, NOT Google Slides. Use whenever a visual, shareable, founder-facing artifact is wanted. Default to this when in doubt.
---

# present-html

Turn any content into a scroll-driven, animated, single-file HTML presentation. Full-viewport sections, smooth scroll-snap, IntersectionObserver-driven reveals, optional OTP gate, and optional embedded animated workflow comparison.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` — for brand voice, design style, signature phrases.
2. Read `../../shared/design-tokens.css` — copy into the page's `<style>` block.
3. Read `## User Preferences` at the bottom of this file. Skip questions whose defaults are learned.

## Step 1: Gather What You Need

**Always ask:**
- What content are we presenting? (paste / file path / a topic to expand on)
- Who's the audience? (a specific founder, internal team, conference, investors)

**First use only:**
- Vibe — minimal & editorial / bold & punchy / playful & illustrative?
- Include an animated workflow comparison? (a side-by-side process race — most impactful for outreach pitches)
- Should it be OTP-gated? (a code unlocks the real content — feels exclusive)
- Accent color preference (one pop color over the default indigo)

**Never ask:**
- Format (always single-file HTML)
- Theme (dark default, only override on explicit request)
- File hosting (that's deploy-html's job — only mention if user asks)

**How to ask:**

Good: *"Got it — building a deck for John at Acme. Want me to drop in that animated comparison of their current process vs yours? It's the section founders actually stop scrolling for."*

Bad: *"Configure workflow_visualization_component: [true|false]."*

Good: *"Want a code to unlock the page? Makes it feel personal — like a key just for them."*

Bad: *"Enable OTP gating mechanism (4-6 digit numeric token)?"*

## Step 2: Plan The Story

Before writing HTML, draft the section list. A good presentation has 5-9 sections, each one full-viewport. Typical flow:

1. **(Optional) OTP gate** — company name + teaser + code input
2. **Hero** — one line that hits, founder's name if personal, scroll cue
3. **The Hook** — the specific problem THIS audience has
4. **Context / Proof** — why you, why now
5. **(Optional) Workflow comparison** — the animated race
6. **The Offer / Solution** — concrete, not vague
7. **How it works** — 3-4 steps
8. **Social proof / metrics** — at their scale, not ours
9. **CTA** — one button, one ask

Cut sections aggressively. A founder will scroll 30 seconds before deciding — every section must earn its viewport.

## Step 3: Build The HTML Presentation

Single self-contained `.html` file. Tokens copied from `shared/design-tokens.css`. Fonts via Google Fonts.

**Quality rules — non-negotiable:**
- Dark theme default. Use design tokens — never hardcode hex.
- Never use placeholder text ("Lorem ipsum", "[insert hook here]"). If a section has no real content, cut it.
- Never use stock images. Lean on typography, color, gradients, and layout.
- Mobile responsive — full-viewport sections preserved on phones.

**Layout & motion:**
- Each section is `min-height: 100vh`, padded `--space-2xl`, content centered with `max-width: var(--container-md)`.
- Soft scroll-snap (`scroll-snap-type: y proximity`) — guides without forcing.
- IntersectionObserver triggers fade-in + 20px slide-up on section entry. One-shot, not on every scroll.
- One pop accent color used sparingly — a single button, one underline, one icon. Everything else is on the dark canvas.
- Mobile-first: type scales down, sections still full-viewport, all animations preserved.

**Typography:**
- Hero headline: `font-display`, `fs-5xl`, `fw-bold`, letter-spacing -0.02em.
- Section headers: `fs-3xl`, `fw-semibold`.
- Body: `fs-lg`, `lh-relaxed`.

**Required interactions:**
- Scroll progress indicator at the top (thin bar, `accent-primary`).
- Floating section dots on the right side (desktop only) — click to jump.
- All CTAs use one consistent button style (filled `accent-primary`, `radius-full`, subtle glow on hover).

### OTP gate (if enabled)

First view shows ONLY:
- Company name + founder name big
- A one-line teaser ("A 90-second look at where Acme could be in 6 weeks")
- 4-6 numeric inputs for the code
- Subtle "your code is in the DM" line

Code lives in a JS variable at the top of the file — clearly marked as "personalization, not security". Correct entry: smooth fade + content reveal. Wrong: gentle horizontal shake (CSS keyframe `translateX` 0 → 8px → -8px → 0), inputs flash `accent-danger` border, then reset. After 3 wrong attempts, show a friendly "double-check the code in the message?".

### Workflow comparison component (if enabled)

This is the highest-impact section in any outreach pitch. Two pipelines animate side-by-side, racing. The new (fast) one finishes while the old one is still mid-process — a win banner slides in. Founders stop and watch.

**Visual structure:**
- Two vertical SVG node graphs, side-by-side (stacked on mobile).
- Each node = circle (radius 36px), icon centered, step number badge top-right, duration badge bottom.
- Nodes connected by SVG path (straight line desktop, slight bezier curve for organic feel).
- Section title: "Their current flow vs With [Your Company]" — pull real names from profile.md and the content.

**Animation engine (requestAnimationFrame loop):**
- Particles travel along the SVG paths between nodes.
- Old pipeline: particles slow (4-6s per edge), heavier (radius 4px), color `text-muted`.
- New pipeline: particles fast (0.4-0.8s per edge), zippy (radius 3px, with trail), color `accent-secondary`.
- Active node (currently being processed): dashed `accent-primary` ring spinning around it (CSS `@keyframes rotate`), pulsing halo (box-shadow breathing 0.4 → 1.0 opacity, 1.5s loop).
- Completion burst: 8-12 particles explode outward from node, fade over 600ms, before handoff to next node.

**Bottleneck markers:**
- Any node with duration > 1 day in the old pipeline gets a ⚠️ badge in `accent-warning` and a slow-pulsing red halo.

**Controls:**
- Big "▶ Run Comparison" button below the graphs. Disabled while running.
- "↺ Replay" button appears after first run.
- Both pipelines start on the same click — that's the whole point of the race.

**Live clocks:**
- Each pipeline has a clock above it ticking up in real time (scaled — e.g. 1 real-second = 1 real day for old, 1 real-second = 1 minute for new). Format the unit honestly: "Day 4 of 12" or "Minute 3 of 8".

**Win banner:**
- When the fast pipeline finishes while the slow one is still running, a banner slides down from the top of the section: *"✓ With us, [Founder] is already done. Their team is still on step [N]."*. Stays until slow finishes.

**Final metrics panel:**
- Appears when BOTH finish. 3 stat cards in a row:
  - Time saved (e.g. "11 days → 8 minutes")
  - Steps eliminated (e.g. "7 → 3")
  - Bottlenecks removed (e.g. "2 → 0")
- Stats count up from 0 over 1.2s on appear (use `requestAnimationFrame`).

**Accessibility:**
- Respect `prefers-reduced-motion`: drop the particles & spin, keep just state changes (active node color shift).
- Each node has a `<title>` SVG element for screen readers.

## Step 4: Save and Present

- Filename: `present-{topic-or-recipient-slug}-{YYYY-MM-DD}.html`.
- Save to working directory.
- Open in browser locally.
- 2-line summary: how many sections, key features (OTP / workflow / etc.), the OTP code if generated.
- Ask: *"Want this live on a link, or just running locally for now?"* (signals deploy-html).

## Step 5: Update Preferences

Rewrite the preferences section ONLY when:
- User changed a default explicitly ("always include the workflow, don't ask").
- Same correction made 2+ times.
- User confirmed an unusual choice that worked.

If a brand-voice or company-level fact came up (e.g. "we always close with a Calendly link"), update `shared/profile.md` instead — that's the right home for company-wide info.

## Step N: Record the run

Before the final hand-back to the user, log a run record so the system can include this presentation in `dashboard-html` KPIs and learn from how you composed it:

```bash
. "${HTML_SKILLS_LIB}/memory.sh"
memory::quick_run skill=present-html \
  audience="$audience" sections="$section_count" otp="$otp_enabled" \
  workflow="$workflow_enabled" html_path="$html_path"
```

If the page is for a specific target (e.g. a pitch deck for a known company), also link it to that target's `past_outreach[]`:

```bash
slug="$(memory::slugify "$company")"
memory::add_outreach "$slug" "$HTML_SKILLS_RUN_ID" "$url" "$angle" "pending"
```

## Common Mistakes to Avoid

1. **Too many sections** — 5-9 max. Cutting is the work.
2. **Generic hero headlines** — "Welcome" or "Hi [Name]" wastes the most expensive viewport. The headline should reference a specific thing about THEM.
3. **Particles without nodes** — the workflow component without proper SVG nodes & icons feels cheap. Build the graph properly or skip the section.
4. **Hardcoding colors** — always reference `var(--accent-primary)` etc., never `#7c5cff` inline. The user might swap themes.
5. **Forgetting reduced-motion** — your animations will give someone motion sickness if you skip this.
6. **OTP code in plain text in the page** — that's fine (it's personalization, not security), but never call it "secure" in user-facing text.

---

## User Preferences (Auto-Updated)

<!--
  Rewritten after every successful run. Max 20 lines. Replace, don't append.
-->

- Vibe default: [not yet learned]
- Workflow comparison: ask each time (default until learned)
- OTP gating: ask each time (default until learned)
- Accent color: indigo (--accent-primary, default)
- Mobile-first emphasis: yes (default)
- Sections to always include: hero, CTA (defaults)
- Last updated: [never]

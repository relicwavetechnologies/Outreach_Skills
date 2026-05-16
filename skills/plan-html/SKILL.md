---
name: plan-html
description: Use this skill ANY time the user wants to plan, design, map, scope, lay out, propose, or think through a process, system, project, architecture, roadmap, or decision. Triggers include "plan X", "design a system for Y", "map out the workflow", "what's the roadmap", "help me decide between X and Y", "scope this out", "draft a plan", "compare these options", "improve our [process]", "should we build or buy", "let's think through". Produces an interactive HTML planning document — with embedded animated workflow comparisons, decision matrices, process flows, or timelines depending on plan type. Print-friendly. Defaults to this for any non-trivial planning ask.
---

# plan-html

Generate an interactive HTML planning document with the right visual component for the plan type. Four plan types — process/workflow, system/architecture, project/roadmap, comparison/decision. Each gets its own visual: workflow race, flow diagram, decision matrix, or timeline. Always makes a recommendation, always names risks, always print-friendly.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` — for user role, company context, audience.
2. Read `../../shared/design-tokens.css` — copy into the HTML's `<style>` block.
3. Read `## User Preferences` at the bottom of this file. Note: this skill asks more questions every run than other skills — planning is high-context. Don't over-skip even if some defaults are learned.

## Step 1: Gather What You Need

**Always ask:**
- What are we planning? (one or two sentences)
- Who's this for? (you alone, a team, a stakeholder, a client)
- Which type of plan does this feel like?
  1. **Process / workflow** — improving how a thing gets done
  2. **System / architecture** — designing what to build
  3. **Project / roadmap** — sequencing phases & milestones
  4. **Comparison / decision** — choosing between options

**Usually ask (every run, unless answered):**
- What's already decided vs what's still open?
- Constraints? (budget, team size, deadline, must-haves, hard nos)
- Include an animated workflow comparison? (default yes for process/workflow plans, optional otherwise)

**Type-specific follow-ups:**

- **Process:** What's the current process, step by step? Where does it hurt?
- **System:** Build vs buy bias? Existing stack to integrate with? Scale assumptions?
- **Project:** Hard deadlines? Dependencies on other teams?
- **Decision:** What are the options? What criteria matter? Weights?

**How to ask:**

Good: *"Let's plan this. Quick — is this more about fixing how something gets done today, designing something new, sequencing a project, or picking between options? (those map to different shapes of plan, I'll build the right one)"*

Bad: *"Specify plan_type from enum [process, system, project, decision]."*

Good: *"What's already settled, and what's still up for grabs? Helps me know where to be opinionated vs neutral."*

Bad: *"Provide decided_items and undecided_items as separate lists."*

## Step 2: Do The Thinking

Don't generate the HTML yet. First, work the plan out in your head (use TodoWrite if it helps).

**For all plan types:**
- Identify the 3-5 most important insights/decisions
- Make a clear recommendation (not "it depends" — pick one and defend it)
- List honest risks & open questions (2-5 items)

**Type-specific work:**

- **Process plan:** map current process node-by-node with realistic durations. Identify bottlenecks (>1 day or repeated steps). Design improved process. Calculate time/cost saved.
- **System plan:** list components, draw data flow, mark each "build" or "buy" with a one-line justification. Estimate complexity (S/M/L) per component.
- **Project plan:** break into 3-5 phases. Each phase: 1-line goal, 2-4 milestones, rough timeline, primary blocker.
- **Decision plan:** list 2-4 options. List 4-7 criteria. Score each option per criterion (1-5 or pass/fail). Apply weights. Show the math.

## Step 3: Build The HTML

Single self-contained `.html` file. Tokens copied. Print stylesheet included.

**Universal page structure:**

1. **Header** — plan title, type, date, author (from profile.md).
2. **TL;DR** — top of fold. The recommendation in 1-2 sentences + the 3 most important supporting points. Founder/exec should be able to read ONLY this and know the call.
3. **Context** — what we're planning, what's already decided, what's open, constraints.
4. **The Visual Component** — one of four, see below. THE big interactive section.
5. **Detailed walkthrough** — prose + sub-sections for each step / component / phase / option.
6. **Risks & Open Questions** — honest list. Each risk has a "mitigation" or "we'd need to learn X to know".
7. **Next Steps** — 3-5 concrete actions, with owners if known.
8. **Appendix** — sources, raw data, alternate options considered (collapsed by default).

### Visual components

**A. Workflow comparison** (process plans)

Same spec as `present-html` workflow comparison — two SVG node graphs side-by-side, requestAnimationFrame particles, spinning rings on active nodes, pulsing halos, burst on complete, win banner, final metrics panel. See `present-html/SKILL.md` Step 3 for full visual spec — replicate it identically here so all html-skills share one workflow-component look.

**B. Process flow diagram** (system / project plans)

Horizontal or vertical node chain — pick horizontal for ≤6 nodes, vertical otherwise.
- Each node: rounded rect (`radius-md`), label, status pill (top-right: `Done` / `In progress` / `Blocked` / `Planned` color-coded with `accent-success` / `accent-secondary` / `accent-danger` / `text-muted`).
- Edges: curved SVG paths with arrowheads. Color matches downstream node's status.
- Click a node: side panel slides in from right with full details (description, owner, dependencies, estimated effort).
- Mini-map in the corner for diagrams with >10 nodes.

**C. Decision matrix** (decision plans)

Interactive grid: options as columns, criteria as rows.
- Each cell: numeric score colored by intensity (HSL lightness mapped to score 1-5 against `accent-primary`).
- Hover cell: tooltip with the reasoning.
- Weighted total row at bottom — bold, with delta vs second-best highlighted.
- Recommended option's column: subtle `accent-primary` border + "✓ Recommended" badge.
- Sort criteria by weight (heaviest first).
- "Swap weights" sliders at the top — recompute totals live on drag.

**D. Timeline / roadmap** (project plans)

Horizontal timeline (vertical on mobile).
- Phases as bars with start/end dates, color-coded.
- Milestones as diamond markers on each bar, hoverable for details.
- Dependencies between phases shown as dashed connectors.
- A vertical "you are here" line at today's date (using JS `new Date()`).
- Click a milestone: expandable detail card.
- Toggle: "Weeks / Months / Quarters" granularity.

### Design rules

- Dark theme default, light theme works via `data-theme="light"`. Use design tokens — never hardcode hex.
- Mobile responsive — visual components reflow (workflow stacks vertical, matrix becomes scrollable, timeline scrolls horizontally with stickied row labels).
- Never use placeholder text — if a section has no content, cut it. Never use stock images.
- Print stylesheet (`@media print`):
  - Force light theme.
  - Hide all controls (buttons, sliders).
  - Workflow animations replaced with two static side-by-side diagrams + a metrics panel.
  - Page breaks before each major section.
  - Hide the appendix collapse — show all content.
- Smooth-scroll nav with section pills at the top.
- Floating "Jump to TL;DR" button bottom-right.
- All claims sourced (link or "from {user}'s input").

## Step 4: Save and Present

- Filename: `plan-{topic-slug}-{YYYY-MM-DD}.html`.
- Save to working directory. Open in browser.
- Brief summary: plan type, key recommendation, 1-line risk summary, file path.
- Ask: *"Want me to push back on anything, or expand a section?"* (not just "looks good?" — invite challenge).

## Step 5: Update Preferences

Rewrite preferences ONLY when:
- User has the same plan type 2+ runs and a default emerges ("always include workflow viz", "always print-friendly").
- User explicitly changes a default.

Planning is context-heavy, so most updates here are about FORMAT (visual component default, sections to always include, depth of risk analysis) — not about content.

## Common Mistakes to Avoid

1. **Wishy-washy recommendations** — "it depends on your priorities" is not a plan. Pick one. Defend it. The user can argue back.
2. **No risks section** — every plan has risks. Listing them builds trust. Hiding them is dishonest.
3. **Wrong visual for plan type** — a decision plan with a workflow race is confusing. Match the visual to the shape of the question.
4. **Forgetting print stylesheet** — plans get shared, often printed. Test print preview.
5. **Skipping TL;DR** — exec readers stop after the first screen. The recommendation MUST be in the first viewport.
6. **Hardcoding colors in scores** — use HSL with `--accent-primary` hue so theme switching works.

---

## User Preferences (Auto-Updated)

<!--
  Rewritten after every successful run. Max 20 lines.
  Planning is context-heavy — keep defaults narrow.
-->

- Default plan type bias: [not yet learned]
- Visual component default for process plans: workflow comparison
- Always include TL;DR: yes
- Always include risks section: yes
- Print stylesheet: always include
- Sections to always include: TL;DR, Risks, Next Steps
- Last updated: [never]

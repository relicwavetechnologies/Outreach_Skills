---
name: review-html
description: Use this skill ANY time the user wants to review, audit, critique, examine, or "take a look at" code, a pull request, a diff, a branch, or recent changes. Triggers include "review this PR", "code review", "look over my changes", "audit this branch", "check this diff", "what's wrong with this", "review the latest commit", "PR review for #123", "is this code okay". Produces a visual HTML code review report — severity-coded findings, annotated diffs, architecture impact diagram, filterable findings. Default to this whenever the user asks for code feedback in a form richer than a chat reply.
---

# review-html

Turn code changes (a PR, a diff, a branch, a single file) into a visual HTML review report. Severity-coded findings, annotated diffs with inline comments, filterable, with an architecture-impact diagram.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` — for tech audience level (technical / business / mixed).
2. Read `../../shared/design-tokens.css` — copy into the page's `<style>` block.
3. Read `../../shared/components/confidence-dot.html` — use the `.cdot` inline indicators to tag severity on every finding (`cdot-danger` for critical, `cdot-warning` for medium, `cdot-muted` for low/nit). Paste the CSS once into your `<style>`.
4. Read `## User Preferences` at the bottom. If severity threshold and audience tech-level are learned, skip those questions.

## Step 1: Gather What You Need

**Always ask:**
- What code are we reviewing? (PR URL, branch name, file paths, or "all my uncommitted changes")
- What should I focus on? (bugs, performance, security, style, all of it)

**First use only:**
- Severity threshold to surface — show only Critical & Warning, or include Suggestions and Positives too?
- How technical is the audience for this report? (engineer / mixed / non-technical exec — changes how findings are explained)

**Never ask:**
- Output format (always HTML report)
- Whether to show diffs (always, with inline annotations)

**How to ask:**

Good: *"Got it — reviewing the auth refactor PR. Want me to flag everything (suggestions + good catches included) or just the stuff you'd actually want to fix?"*

Bad: *"Configure severity_threshold ∈ {Critical, Warning, Suggestion, Positive}."*

Good: *"Who's reading this? Just you, or are you sending it to someone less in the weeds?"*

Bad: *"Specify audience.technical_proficiency_level."*

## Step 2: Do The Review

Use Read, Grep, Bash (`git diff`, `git log`, `gh pr view`) to load the changes. Then actually review — don't skim.

**Severity levels:**

| Level | Color | Use for |
|---|---|---|
| **Critical** | `accent-danger` (red) | Bugs that WILL break in production. Security vulns. Data loss risks. |
| **Warning** | `accent-warning` (amber) | Performance issues. Code smells likely to bite later. Missing error handling. |
| **Suggestion** | `accent-secondary` (cyan) | Style improvements. Refactor opportunities. Better patterns available. |
| **Positive** | `accent-success` (green) | Good calls worth calling out — clever solutions, careful edge cases, removed dead code. |

**Review depth — for each changed file:**
- Read the full file, not just the diff. Context matters.
- For each finding: severity, file:line, 2-3 line explanation, suggested fix (code snippet if useful).
- Cross-file impacts: if a function signature changed, who calls it? Are all call sites updated?
- Security check: any new user input → SQL/shell/HTML? Any new secrets/keys/tokens accidentally committed?

**Calculate risk score (0-100):**
- 30 points: Critical count × 10 (capped)
- 20 points: Warning count × 4 (capped)
- 10 points: complexity delta (added LOC × file count factor)
- 20 points: test coverage delta (missing tests = points)
- 20 points: blast radius (how many files/modules touched)

**Always include Positives** even if the user asked for just bugs — calling out good work makes the report read as fair, not adversarial.

## Step 3: Build The HTML Report

Single self-contained `.html` file. Tokens copied. Mono font for code blocks.

**Page structure:**

1. **Header** — PR title or branch name, author, date, big risk score (0-100) with visual indicator.
2. **Risk indicator** — circular gauge or horizontal bar, colored by zone (0-30 green, 31-60 amber, 61-100 red).
3. **Summary** — 2-3 sentences: what changed, key concerns, recommended action (merge / iterate / block).
4. **Findings — Filterable Cards**:
   - Severity filter chips at top: `All | Critical (3) | Warning (5) | Suggestion (8) | Positive (2)`. Click to filter.
   - Each finding card: severity badge, file:line link, explanation, suggested fix (collapsible code block).
   - Click file:line: smooth-scroll to that file's diff below.
5. **Annotated Diffs** — for each changed file:
   - Standard +/- diff rendering, monospace, with `accent-success`/`accent-danger` left-border on added/removed lines.
   - Inline comment bubbles on lines that have findings (color-coded by severity).
   - "Expand context" button to show 10 more lines around each hunk.
6. **Architecture Impact Diagram** — visual graph of modules touched:
   - Each module = node. Edge if module A imports module B.
   - Touched modules highlighted with `accent-primary` glow.
   - Indirectly affected (transitively imported from touched) shown with dashed border.
   - Hover module: shows findings count for that module.
   - Skip this section if changes touch ≤2 files (overkill).
7. **Recommendations** — 3-5 concrete next steps. Prioritized. "Copy Recommendations" button copies plain text to clipboard.

**Design rules:**
- Dark theme default. Use design tokens — never hardcode hex. Code blocks use a darker `bg-secondary` background, light syntax-highlight colors.
- Never use placeholder text — every finding has real explanation + real suggested fix. No "TBD" or "[describe issue]". Never use stock images.
- Filter chips: pill-shaped, click toggles active state with `accent-primary` fill.
- Findings cards: subtle severity-color left-border (4px), full card on hover.
- Mobile-responsive: diffs scroll horizontally, architecture diagram collapses to a list view <720px.
- Smooth scroll nav at top: Summary | Findings | Diffs | Architecture | Recommendations.
- Sticky filter bar (sticks to top when scrolling Findings section).

**Audience-aware language:**
- Engineer audience: be terse, use jargon, link to docs, suggest specific fixes.
- Mixed audience: explain the "why this matters" for each finding in one accessible line.
- Non-technical audience: lead each finding with business impact ("could cause checkout to fail for ~X% of users"), keep code snippets but minimize jargon.

## Step 4: Save and Present

- Filename: `review-{pr-number-or-branch}-{YYYY-MM-DD}.html`.
- Save to working directory. Open in browser.
- 2-line summary: risk score, count of critical findings, file path.
- Ask: *"Want me to dig deeper on any specific finding, or is this good to send over?"*

## Step 5: Update Preferences

Rewrite preferences ONLY when:
- Severity threshold has stabilized (user always wants Suggestions included, or always filters them out).
- Audience tech-level is consistent across runs.
- User has corrected the same thing twice ("don't include positives" → save that default).

## Step 6: Record the run

Log a run record so dashboard-html can show review activity in the KPI cards:

```bash
. "${HTML_SKILLS_LIB}/memory.sh"
memory::quick_run skill=review-html \
  findings_critical="$crit" findings_medium="$med" findings_low="$low" \
  audience="$audience" html_path="$html_path"
```

## Common Mistakes to Avoid

1. **Skimming the diff** — read the full files. A diff hides context. The Critical finding is often in code that wasn't changed.
2. **Only listing bad things** — Positives make the review trustworthy. Always include 1-3 even on rough PRs.
3. **Wrong severity** — a style nit is not Critical. Calibrate. Misuse of severity makes the whole report ignorable.
4. **Vague fixes** — "consider refactoring" is useless. Show the actual replacement code in the suggested fix.
5. **Skipping the architecture diagram on a big PR** — when 10+ files change, the diagram is what makes the review skimmable.
6. **Forgetting cross-file impacts** — if a public function changed, you have to check the call sites. The report should note "verified all N callers handle this" or "call site at X not updated".

---

## User Preferences (Auto-Updated)

<!--
  Rewritten after every successful run. Max 20 lines.
-->

- Severity threshold: include all (default until learned)
- Audience tech level: engineer (default until learned)
- Always include Positives: yes (default)
- Architecture diagram threshold: 3+ files changed (default)
- Code snippets in suggested fixes: yes (default)
- Last updated: [never]

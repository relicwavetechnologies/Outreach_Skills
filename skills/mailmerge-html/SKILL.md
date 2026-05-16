---
name: mailmerge-html
description: Use this skill ANY time the user wants to do BATCH personalized outreach — multiple targets at once, from a CSV or a pasted list. Triggers include "mailmerge to these 20 founders", "outreach to this CSV", "batch this list", "send personalized pages to all of these", "run outreach on a spreadsheet", "do these all at once". The pipeline: parse the CSV → research each target → cluster by ICP attributes → pick the best-fit angle per cluster from past patterns → generate a personalized HTML page per target → deploy each → produce a single dashboard HTML with all URLs, suggested DMs, and per-target reasoning. SELF-CONTAINED — works without research-html, outreach-html, deploy-html installed (calls the same shared/lib helpers). Has built-in cost guardrails, dry-run preview mode, and pause-and-inspect checkpoints.
---

# mailmerge-html

The volume leverage move. Feed a CSV (or pasted list). Get N personalized pages + N suggested DMs + a single dashboard that summarizes the batch. Each page is one-of-one — researched and angle-tuned per target — not a templated copy.

**This is NOT a dumb loop.** Mailmerge uses cross-skill memory (`targets/<slug>.json`) and pattern data (`patterns.json`) to:
- Cluster targets by ICP attributes (stage, size, industry, role).
- Pick the best-fit angle per cluster from past reply data.
- Skip research on targets already known (freshness > 0.7, < 14 days).
- Refuse to re-use an angle already shipped to the same person.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` and `~/.cache/html-skills/memory/profile.json` — your company, pitch angle, brand voice are load-bearing.
2. Read `../../shared/SCHEMAS.md` for the memory contract (esp. `targets/<slug>.json` and `runs/<run_id>.json`).
3. Read `../../shared/design-tokens.css`, `../../shared/components/{confidence-dot,sources-footer,insight-block,mailmerge-dashboard}.html`.
4. Read `~/.cache/html-skills/memory/patterns.json` if it exists. Patterns drive cluster→angle decisions. If empty, fall back to profile's `pitch_angle` as a default.
5. Read `## User Preferences` AND `## Saved Config` at the bottom of this file.
6. Locate shared libs (same lookup as deploy-html):
   ```
   $HTML_SKILLS_LIB / ~/.claude/skills/html-skills/shared/lib / ~/.codex/.../shared/lib / ../../shared/lib
   ```
   Source `log.sh`, `memory.sh`, `csv.sh`, `outcomes.sh`, `track.sh`, and prepare to call `deploy.sh`.

7. **One-tap pending-reply prompt.** ONCE per session, scan for outreaches > 24h old still marked `pending`:
   ```bash
   . "${HTML_SKILLS_LIB}/outcomes.sh"
   outcomes::pending_replies 24
   ```
   For each: brief ask, then `outcomes::set_outreach_outcome <slug> <run_id> <outcome>` where outcome ∈ `pending|replied|no_reply|meeting_booked|cold`. This is the highest-signal feedback the system gets — two taps and the consolidation pass has gold-standard data for `patterns.json`. Skip if there are none pending.

## Step 1: Gather the Inputs

Plain-language, one at a time.

**Question 1 — source:**
> *"How are you giving me the list — a CSV file, or do you want to paste it in?"*

If CSV: ask for path. Validate with `csv::validate <path>`. On failure, translate the error (e.g., "row 14 has more cells than the header — wanna fix the CSV first, or want me to skip that row?").

If pasted: write to `~/.cache/html-skills/mailmerge-<timestamp>.csv` after light cleanup (strip leading/trailing whitespace, normalize line endings).

**Question 2 — column mapping (only if not auto-detectable):**

Use `csv::detect_field <file> linkedin url profile`. If a LinkedIn-ish column is found, confirm: *"I'll use 'LinkedIn URL' for each target — sound right?"*

Required logical fields and the substrings to auto-detect:

| Logical field | Detection substrings | Required? |
|---|---|---|
| `name`        | `name`, `full name`, `contact` | yes |
| `company`     | `company`, `org`, `account`    | yes |
| `linkedin`    | `linkedin`, `profile`, `url`   | strongly preferred |
| `email`       | `email`, `e-mail`              | optional |
| `role`        | `title`, `role`, `position`    | optional |
| `notes`       | `notes`, `comment`, `context`  | optional |

If `name` or `company` can't be auto-detected, ask the user to point at the right column.

**Question 3 — batch size + budget:**

> *"How many do you actually want to ship — all 47, or a subset to start? And what's the budget ceiling — I'll cap research depth + parallelism to fit."*

Hard defaults the user can override:
- ≤ 5 targets: deep dive each, sequential.
- 6–20 targets: standard depth, up to 3 parallel.
- 21–50 targets: standard depth, up to 5 parallel, ICP clustering kicks in.
- 50+: refuse without explicit confirmation; suggest splitting.

**Question 4 — dry run first?**

> *"Want me to do a 3-target preview first so you can sanity-check tone, or just commit to the full batch?"*

DEFAULT to dry-run if this is the user's first mailmerge OR the batch is > 10. Recommend skipping dry-run only for repeat users with stable patterns.

**Every run (quick check-in):**
- *"Same vibe as your last batch, or anything different?"*

Save Q1–Q4 answers to `## Saved Config` immediately.

## Step 2: Plan the Batch

Build a `batch.json` in `~/.cache/html-skills/mailmerge/<batch-id>/` with the planned actions. This is what the user reviews and approves.

```json
{
  "batch_id": "20260517-153201",
  "source_csv": "...",
  "total_targets": 17,
  "dry_run": true,
  "dry_run_size": 3,
  "parallelism": 3,
  "clusters": {
    "series-a-ai":      { "count": 9, "angle": "scale-outbound-not-headcount" },
    "enterprise-saas":  { "count": 5, "angle": "compliance-risk-removal" },
    "unclustered":      { "count": 3, "angle": "<profile.pitch_angle as fallback>" }
  },
  "targets": [
    { "row": 1, "name": "John Smith", "company": "Acme Corp", "linkedin": "...",
      "slug": "acme-corp", "cluster": "series-a-ai", "angle": "scale-outbound-not-headcount",
      "memory_freshness": 0.0, "needs_research": true,
      "past_outreach_to_this_person": [], "skip_reason": null }
  ]
}
```

### ICP clustering

For each row:
1. Slugify the company → check `~/.cache/html-skills/memory/targets/<slug>.json`.
2. If it exists, pull stage/size/industry from `.facts[]`. Otherwise do a quick LinkedIn/site lookup (1–2 queries max) to classify.
3. Bucket into clusters using simple rules:
   - `series-a-ai`         → "Series A" + AI/ML in description
   - `enterprise-saas`     → 200+ employees + B2B SaaS
   - `early-stage`         → < 30 employees + pre-Series-A
   - `unclustered`         → fallback
   (Expand bucket logic over time as `patterns.json` grows.)

### Angle selection per cluster

Read `patterns.json`. If a rule with high `evidence_runs` matches a cluster, use that angle. Example pattern:
```
"hooks-with-quotes-win" → evidence_runs:8 → use quote-led hooks for trust-building clusters
```

If no relevant pattern OR `patterns.json` is empty, fall back to `profile.json.company.pitch_angle`.

### Pre-skip checks per target

Skip a target (and explain in dashboard) when:
- A `past_outreach[]` entry exists with `outcome=="pending"` and < 7 days old (don't double-DM).
- The cluster's planned angle is already in `do_not_use_angles[]` for that target.
- A severe risk flag exists in the target's facts (mark as `needs_review`).

## Step 3: Show the Plan, PAUSE for Approval

Render the plan to the user as a brief summary table. **Wait for approval before any research or deploy.**

```
17 targets, 3 clusters:
  • series-a-ai (9):       angle → "scale-outbound-not-headcount"
  • enterprise-saas (5):   angle → "compliance-risk-removal"
  • unclustered (3):       angle → "<your default>"

  2 will be SKIPPED:
    – sarah@beam: outreach 3 days ago, no reply yet
    – peter@globex: severe risk flag (Salesforce-only)

  Dry run: yes → I'll do the first 3 only, you preview, we commit to the rest.

Ship it? (yes / change angles / skip cluster X / cancel)
```

Accept simple edit commands: "use the values-led angle for enterprise-saas", "skip the unclustered ones this round". Re-render the plan after each edit.

## Step 4: Execute (dry-run first if enabled)

For each target NOT marked skipped:

1. **Research** — call the slot-based research engine from `research-html`'s spec (inline; do not require research-html to be installed). Source diversification, confidence scoring, sources captured. Write facts to `targets/<slug>.json` via `memory::add_fact` etc.
2. **Build insight sections** — Hooks, Trojan-Horse, Why-this-matters, Risk-flags. Top hook = page hero headline. Trojan-horse = subhead + first line of DM.
3. **Generate the HTML page** — same structure as `outreach-html` (OTP gate, hero, we-get-you, problem, workflow comparison if enabled, solution, results, CTA, sources footer).
4. **Inject tracker (if enabled)** — `track::inject "<html-file>" "<per-target run_id>"`. No-op if `track::is_enabled` is false. Each target gets its own run_id so events route correctly.
5. **Deploy** — `bash "$DEPLOY_SH" ship "<file>" --project "<user-company>-mailmerge"`. Auth re-verify is handled by deploy.sh. Capture URL from last line of stdout.
6. **Record** — `memory::add_outreach <slug> <run_id> <url> <angle> "pending"` and `memory::quick_run skill=mailmerge-html ...`.

### Parallelism

Run up to `parallelism` targets concurrently. Use bash `&` + `wait`, or `xargs -P`. Per-target failures don't kill the batch — capture and continue. Track results in `batch.json` (status: `pending → researching → building → shipping → shipped|failed`).

### Cost guardrails

- Hard cap total runtime at `parallelism * 90s * total_targets / parallelism = 90s * total_targets` (an upper-bound; usually much less).
- If a single target hits 5 minutes, abort that target and mark `failed: timeout`. Continue with the rest.
- Surface running cost (rough token estimate) in the live status output every 60s.

### Live status (every 5s during execution)

```
[14:32:11]  research-html  3/17  ████░░░░░░░░░░░░░░░░  17%   2 failed
                          ⏵ now: john@acme (researching), sarah@beam (deploying)
```

Brief, plain-text. No raw subprocess output.

## Step 5: Dry-Run Preview Checkpoint

If dry-run was enabled, after the first 3 targets finish, STOP and report:

```
Dry-run done — 3 of 17 shipped. Take a look:
  1. John @ Acme    → https://acme-john.example.vercel.app    code 4271
  2. Sarah @ Beam   → https://beam-sarah.example.vercel.app   code 9082
  3. Mike @ Globex  → https://globex-mike.example.vercel.app  code 1573

Eyeball these. Sound right? (continue / adjust angles / cancel)
```

If user adjusts ("the angles are too aggressive, soften them"), re-write the relevant cluster's angle in `batch.json` and continue from target 4.

## Step 6: Generate the Dashboard

When the batch finishes (or partially finishes), generate ONE single-file HTML dashboard using `shared/components/mailmerge-dashboard.html` as the template.

Fill in:
- Header: title (e.g., "Mailmerge — Series A AI, 17 targets"), date, batch_id.
- Stats: total / shipped / failed / replied (replied is 0 fresh — track.js fills in later, P2b).
- Filter chips: one per cluster + one per status.
- Rows: one per target, sorted by cluster then status. Each row has:
  - Target name + company
  - Cluster pill
  - Status pill (`pending|shipped|failed|replied|meeting-booked`)
  - Angle used
  - Open / Copy-DM / Details buttons
  - Expanded details: suggested DM + "Why this angle" reasoning (from cluster pattern)

Save to current working dir as `mailmerge-<batch-id>.html`. Optionally `deploy.sh ship` it too if user wants the dashboard live (off by default — dashboard contains all the URLs and DMs and is intended to stay local).

## Step 7: Hand Back

Brief, two-screen summary.

```
✓ Mailmerge done — 15 shipped, 2 failed.
✓ Dashboard: ./mailmerge-20260517.html  (open with: open ./mailmerge-20260517.html)

  Series A AI cluster (9): all shipped, average page builds 4.2s
  Enterprise SaaS (5): all shipped
  Unclustered (3): 1 shipped, 2 failed (network issues, auto-retried once)

  Suggested DM for John @ Acme:
  "John — saw you're hiring 3 SDRs. Built you a 90-second page on what that
  could look like with our setup. Code's 4271: https://...  Take a look."

  (12 more DMs in the dashboard. Click Copy DM on each row.)

  Want me to retry the 2 failed ones? (yes / no / show me the errors)
```

## Step 8: Record + Learn

Write a batch-level run record:

```bash
memory::quick_run skill=mailmerge-html batch_id="$batch_id" \
  total="$N" shipped="$S" failed="$F" \
  duration_s="$T" clusters="$cluster_json"
```

Update `patterns.json` ONLY through the consolidation pass (P2c) — don't write rules directly here. The run record is what the consolidation pass distills.

## Step 9: Update Preferences

`## User Preferences` at bottom — only update for stable patterns:
- Default parallelism if user has overridden consistently.
- Default cluster→angle if user has approved the same mapping 2+ batches in a row.
- Always-dry-run vs. skip-dry-run preference.

## Common Mistakes to Avoid

1. **Treating mailmerge as a loop.** Without ICP clustering and angle selection, this is a worse `outreach-html`. The clustering is the value.
2. **Skipping the plan-approval checkpoint.** Always pause at Step 3 with the planned angles and skips. Founders catch errors here.
3. **Hammering Vercel with 50 deploys at once.** Respect parallelism. The deploy.sh state machine is shared — collisions matter.
4. **Forgetting to write to memory.** Every target researched gets `targets/<slug>.json`; every outreach attempt gets `past_outreach[]`. Without this, the next batch is research-blind.
5. **Sending DMs the user hasn't seen.** This skill produces URLs and SUGGESTED DMs. Sending is always the user's job (LinkedIn TOS, deliverability). Don't auto-send.
6. **Building the dashboard before the batch finishes.** Generate dashboard at the end (Step 6), not incrementally — partial dashboards confuse.
7. **Pasting raw error stacks.** Same rule as deploy-html: translate to one plain line, point at `~/.cache/html-skills/last-error.md`.

---

## User Preferences (Auto-Updated)

<!--
  Rewritten on successful run. Max 20 lines. Don't append.
-->

- Default parallelism: [not yet learned]
- Default dry-run policy: ask first run, learned after
- Cluster→angle defaults: [pulled from patterns.json; not yet learned]
- Dashboard deploy default: false (stays local)
- Auto-retry failed targets: ask (default)
- Last updated: [never]

---

## Saved Config (Human-Readable Mirror)

<!--
  Mirror of recent batch state. The authoritative copy lives at
  ~/.cache/html-skills/mailmerge/<batch-id>/batch.json.
-->

- Last batch_id: [none]
- Last batch source: [none]
- Last batch targets: [none]
- Last batch shipped / failed: [none]
- Last batch finished at: [never]

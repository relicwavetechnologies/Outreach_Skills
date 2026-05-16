# html-skills

**Skills that turn Claude Code & Codex into a rich-HTML generator.**

Instead of getting markdown back, you get a styled, animated, interactive HTML page — a research report, a pitch deck, a planning doc, a code review, a triage tool — saved as a single `.html` file you can open in your browser or deploy to a live URL.

---

## What is a "skill"?

A skill is a Markdown instruction file (`SKILL.md`) that tells Claude Code or Codex *how to behave* when it detects a certain kind of request. There's no code to run, no service to host. The skill files live in `~/.claude/skills/` (or `~/.codex/skills/`) and the AI reads them when it needs them.

These skills make the AI:

- Ask you a few short questions in plain language.
- Do the work (research, write, design).
- Output a beautiful, interactive HTML file.
- Quietly remember your preferences so it asks fewer questions next time.

---

## Install

One command:

```bash
curl -fsSL https://raw.githubusercontent.com/relicwavetechnologies/Outreach_Skills/main/install.sh | bash
```

The installer will:

1. Detect if you have Claude Code, Codex, or both.
2. Ask which skills you want (all / outreach bundle / pick).
3. Drop the SKILL.md files in the right place.

That's it. Restart your AI, and the skills are live.

---

## The Skills

| Skill              | What it does                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------- |
| **research-html**  | Researches a company / founder / competitor and outputs a rich interactive HTML report.    |
| **present-html**   | Turns any content into a scroll-driven, animated HTML presentation. Optional OTP gate.     |
| **deploy-html**    | Puts any HTML file on a live URL via Vercel. First time it walks setup, then it's silent.  |
| **outreach-html**  | Full pipeline — research a founder, build a personalized page, deploy, hand back the link. |
| **mailmerge-html** | Batch outreach: CSV → N personalized pages → N URLs + DMs + one summary dashboard.        |
| **plan-html**      | Interactive planning docs — process, system, project, or decision. Embedded visuals.       |
| **review-html**    | Code/PR review as a visual HTML report — severity-coded findings, annotated diffs.         |
| **editor-html**    | Generates a single-file HTML editor for your data (kanban, table, sortable, prompt tuner). |

---

## Self-learning

Every skill has a `## User Preferences` section at the bottom of its `SKILL.md`. After each successful run, the skill quietly rewrites that section based on what worked.

**Your first run:**
> *"Cool, researching Acme Corp. Quick — fast overview, or deep dive into competitors and tech stack?"*

**Your fifth run:**
> *"On it — researching Acme Corp (deep dive as usual)."* 

It doesn't grow forever — sections are capped and rewritten cleanly each time, not appended.

Company-level info you'd never want re-asked (your name, your company's pitch angle, brand voice) lives in `shared/profile.md` — read by every skill, written by any.

---

## Example: the outreach pipeline end-to-end

Say you (or your outreach teammate) wants to reach out to a founder. You type:

> *"Outreach to John at Acme Corp"*

What happens:

1. **outreach-html** activates. It reads `shared/profile.md` to know who YOU are (your company, your pitch angle).
2. **Asks you:** "Got his LinkedIn? Anything different this time?" That's it.
3. **Researches Acme** — products, John's background, their current outreach process (from job listings), recent news.
4. **Summarizes findings** and pauses: *"Here's what I found. Sound right?"*
5. **Builds a one-of-one HTML page** — hero references John's specific situation, "we get you" cards cite real research, an animated workflow comparison races their current process against yours (left side slow, right side fast, win banner appears).
6. **Deploys to Vercel** silently (since deploy is already set up).
7. **Hands back:**

   ```
   ✓ Live: https://acme-john.outreach.yourco.vercel.app
   ✓ Code: 4271

   Page is 7 sections — hero hits the SDR-hiring angle, includes the
   workflow race showing 12 days → 8 min for their outbound, ends with
   a Calendly link.

   Suggested DM to John:
   "John — saw you're hiring 3 SDRs. Built you a quick page on what
   that could look like with our setup. Code's 4271: [link]. 90 seconds."
   ```

You copy the DM, paste into LinkedIn. Done.

---

## Repo structure

```
skills-html/
├── README.md
├── install.sh
├── shared/
│   ├── profile.md              # your profile — read by every skill
│   ├── design-tokens.css       # one design language across all outputs
│   ├── SCHEMAS.md              # memory + run JSON schema contracts
│   ├── lib/                       # executable helpers (NOT prose for the LLM)
│   │   ├── log.sh                 # status/error helpers, last-error.md writer
│   │   ├── memory.sh              # ~/.cache/html-skills/ init + JSON I/O + target/run helpers
│   │   ├── csv.sh                 # RFC 4180 CSV parser (python3-backed)
│   │   └── deploy.sh              # Vercel deploy state machine (production-grade)
│   └── components/                # reusable HTML snippets skills paste into output
│       ├── confidence-dot.html    # inline confidence indicators (high/medium/low)
│       ├── sources-footer.html    # citations block at end of every report
│       ├── insight-block.html     # the visual grammar for insight sections
│       └── mailmerge-dashboard.html # batch summary: filter chips, copy-DM, open-all
├── skills/
│   ├── research-html/SKILL.md
│   ├── present-html/SKILL.md
│   ├── deploy-html/SKILL.md
│   ├── outreach-html/SKILL.md
│   ├── mailmerge-html/SKILL.md
│   ├── plan-html/SKILL.md
│   ├── review-html/SKILL.md
│   └── editor-html/SKILL.md
└── tests/
    ├── test-deploy-dryrun.sh   # offline state-machine tests (no network)
    ├── test-memory.sh          # memory.sh target/run/dedupe tests
    ├── test-csv.sh             # csv.sh parser tests (RFC 4180 quirks)
    └── smoke-deploy.sh         # real Vercel deploy + teardown
```

## Per-user runtime cache

Created on install (or on first skill run) at `~/.cache/html-skills/`:

```
~/.cache/html-skills/
├── memory/
│   ├── profile.json       # canonical user/company profile
│   ├── voice.json         # learned voice attributes
│   ├── patterns.json      # what's worked across runs
│   ├── targets/           # per-target context (acme-corp.json, …)
│   ├── runs/              # per-run logs
│   └── outcomes/feedback.jsonl
├── state/
│   └── deploy.json        # vercel setup + last deploy URL (source of truth)
└── last-error.md          # human-readable diagnostic on any failure
```

## Architecture: skills delegate to shell

Skills are still Markdown that the AI reads. But operational logic — env checks,
auth polling, deploy state transitions, error capture — lives in real executable
scripts under `shared/lib/`. The skill markdown says *"call `deploy.sh ship FILE`
and report the URL"*; the script does the actual work.

This means:

- **The Vercel auth-loop bug is gone.** After `vercel login`, the script polls
  `vercel whoami` every 5s for up to 90s before declaring failure. No more
  "auth landed but the skill stopped."
- **Deploy state is a real state machine.** Phases are `fresh → awaiting-auth
  → ready → deployed`. Stored as JSON in `~/.cache/html-skills/state/deploy.json`.
- **Failures write a diagnostic file.** Every hard failure produces
  `~/.cache/html-skills/last-error.md` with command, exit code, captured stderr,
  and a suggested next step. Paste it into a bug report and you're done.

## Cross-skill memory (the engine that makes the system learn)

Every skill reads from and writes to `~/.cache/html-skills/memory/`:

- **`targets/<slug>.json`** — everything any skill ever learned about a company, founder, or prospect. `research-html` writes facts here; `outreach-html` reads them and refuses to re-use angles that already shipped.
- **`runs/<run_id>.json`** — one record per skill execution. Inputs, draft sections, shipped sections, edits, outcomes. The substrate for `patterns.json` consolidation later.
- **`profile.json` / `voice.json` / `patterns.json`** — user/company profile, learned writing style, distilled rules. Read on every skill startup.
- **`outcomes/feedback.jsonl`** — append-only event log (P2 surface).

Full schemas in [`shared/SCHEMAS.md`](shared/SCHEMAS.md). Skills MUST go through `memory::*` helpers in `shared/lib/memory.sh` — `memory::add_fact`, `memory::add_person`, `memory::add_outreach`, `memory::merge_target`, `memory::quick_run`, etc. — so writes stay atomic, deduped, and schema-conformant.

## Confidence-tagged research + insight sections

`research-html` and `outreach-html` now produce more than summaries:

- **Slot-based research plan** built BEFORE any web search. Each fact gets a `high | medium | low` confidence tag; the page renders a dot next to non-obvious claims so the reader can calibrate.
- **Sources footer** — every URL fetched, with fetch date. Founders click; trust compounds.
- **Insight sections** — *Why This Matters For You*, *Hooks (ranked)*, *Probably Already Considered*, *Risk Flags*, *Trojan-Horse One-Liner*. These are what turn the artifact from "informed" to "persuasive."

The visual grammar for these lives in `shared/components/insight-block.html`. Skills paste the CSS once, then build one `<section data-kind="…">` per insight.

## Batch outreach (mailmerge)

`mailmerge-html` turns the one-at-a-time outreach pipeline into a batch engine. Feed a CSV; get N personalized pages + N suggested DMs + one summary dashboard.

What makes it more than a loop:

- **ICP clustering** — targets are bucketed by stage / size / industry from researched facts.
- **Angle selection per cluster** — reads `patterns.json` (when populated) to pick the angle that's worked best for similar clusters in your past data. Falls back to `profile.json.pitch_angle`.
- **Memory-aware** — skips re-research on targets known < 14 days, refuses to repeat any angle in a target's `past_outreach[]`, halts on severe risk flags.
- **Dry-run preview** — first 3 targets ship → you eyeball → confirm → the rest run. Default-on for first batch / batches > 10.
- **Cost guardrails** — bounded parallelism (3 / 5 depending on batch size), per-target timeout, total batch cost ceiling.
- **Dashboard output** — one HTML file with filter chips (status / cluster), per-row Open / Copy-DM / Why-this-angle, an "Open all" button.

Try it:
> *"Mailmerge these 20 founders for me — CSV is at ~/Downloads/leads.csv"*

## Testing

```bash
# Offline tests — no network, no vercel CLI required
bash tests/test-deploy-dryrun.sh   # 37 assertions on the deploy state machine
bash tests/test-memory.sh          # 46 assertions on memory helpers
bash tests/test-csv.sh             # 28 assertions on the CSV parser (quirks + edge cases)

# Real Vercel smoke test (creates + verifies + tears down a real deploy)
export VERCEL_SMOKE_PROJECT=html-skills-smoke
vercel login    # one-time
bash tests/smoke-deploy.sh
```

---

## For non-technical users

Three steps:

1. **Open Terminal** (it's on your Mac in Applications → Utilities, or hit ⌘+Space and type "terminal"). Paste the install command above and hit enter.
2. **Pick what you want** — when it asks, type `1` for everything.
3. **Talk to Claude Code or Codex like a coworker** — *"do an outreach for me to John at Acme Corp"*, *"research this company"*, *"make a deck out of this doc"*. The skill activates automatically.

You never need to think about which skill to use. You just describe what you want; the AI picks the right skill, asks the questions, and hands back the file or link.

If anything breaks: re-run the install command. It's safe to run multiple times.

---

## Design

All HTML outputs share one visual language — fonts, colors, motion — defined in `shared/design-tokens.css`. So a founder who clicks a research report, then a pitch page, then a workflow visualization feels like they were all made by the same brand. Dark theme by default; light theme works via `data-theme="light"` on `<html>`.

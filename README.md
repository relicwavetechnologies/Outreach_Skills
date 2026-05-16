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
│   ├── profile.md          # your profile — read by every skill
│   └── design-tokens.css   # one design language across all outputs
└── skills/
    ├── research-html/SKILL.md
    ├── present-html/SKILL.md
    ├── deploy-html/SKILL.md
    ├── outreach-html/SKILL.md
    ├── plan-html/SKILL.md
    ├── review-html/SKILL.md
    └── editor-html/SKILL.md
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

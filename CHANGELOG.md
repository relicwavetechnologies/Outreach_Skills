# Changelog

All notable changes to `html-skills`. Newest first.

This project tracks work in **P-numbered iterations** rather than semver — each P is a coherent capability landed via one or more PRs. Skip a P at your own risk; later Ps generally depend on earlier ones.

---

## [P2d] — Consolidation pass: the system learns  *(branch: `p2d-consolidation`)*

The loop closes. P0 made deploys reliable, P1 added memory, P2a added volume, P2b added the outcomes signal — but until now nothing was *reading* the outcomes to make future decisions smarter. P2d is that read pass.

### Added

- **`shared/lib/patterns.sh`** — the consolidation pass. Reads `memory/runs/*.json` + `memory/outcomes/feedback.jsonl` + `memory/targets/*.json`, joins them, distills into rules at `memory/patterns.json`. Three rule kinds:
  - **`cluster_angle`** — for each `(cluster, angle)` pair seen ≥ 2 times: reply rate, decided count, confidence.
  - **`section_survival`** — for each section name in draft/shipped arrays: `survival_rate = shipped / drafted`, with a recommendation bucket (`always | usually | rarely | skip`).
  - **`section_engagement`** — when a section's presence correlates with a ≥ 0.10 absolute reply-rate delta.

  Plus drift detection: previous `patterns.json` is rotated to `patterns.previous.json` each consolidation. Rules whose `reply_rate` or `survival_rate` moved by ≥ 0.30 between runs are surfaced as `drift_alerts[]`.

- **CLI commands** on `patterns.sh`:
  - `consolidate` — rebuild patterns.json
  - `auto-consolidate [days]` — no-op if patterns.json is fresh (default 7d)
  - `report [days]` — human-readable rollup
  - `drift` — show drift alerts
  - `reset` — wipe patterns.json (history preserved)
  - `angle-for-cluster <cluster> [fallback]` — used by mailmerge
  - `section-recommendation <section>` — used by outreach/research

- **Skill wiring**:
  - `mailmerge-html` now calls `patterns::angle_for_cluster` per cluster to pick the highest-evidence angle. Falls back to `profile.json.company.pitch_angle` when no data. Surfaces drift alerts in the plan-approval pause.
  - `outreach-html` and `research-html` consult `patterns::section_recommendation` before drafting heavy insight sections. `skip` skips, `rarely` shrinks, `always`/`usually`/`unknown` draft normally.
  - All three skills now write *richer* run records (with `cluster`, `draft_sections`, `shipped_sections`) via `memory::write_run` JSON form, so subsequent consolidations have the data to compute everything.

- **`tests/test-patterns.sh`** — 28 assertions covering empty memory, cluster_angle synthesis with mixed outcomes, section_survival across drafted/shipped diffs, section_engagement deltas, lookups with fallback, drift detection across consolidations, auto-consolidate freshness, report rendering, reset preserving previous.

### Fixed

- **`memory::write_run` was hostile to multiple writes from the same shell.** It used `$HTML_SKILLS_RUN_ID` env var as the destination filename — so a skill writing two run records (one quick + one rich, common pattern in P2d) overwrote the first. New behavior: prefer `.run_id` from the JSON content, fall back to env, fall back to generated. Backwards-compatible; surfaced by the new integration assertions.

### CI

- `test-patterns.sh` and the extended `test-integration.sh` (45 assertions, +7 from P2c) are gated by `.github/workflows/ci.yml`.

### Test counts

```
P2c snapshot:  37 + 46 + 28 + 24 + 23 + 38 = 196   + 47 lint = 243
P2d snapshot:  37 + 46 + 28 + 24 + 23 + 28 + 45 = 231 + 47 lint = 278
                                       ↑    ↑
                            patterns: 28  integration: 38→45
```

---

## [P2c] — Quality, hardening, and CI  *(branch: `p2c-harden`)*

The first PR in this project that adds **no new features.** Everything here is making what we've already shipped trustworthy.

### Added

- **`tests/test-integration.sh`** — end-to-end pipeline that exercises every shared lib together: profile → research → page generation with components → tracker injection → deploy.sh ship (dry-run) → outreach recorded → 48h-pass simulation → one-tap reply → outcome stats. 38 assertions.
- **`tests/lint-skills.sh`** — static analysis of `skills/*/SKILL.md`: YAML frontmatter, bash blocks parse via `bash -n`, every referenced `shared/lib/*.sh` and `shared/components/*.html` resolves, every `memory::*` / `outcomes::*` / `track::*` helper called by a skill is actually defined in some lib.
- **`tests/lint-js.sh`** — `node --check` on `track.js` (classic script) and `track-server.js` (ESM). Plus content checks: no `TODO`/`FIXME`, no `console.*` leaks in the client, `'use strict'` + IIFE wrapper present, `.slice()` length-caps present in the server.
- **`.github/workflows/ci.yml`** — runs all 6 test suites + 2 linters on every push and PR. Real gate now, not just local promises.
- **`CHANGELOG.md`** — this file. P-by-P narrative so contributors and future-me can understand the arc.

### Fixed

Bugs surfaced by the new tests and fixed in this same PR:

- **`outcomes::stats` undercounted replies.** The function was filtering on `event=="reply"`, but `outcomes::set_outreach_outcome "replied"` emits `event=="replied"`. So every replied outreach has been invisible to stats since P2b shipped. Fixed: match `replied | no_reply | meeting_booked` consistently with the helper. Old `test-outcomes.sh::T3.3` was masking the bug by writing `event="reply"` directly — rewritten to exercise the real flow.
- **`outcomes::record` dropped events without extras.** Bash brace-default expansion `${3:-{\}}` mis-parsed and produced an unparseable jq argument. Replaced with explicit empty-check. (Fixed in P2b, kept here for the record.)
- **`track::inject` couldn't carry multi-line scripts via `awk -v`.** Replaced with a temp-file splice using awk's `getline`. (Fixed in P2b.)
- **Three `SKILL.md` bash blocks had `<placeholder>` syntax** that bash parses as input redirection. Replaced with proper `$variable` references. Affected `outreach-html`, `research-html`, and the linter's regex caught the `mailmerge-html` false-positive variant.
- **`lint-skills.sh` regex missed indented fenced blocks.** Numbered-list bash blocks weren't being parsed. Regex now tolerates up to 4 spaces of indent on each fence.

### Hardened

`shared/components/track-server.js` is a public endpoint. Real production discipline:

- **Event-name allowlist** — only the 9 event names actually emitted by `track.js` are accepted. Junk events are rejected with 400.
- **`run_id` format validation** — must match `^[A-Za-z0-9._:-]+$` and ≤ 80 chars. Prevents unbounded KV key sprawl.
- **Replay window** — events older than 7 days OR more than 1 hour in the future are rejected. Tolerates reasonable clock skew.
- **Query-string stripping** on `page` and `referrer` — defensive against accidentally logged tokens/emails in URLs.
- **Per-session rate limiting** — 60 events/minute per session via Vercel KV `incr` with a 90s TTL. Spammers get silently 204'd, not 429'd (so they don't learn the limit).
- **Per-run KV cap** — `hs:run:<id>` lists trimmed to 1k entries. Plus the existing global `hs:recent` cap of 10k.

### Internal

- `test-outcomes.sh::T3` rewritten to use the real `replied`/`no_reply`/`meeting_booked` event names. Adds T3.4 (no_reply) and T3.7 (scroll breakdown).
- `tests/test-integration.sh` is the canonical "does the whole thing actually work?" check. It's the only test you can't write a unit test for, and the only one that would have caught the stats bug above.

### Test counts

```
deploy-dryrun:      37
memory:             46
csv:                28
outcomes:           24   (was 22; +T3.4 +T3.7)
track:              23
integration:        38   ← new
lint-skills:        40   ← new (static analysis, not assertions per se but pass/fail)
lint-js:             7   ← new
─────────────────────────
TOTAL:             243
```

---

## [P2b] — Outcomes signal and opt-in tracker  *(branch: `p2b-outcomes-and-tracking`)*

The feedback loop. Until P2b the system was blind to whether anything we shipped actually worked.

### Added

- **`shared/lib/outcomes.sh`** — append-only event log at `~/.cache/html-skills/memory/outcomes/feedback.jsonl`. Helpers: `append`, `record`, `stats`, `pending_replies`, `set_outreach_outcome`.
- **One-tap reply prompt** — `outcomes::pending_replies <hours>` lists outreaches > N hours old still marked `pending`. Wired into the startup of `outreach-html` and `mailmerge-html` so the skill asks once per session: *"Did John reply?"* Two taps. The strongest signal we can get.
- **`shared/components/track.js`** — ~2 KB privacy-respecting client tracker. No cookies, no fingerprinting, no third-party. Honors `navigator.doNotTrack`. Uses `sendBeacon`. Emits `page_view`, `scroll_*`, `dwell_*`, `cta_click`.
- **`shared/components/track-server.js`** — Vercel + `@vercel/kv` serverless template. User-owned endpoint. Setup wizard scaffolds + walks through the one-time deploy.
- **`shared/lib/track.sh`** — orchestrator: `status / enable / disable / inject / setup / sync / set-endpoint`. State at `~/.cache/html-skills/state/track.json`.
- **`tests/test-outcomes.sh`** (22 assertions originally; 24 after P2c rewrite).
- **`tests/test-track.sh`** (23 assertions).

---

## [P2a] — Mailmerge (batch outreach)  *(branch: `p2-mailmerge`)*

The volume leverage move.

### Added

- **`skills/mailmerge-html/SKILL.md`** — CSV in, N personalized pages + N suggested DMs + one summary dashboard out. ICP clustering, per-cluster angle selection, memory-aware skip, dry-run preview, bounded parallelism, cost ceilings.
- **`shared/lib/csv.sh`** — RFC 4180 parser via python3. Handles quoted-comma, escaped-quote, multi-line, UTF-8 BOM. API: `validate`, `header`, `count`, `parse` (jsonl), `row`, `detect_field`.
- **`shared/components/mailmerge-dashboard.html`** — sortable/filterable single-file dashboard. Per-row Open / Copy-DM / Why-this-angle. "Open all" bulk action.
- **`tests/test-csv.sh`** (28 assertions).
- `python3` becomes a required dependency. Installer surfaces it explicitly.

---

## [P1] — Cross-skill memory, slot-based research, insight sections  *(branch: `p1-research-insight-memory`)*

Made the system substantive instead of just well-formatted.

### Added

- **`~/.cache/html-skills/memory/`** layout — `profile.json`, `voice.json`, `patterns.json`, `targets/<slug>.json`, `runs/<run_id>.json`, `outcomes/feedback.jsonl`. Full contract in `shared/SCHEMAS.md`.
- **`shared/lib/memory.sh`** target/run helpers: `target_path`, `read_target`, `write_target`, `init_target`, `merge_target`, `add_fact`, `add_person`, `add_outreach`, `mark_researched`, `write_run`, `quick_run`.
- **`shared/components/{confidence-dot,sources-footer,insight-block}.html`** — reusable HTML snippets the skills paste into generated pages.
- **`skills/research-html/SKILL.md`** rewritten: slot-based research plan, source diversification, confidence scoring (`high|medium|low`), insight sections required (Why-this-matters, Hooks ranked, Probably-already-considered, Risk-flags, Trojan-horse one-liner), writes to `targets/<slug>.json`, diff mode on re-research.
- **`skills/outreach-html/SKILL.md`** — reads existing target context, refuses to repeat angles in `past_outreach[]`, applies the same insight discipline.
- **`tests/test-memory.sh`** (46 assertions).

---

## [P0] — Reliable deploys  *(branch: `p0-reliable-deploys`)*

The foundation. Fixed the Vercel auth-loop bug ("auth landed in browser but the skill stopped"). Extracted operational deploy logic from interpretable Markdown into an executable state machine.

### Added

- **`shared/lib/log.sh`** — colored status helpers + `last-error.md` writer.
- **`shared/lib/memory.sh`** — idempotent `~/.cache/html-skills/` skeleton init, atomic JSON state I/O.
- **`shared/lib/deploy.sh`** — production-grade Vercel deploy state machine. Phases: `fresh → awaiting-auth → ready → deployed`. Commands: `status | check | setup | ship | reset`. Polls `vercel whoami` every 5s for up to 90s after launching login (this is the bug fix). Uses `vercel link` for project stickiness. Robust URL capture via regex + `vercel ls --json` fallback. Per-call timeouts. Diagnostic file on hard failure.
- **`tests/test-deploy-dryrun.sh`** (37 assertions) + **`tests/smoke-deploy.sh`** (real Vercel deploy + teardown).

---

## Earlier

Initial commit shipped the seven base skills (`research-html`, `present-html`, `deploy-html`, `outreach-html`, `plan-html`, `review-html`, `editor-html`), `shared/profile.md`, `shared/design-tokens.css`, and a curl-bash installer.

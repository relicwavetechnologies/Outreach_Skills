# Memory & Run Schemas

This document defines the JSON shapes that live in `~/.cache/html-skills/`. Every skill reads from and writes to this directory; the schemas here are the contract.

The shapes are enforced by helpers in `shared/lib/memory.sh` (preferred) — skills should call helpers rather than emit raw JSON, but skills that need ad-hoc fields can write directly as long as they preserve the documented fields.

---

## File layout

```
~/.cache/html-skills/
├── memory/
│   ├── profile.json              # user/company profile (1 file)
│   ├── voice.json                # learned voice attributes (1 file)
│   ├── patterns.json             # cross-run distilled rules (1 file)
│   ├── targets/                  # 1 file per researched entity
│   │   ├── acme-corp.json
│   │   └── …
│   ├── runs/                     # 1 file per skill invocation
│   │   ├── 20260517-153201-research-html-a3f1.json
│   │   └── …
│   └── outcomes/
│       └── feedback.jsonl        # 1 line per outcome event (open, reply, etc.)
└── state/
    └── deploy.json               # see deploy.sh — phase machine state
```

---

## `memory/targets/<slug>.json`

The spine of cross-skill memory. Every company / founder / prospect any skill ever researched lives here. Re-reads on every subsequent skill run for that target.

```json
{
  "slug": "acme-corp",
  "name": "Acme Corp",
  "urls": {
    "site": "https://acme.com",
    "linkedin": "https://linkedin.com/company/acme",
    "crunchbase": "https://crunchbase.com/organization/acme"
  },
  "created_at": "2026-05-17T15:32:00Z",
  "last_researched": "2026-05-17T15:32:00Z",
  "research_freshness_score": 0.84,

  "facts": [
    {
      "claim": "Series A, 40 employees, raised $12M Apr 2025",
      "source": "https://crunchbase.com/organization/acme",
      "confidence": "high",
      "fetched": "2026-05-17T15:32:00Z"
    }
  ],

  "people": [
    {
      "name": "John Smith",
      "role": "CEO",
      "linkedin": "https://linkedin.com/in/johnsmith",
      "voice": "warm, values-driven, posts weekly",
      "public_quotes": [
        "we'll never sacrifice human-feeling for speed"
      ]
    }
  ],

  "past_outreach": [
    {
      "run_id": "20260517-153201-outreach-html-a3f1",
      "url": "https://acme-john.outreach.relicwave.vercel.app",
      "angle": "SDR-hiring",
      "outcome": "pending",
      "at": "2026-05-17T15:32:00Z"
    }
  ],

  "do_not_use_angles": ["pricing-led"],

  "user_corrections": [
    {
      "date": "2026-05-17T15:30:00Z",
      "correction": "they actually just hired a head of growth — skip SDR angle"
    }
  ]
}
```

### Field semantics

| Field | Type | Notes |
|---|---|---|
| `slug` | string | URL-safe identifier. `memory::slugify` produces it. |
| `name` | string | Display name. |
| `urls` | object | Free-form keyed URLs (site, linkedin, crunchbase, …). |
| `created_at` | ISO timestamp | Set on first init, never changed. |
| `last_researched` | ISO timestamp \| null | Updated by `memory::mark_researched`. |
| `research_freshness_score` | float 0..1 | 1.0 right after a fresh deep dive; decays over time. Skills can read this to decide whether to re-research. |
| `facts[]` | array | Each fact has `claim`, `source`, `confidence` (`high`/`medium`/`low`), `fetched`. Deduped on `claim` by `memory::add_fact`. |
| `people[]` | array | Each person has `name`, `role`, `linkedin` (optional), `voice` (optional), `public_quotes[]` (optional). Deduped on `linkedin` first, then `name+role`. |
| `past_outreach[]` | array | Append-only via `memory::add_outreach`. `outcome` is `pending` until updated. |
| `do_not_use_angles[]` | array of strings | Angles that have been tried and failed, or that user vetoed. |
| `user_corrections[]` | array | Human-in-the-loop corrections. Skills MUST respect these. |

### Confidence rules

- `high` = two independent sources agreed, OR a primary source (the target's own site / their public filing).
- `medium` = single reasonable source, plausible but not cross-verified.
- `low` = inferred / guessed / from a noisy source. UI shows these with a small dim indicator; never present them without that visual cue.

### Conflict resolution

When a new fact contradicts an existing one with the same claim text, `memory::add_fact` replaces (latest write wins). When claims DIFFER but refer to the same attribute (e.g., two different headcounts), both are kept — the rendering layer is responsible for flagging "sources disagree."

---

## `memory/runs/<run_id>.json`

One file per skill invocation. The substrate of cross-run learning: edits made vs. shipped, what worked, what didn't.

```json
{
  "run_id": "20260517-153201-research-html-a3f1",
  "skill": "research-html",
  "started_at": "2026-05-17T15:32:01Z",
  "finished_at": "2026-05-17T15:39:14Z",
  "target_slug": "acme-corp",

  "inputs": {
    "asked": ["target_name", "depth"],
    "inferred_from_memory": ["voice", "pitch_angle"]
  },

  "research_plan": {
    "slots_attempted": ["company_basics", "founder", "tech_stack", "pain", "news"],
    "slots_filled": ["company_basics", "founder", "pain", "news"],
    "slots_not_found": ["tech_stack"]
  },

  "sources": [
    { "url": "https://crunchbase.com/...", "fetched_at": "...", "used_for": ["company_basics"] }
  ],

  "draft_sections": ["header", "at_a_glance", "company", "founder", "pain", "hooks", "risk_flags", "trojan_horse", "sources_footer"],
  "shipped_sections": ["header", "at_a_glance", "company", "founder", "pain", "hooks", "trojan_horse", "sources_footer"],
  "edits": [
    { "section": "hero", "kind": "shortened", "delta": "14→8 words" },
    { "section": "risk_flags", "kind": "deleted", "delta": null }
  ],

  "delivery": {
    "html_path": "/Users/.../research-acme-2026-05-17.html",
    "url": null,
    "dm_text": null
  },

  "outcomes": {
    "opens": null,
    "max_dwell_s": null,
    "replied": null,
    "meeting_booked": null
  }
}
```

`outcomes` starts null; `track.js` (P2) fires events into `outcomes/feedback.jsonl`, and a consolidation pass joins them back into the run record.

---

## `memory/profile.json`

Canonical user/company profile. The Markdown `shared/profile.md` is now a human-readable mirror of this — skills should treat the JSON as truth.

```json
{
  "user": {
    "name": "Anugra",
    "role": "Founder",
    "company": "Relicwave",
    "timezone": "America/Los_Angeles"
  },
  "company": {
    "one_liner": "AI outbound that doesn't feel like AI outbound",
    "how_we_help": "Replace SDR teams with personalized URL-based outreach",
    "typical_client": "Series A / B SaaS, 20-200 employees",
    "pitch_angle": "we get you, then we ship it"
  },
  "brand_voice": {
    "tone": "warm, sharp, no fluff",
    "words_use": ["actually", "ship", "real"],
    "words_avoid": ["leverage", "synergy", "solution"],
    "signature_phrases": ["one-of-one"]
  },
  "general_preferences": {
    "research_depth_default": "standard",
    "design_style": "dark, geometric, animated-but-restrained",
    "theme_default": "dark",
    "deployment_platform": "vercel",
    "cta_style": "single button, calendly"
  }
}
```

---

## `memory/voice.json`

Learned writing style. Populated over time by observing what the user keeps vs. cuts.

```json
{
  "avg_sentence_words": 11,
  "preferred_openers": ["Quick one:", "Saw you…"],
  "rejected_openers": ["I hope this finds you well"],
  "punctuation_signature": "em-dashes, ellipses, lowercase headers",
  "last_updated": "2026-05-17T15:32:00Z"
}
```

---

## `memory/patterns.json`

Distilled rules across all runs. Rewritten by the consolidation pass in `shared/lib/patterns.sh`. Skills read this on startup and use it to bias defaults.

```json
{
  "version": 1,
  "last_consolidated": "2026-05-17T15:32:00Z",
  "runs_analyzed": 47,
  "decided_outreaches": 22,
  "rules": [
    {
      "id":            "angle:series-a-ai:scale-outbound-not-headcount",
      "kind":          "cluster_angle",
      "cluster":       "series-a-ai",
      "angle":         "scale-outbound-not-headcount",
      "evidence_runs": 12,
      "decided":       9,
      "outcomes":      { "replied": 4, "no_reply": 4, "meeting_booked": 1, "pending": 3 },
      "reply_rate":    0.556,
      "confidence":    "high"
    },
    {
      "id":             "section:risk_flags",
      "kind":           "section_survival",
      "section":        "risk_flags",
      "evidence_runs":  6,
      "drafted":        6,
      "shipped":        1,
      "survival_rate":  0.167,
      "recommendation": "skip",
      "confidence":     "medium"
    },
    {
      "id":                   "engagement:workflow_comparison",
      "kind":                 "section_engagement",
      "section":              "workflow_comparison",
      "reply_rate_with":      0.62,
      "reply_rate_without":   0.18,
      "delta":                0.44,
      "n_with":               13,
      "n_without":            9,
      "confidence":           "high"
    }
  ],
  "drift_alerts": [
    {
      "kind":                  "angle_drift",
      "rule_id":               "angle:series-a-ai:scale-outbound-not-headcount",
      "angle":                 "scale-outbound-not-headcount",
      "cluster":               "series-a-ai",
      "previous_reply_rate":   0.55,
      "current_reply_rate":    0.22,
      "delta":                 -0.33,
      "direction":             "down"
    }
  ]
}
```

### Rule kinds

| `kind` | Generated when | Used by |
|---|---|---|
| `cluster_angle` | (cluster, angle) pair appears in ≥ 2 runs. `cluster` may be `null` if the run didn't carry a cluster tag — `_any` bucket. | `mailmerge-html` calls `patterns::angle_for_cluster <cluster>` to pick the highest-confidence angle. |
| `section_survival` | A section name appeared in ≥ 2 draft lists. `survival_rate = shipped / drafted`. Recommendation buckets: `always` (≥ 0.85), `usually` (≥ 0.50), `rarely` (≥ 0.20), `skip` (< 0.20). | `outreach-html` / `research-html` call `patterns::section_recommendation <section>` to decide whether to draft. |
| `section_engagement` | A section shows ≥ 0.10 absolute reply-rate delta vs runs without it, with at least 2 decided outcomes on each side. | Surfaced in `patterns::report`; informational. |

### Confidence buckets

Determined by evidence count, NOT by p-values (we're working with tiny n's):

- `low` — 2–4 evidence runs
- `medium` — 5–9 evidence runs
- `high` — 10+ evidence runs
- `insufficient` — single observation (rules never emitted at this level)

### Drift alerts

After each consolidation, the previous `patterns.json` is rotated to `patterns.previous.json`. Drift detection compares matching rule IDs:

- **Angle drift**: `reply_rate` moved by ≥ 0.30 absolute between consolidations.
- **Section drift**: `survival_rate` moved by ≥ 0.30 absolute.

Alerts are written into `patterns.json.drift_alerts[]` and surfaced by `patterns::drift` and `patterns::report`. Skills can read this to caveat their own recommendations ("this angle has been working — but reply rate dropped this week, worth a fresh look").

### Update discipline

- Skills MUST NOT write `patterns.json` directly. Only `patterns::consolidate` writes it.
- Skills MAY call `patterns::auto_consolidate` at startup — it's a no-op if `last_consolidated` is < 7 days old.
- `patterns::reset` deletes `patterns.json` but preserves `patterns.previous.json`.

---

## `memory/outcomes/feedback.jsonl`

Append-only event log. One JSON object per line. Populated by `track.js` (P2) and by one-tap user feedback.

```jsonl
{"event":"page_view","run_id":"...","at":"2026-05-17T16:10:00Z","session":"anon-abc123"}
{"event":"scroll_50","run_id":"...","at":"2026-05-17T16:10:34Z","session":"anon-abc123"}
{"event":"cta_click","run_id":"...","at":"2026-05-17T16:11:02Z","session":"anon-abc123"}
{"event":"user_reported_reply","run_id":"...","at":"2026-05-19T09:00:00Z","replied":true,"hours_to_reply":41}
```

---

## `state/deploy.json`

Owned by `shared/lib/deploy.sh`. Documented at the top of that file. Phases: `fresh → awaiting-auth → ready → deployed`.

---

## Update discipline

1. **Skills MUST go through `memory::*` helpers** for any documented field. Raw writes risk schema drift.
2. **New fields are additive.** Don't rename or remove fields — older skill versions still in the wild may read them.
3. **Timestamps are always UTC ISO-8601** (`date -u +%Y-%m-%dT%H:%M:%SZ`).
4. **Atomic writes only.** Use `memory::write_target` (it writes to `*.tmp.$$` and `mv`s) — never `>` into the live file.
5. **Privacy:** nothing in this tree should ever leave the user's machine without an explicit deploy. The cache is local-only.

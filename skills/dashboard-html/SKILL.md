---
name: dashboard-html
description: Use this skill ANY time the user wants to SEE the state of their outreach + research system — what's been shipped, what's working, what's pending, what's drifting. Triggers include "show me the dashboard", "how's outreach going", "what's my outreach status", "give me a rollup", "what's working lately", "anything I'm missing", "stats", "what's the state of things", "where are we at". Produces a single self-contained HTML file: KPI cards, top-performing angles, pending follow-ups, drift alerts, recent targets, and a learn-loop status. Reads directly from ~/.cache/html-skills/memory/ — no network, no LLM judgment calls about the data, just rendering what the system has actually observed.
---

# dashboard-html

The meta-view. Reads every shipped artifact (patterns.json, outcomes/feedback.jsonl, targets/*.json, runs/*.json) and renders a single rich HTML page that shows the user where the system actually stands.

This is the only HTML skill that **produces no new substantive content** — it's a presentation of the data that already exists. Cheap to run; should feel instant after the first call.

---

## Step 0: Read Shared Context

1. Read `../../shared/profile.md` and `~/.cache/html-skills/memory/profile.json` (JSON wins). Used in the dashboard header (greeting + company name).
2. Read `../../shared/design-tokens.css` — copy into the page's `<style>` block.
3. Read `../../shared/components/dashboard.html` — the visual template. Paste its CSS once, then fill in the markup.
4. Read `../../shared/components/confidence-dot.html` — used inline on angle/section recommendations.
5. Locate shared libs the same way the other skills do (`$HTML_SKILLS_LIB`, then `~/.claude/skills/html-skills/shared/lib/`, etc.).

## Step 1: Run the Learn Loop (cheap, automatic)

Consolidation is no-op if patterns.json is < 7 days old. We force a fresh consolidation here ONLY because the dashboard is the canonical "see the latest" surface — users expect freshness when they explicitly look:

```bash
. "${HTML_SKILLS_LIB}/log.sh"
. "${HTML_SKILLS_LIB}/memory.sh"
. "${HTML_SKILLS_LIB}/outcomes.sh"
. "${HTML_SKILLS_LIB}/patterns.sh"
. "${HTML_SKILLS_LIB}/voice.sh"
memory::init
patterns::consolidate >/dev/null 2>&1 || true
voice::consolidate    >/dev/null 2>&1 || true
```

If consolidation fails (jq/python3 missing, empty memory, whatever) — render the dashboard anyway with whatever data is on disk. Show the failure in the "Learn-loop status" panel rather than aborting.

The dashboard surfaces a small "Voice" card showing `voice::tone_summary` — a one-line snapshot like *"11w/sent · 32w DMs · 8w heros · em-dashes, lowercase sentence-starts"* — so the user can see at a glance what the system has learned about their writing style. Empty string = no voice data yet, which is normal for the first few outreaches.

## Step 2: Gather the Numbers

All of the following are JSON queries against files in `~/.cache/html-skills/memory/`. The skill emits them as shell variables for the template step.

### KPI cards (top of dashboard)

```bash
cache="$(memory::root)"

# Targets we've ever researched.
targets_total="$(find "$cache/memory/targets" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"

# Runs in last 30 days.
runs_30d="$(python3 - <<PY
import os, glob, json, datetime as dt
root = "$cache/memory/runs"
cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)
n = 0
for p in glob.glob(os.path.join(root, "*.json")):
    try:
        t = json.load(open(p)).get("started_at","")
        if not t: continue
        if dt.datetime.fromisoformat(t.replace("Z","+00:00")) >= cutoff:
            n += 1
    except Exception:
        pass
print(n)
PY
)"

# Outreaches with each outcome across all targets.
outcomes_summary="$(python3 - <<PY
import os, glob, json
root = "$cache/memory/targets"
acc = {"replied":0, "no_reply":0, "meeting_booked":0, "pending":0, "cold":0}
for p in glob.glob(os.path.join(root, "*.json")):
    try:
        for o in json.load(open(p)).get("past_outreach", []) or []:
            k = o.get("outcome","pending")
            acc[k] = acc.get(k, 0) + 1
    except Exception:
        pass
import json as J
print(J.dumps(acc))
PY
)"

# Decided reply rate.
reply_rate="$(printf '%s' "$outcomes_summary" | python3 -c '
import sys, json
d = json.load(sys.stdin)
decided = d.get("replied",0) + d.get("no_reply",0) + d.get("meeting_booked",0)
if decided == 0:
    print("—")
else:
    pct = (d.get("replied",0) + d.get("meeting_booked",0)) / decided * 100
    print(f"{pct:.0f}%")
')"
```

### Top angles (from patterns.json)

```bash
top_angles="$(jq -r '
  .rules // []
  | map(select(.kind == "cluster_angle" and .confidence != "insufficient"))
  | sort_by(-(.reply_rate // 0), -.evidence_runs)
  | .[0:5]
  | .[]
  | "\(.cluster // "any")|\(.angle)|\(.evidence_runs)|\((.reply_rate // 0) * 100 | floor)|\(.confidence)"
' "$cache/memory/patterns.json" 2>/dev/null)"
```

Render each as a row: cluster · angle · evidence count · reply rate · confidence dot.

### Section recommendations

```bash
section_recs="$(jq -r '
  .rules // []
  | map(select(.kind == "section_survival"))
  | sort_by(.survival_rate)
  | .[]
  | "\(.section)|\(.survival_rate * 100 | floor)|\(.recommendation)|\(.confidence)"
' "$cache/memory/patterns.json" 2>/dev/null)"
```

### Pending follow-ups (the action list)

```bash
pending="$(outcomes::pending_replies 24)"
pending_count="$(printf '%s\n' "$pending" | grep -c '^{' || echo 0)"
```

Each pending line is one JSON object — render as a row: target name · hours old · angle · "ask?" button (no JS — just a `mailto:` or copy-DM placeholder).

### Drift alerts

```bash
drift_alerts="$(jq -c '.drift_alerts // []' "$cache/memory/patterns.json" 2>/dev/null || echo '[]')"
drift_count="$(printf '%s' "$drift_alerts" | jq 'length')"
```

If > 0, render the panel — angle/section name, previous → current rate, direction.

### Recent targets

Last 5 researched, by `last_researched`:

```bash
recent_targets="$(python3 - <<PY
import os, glob, json
root = "$cache/memory/targets"
items = []
for p in glob.glob(os.path.join(root, "*.json")):
    try:
        t = json.load(open(p))
        if t.get("last_researched"):
            items.append((t["last_researched"], t.get("slug"), t.get("name")))
    except Exception:
        pass
items.sort(reverse=True)
for ts, slug, name in items[:5]:
    print(f"{slug}|{name}|{ts}")
PY
)"
```

### Learn-loop status

```bash
last_consolidated="$(jq -r '.last_consolidated // "never"' "$cache/memory/patterns.json" 2>/dev/null)"
runs_analyzed="$(jq -r '.runs_analyzed // 0' "$cache/memory/patterns.json" 2>/dev/null)"
rules_total="$(jq -r '.rules | length' "$cache/memory/patterns.json" 2>/dev/null || echo 0)"
```

Render: "last consolidated · N runs analyzed · K rules · [link to `patterns.sh report`]".

## Step 3: Render the HTML

Use `shared/components/dashboard.html` as the structural template. It already defines:
- Header with company name + greeting + generated date
- 4 KPI cards (targets, 30d runs, reply rate, decided outreaches)
- Top angles table
- Pending follow-ups list
- Drift alerts panel (conditional — only render if drift_count > 0)
- Recent targets list
- Learn-loop status footer

Replace the placeholder tokens (`{{TARGETS_TOTAL}}`, `{{TOP_ANGLES_ROWS}}`, etc.) with the values from Step 2. For repeated rows, generate the markup once per row from the pipe-delimited variables.

**Empty-state design**: every section that has no data renders an empty-state row, NOT nothing. The user should always be able to tell why a section is empty:
- No top angles → *"Not enough data yet. Run a couple of outreaches and re-open the dashboard."*
- No pending follow-ups → *"All caught up — no outreaches waiting on a reply."*
- No drift alerts → omit the panel entirely.
- No recent targets → *"No targets researched yet. Try: 'research stripe.com'"*

## Step 4: Save and Open

```bash
ts="$(date -u +%Y-%m-%d)"
out="$(pwd)/dashboard-${ts}.html"
# write the HTML to "$out" ...
case "$(uname -s)" in
  Darwin) open "$out" >/dev/null 2>&1 || true ;;
  Linux)  xdg-open "$out" >/dev/null 2>&1 || true ;;
esac
```

Hand-back message: 2 lines max. URL of the file + one-line summary of the most actionable item:

> *"✓ Dashboard saved to ./dashboard-2026-05-17.html (opened in your browser).*
> *Heads up — 3 outreaches waiting > 48h on a reply. Top of the list: John @ Acme (SDR-hiring, 4 days)."*

If there are drift alerts, surface the most severe one as a second line.

## Step 5: NO run logging

The dashboard skill doesn't update any memory state. It's read-only by design — running it shouldn't pollute the run record or patterns. Skip `memory::quick_run` and friends here.

## Common Mistakes to Avoid

1. **Inventing trends.** If there's no data, say so. Don't extrapolate from 2 runs.
2. **Putting the user in a graph-reading mindset.** This is a coach's dashboard, not a Datadog. Lead with what to DO next (pending follow-ups, drift caveats), not what looks pretty.
3. **Running consolidation in a tight loop.** It's already auto-consolidate behavior — the explicit consolidate at Step 1 is the once-per-dashboard-render cost; don't loop.
4. **Embedding the LLM's narrative voice in the page.** The page is data + design. Voice goes in the hand-back message only.
5. **Auto-deploying to Vercel.** Dashboard stays local by default — it lists every target you've ever researched, including ones you haven't shipped yet. Not safe to publish.

---

## User Preferences (Auto-Updated)

<!--
  Rewritten on successful run. Max 20 lines.
-->

- Time window for KPI cards: 30 days (default)
- Open in browser after generation: yes (default)
- Show empty-state guidance: yes (default)
- Last updated: [never]

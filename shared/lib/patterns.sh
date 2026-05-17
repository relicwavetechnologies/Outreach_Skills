#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / patterns.sh
#  Consolidation pass — turns raw runs[] + outcomes[] + targets[] into
#  distilled, decision-grade rules at:
#    ~/.cache/html-skills/memory/patterns.json
#
#  This is the layer that makes the system COACH instead of GENERATE.
#  Skills consult patterns.json at decision points:
#    - mailmerge-html → angle selection per cluster (or per angle when no
#                       cluster is tagged on the runs)
#    - outreach-html / research-html → which insight sections to generate
#                                       by default
#
#  Source it:  . "$HTML_SKILLS_LIB/patterns.sh"
#
#  Public functions:
#    patterns::consolidate           # rebuild patterns.json from raw memory
#    patterns::auto_consolidate      # cheap no-op if patterns.json is fresh
#                                    # (default freshness = 7 days)
#    patterns::report [days]         # human-readable rollup printed to stdout
#    patterns::drift                 # show drift alerts since previous run
#    patterns::reset                 # wipe patterns.json (history preserved)
#    patterns::angle_for_cluster <cluster> [fallback]
#                                    # echo best angle for that cluster, or
#                                    # echo $fallback / empty if no evidence
#    patterns::section_recommendation <section>
#                                    # echo: always | usually | rarely | skip
#                                    # rules of thumb based on survival rate
#
#  CLI: bash patterns.sh <command> ...    (same set of commands)
# ──────────────────────────────────────────────────────────────────────────

if [ -n "${__HTML_SKILLS_PATTERNS_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_PATTERNS_LOADED=1

if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HTML_SKILLS_LIB
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/memory.sh"

memory::init

patterns::__file()         { printf "%s\n" "$(memory::root)/memory/patterns.json"; }
patterns::__previous_file() { printf "%s\n" "$(memory::root)/memory/patterns.previous.json"; }

# Confidence buckets by evidence count.
#   2-4   → low
#   5-9   → medium
#   10+   → high
patterns::__confidence_for() {
  local n="${1:?count required}"
  if   [ "$n" -ge 10 ]; then echo "high"
  elif [ "$n" -ge 5  ]; then echo "medium"
  elif [ "$n" -ge 2  ]; then echo "low"
  else                       echo "insufficient"; fi
}

# ─────────────────────────────────────────────────────────────────────────
#  Consolidate
#  Reads:  memory/runs/*.json  memory/outcomes/feedback.jsonl  memory/targets/*.json
#  Writes: memory/patterns.json  (and rotates previous to patterns.previous.json)
# ─────────────────────────────────────────────────────────────────────────
patterns::consolidate() {
  command -v python3 >/dev/null 2>&1 || { log::fail "python3 required"; return 10; }
  command -v jq      >/dev/null 2>&1 || { log::fail "jq required";      return 10; }

  local root pf prev
  root="$(memory::root)"
  pf="$(patterns::__file)"
  prev="$(patterns::__previous_file)"

  # Rotate current → previous for drift detection.
  if [ -f "$pf" ]; then
    cp "$pf" "$prev"
  fi

  log::info "Consolidating runs + outcomes + targets …"
  local out
  out="$(python3 - "$root" <<'PY'
import json, os, sys, glob, datetime as dt
root = sys.argv[1]
runs_dir     = os.path.join(root, "memory", "runs")
targets_dir  = os.path.join(root, "memory", "targets")
feedback_jsl = os.path.join(root, "memory", "outcomes", "feedback.jsonl")

def safe_load(path):
    try:
        with open(path, encoding="utf-8") as f: return json.load(f)
    except Exception:
        return None

# 1) Load all runs.
runs = []
for p in glob.glob(os.path.join(runs_dir, "*.json")):
    r = safe_load(p)
    if isinstance(r, dict): runs.append(r)

# 2) Load all targets — index past_outreach by run_id for fast outcome lookup.
outcome_by_run = {}
for p in glob.glob(os.path.join(targets_dir, "*.json")):
    t = safe_load(p)
    if not isinstance(t, dict): continue
    for o in (t.get("past_outreach") or []):
        rid = o.get("run_id")
        if rid: outcome_by_run[rid] = {
            "outcome": o.get("outcome", "pending"),
            "slug":    t.get("slug"),
            "angle":   o.get("angle"),
            "at":      o.get("at"),
        }

# 3) Load feedback events grouped by run_id for engagement metrics.
events_by_run = {}
if os.path.exists(feedback_jsl):
    with open(feedback_jsl, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: e = json.loads(line)
            except Exception: continue
            rid = e.get("run_id")
            if not rid: continue
            events_by_run.setdefault(rid, []).append(e)

# 4) Per-run join.
joined = []
for r in runs:
    rid = r.get("run_id")
    oc  = outcome_by_run.get(rid, {}) if rid else {}
    ev  = events_by_run.get(rid, []) if rid else []
    # Engagement summary from feedback events:
    has_view    = any(e.get("event") == "page_view" for e in ev)
    max_scroll  = 0
    for e in ev:
        ev_name = e.get("event", "")
        if ev_name.startswith("scroll_"):
            try: max_scroll = max(max_scroll, int(ev_name.split("_", 1)[1]))
            except Exception: pass
    cta_clicked = any(e.get("event") == "cta_click" for e in ev)
    joined.append({
        "run_id":            rid,
        "skill":             r.get("skill"),
        "target_slug":       r.get("target_slug") or oc.get("slug"),
        "angle":             r.get("angle") or oc.get("angle"),
        "cluster":           r.get("cluster"),  # optional; only present when mailmerge wrote it
        "draft_sections":    r.get("draft_sections")    or [],
        "shipped_sections":  r.get("shipped_sections")  or [],
        "outcome":           oc.get("outcome", "pending"),
        "has_view":          has_view,
        "max_scroll":        max_scroll,
        "cta_clicked":       cta_clicked,
        "started_at":        r.get("started_at"),
    })

# 5) Rule synthesis.
rules = []

def conf(n):
    if n >= 10: return "high"
    if n >= 5:  return "medium"
    if n >= 2:  return "low"
    return "insufficient"

# 5a) angle effectiveness — group by (cluster, angle); fall back to angle-only.
from collections import defaultdict
ang_keys = defaultdict(list)
for j in joined:
    angle = j.get("angle")
    if not angle: continue
    cluster = j.get("cluster") or "_any"
    ang_keys[(cluster, angle)].append(j)

for (cluster, angle), items in ang_keys.items():
    n = len(items)
    if n < 2: continue
    replied  = sum(1 for x in items if x["outcome"] == "replied")
    no_reply = sum(1 for x in items if x["outcome"] == "no_reply")
    meeting  = sum(1 for x in items if x["outcome"] == "meeting_booked")
    pending  = sum(1 for x in items if x["outcome"] == "pending")
    decided  = replied + no_reply + meeting
    rate = (replied + meeting) / decided if decided > 0 else None
    rules.append({
        "id":            f"angle:{cluster}:{angle}",
        "kind":          "cluster_angle",
        "cluster":       None if cluster == "_any" else cluster,
        "angle":         angle,
        "evidence_runs": n,
        "decided":       decided,
        "outcomes":      {"replied": replied, "no_reply": no_reply,
                          "meeting_booked": meeting, "pending": pending},
        "reply_rate":    rate,
        "confidence":    conf(n),
    })

# 5b) section survival — for runs that recorded draft + shipped sections,
# compute how often each draft section made it into the shipped page.
sec_keys = defaultdict(lambda: {"drafted": 0, "shipped": 0})
for j in joined:
    draft = set(j.get("draft_sections") or [])
    ship  = set(j.get("shipped_sections") or [])
    for s in draft:
        sec_keys[s]["drafted"] += 1
        if s in ship: sec_keys[s]["shipped"] += 1

for sec, counts in sec_keys.items():
    n = counts["drafted"]
    if n < 2: continue
    rate = counts["shipped"] / n
    if   rate >= 0.85: rec = "always"
    elif rate >= 0.50: rec = "usually"
    elif rate >= 0.20: rec = "rarely"
    else:              rec = "skip"
    rules.append({
        "id":            f"section:{sec}",
        "kind":          "section_survival",
        "section":       sec,
        "evidence_runs": n,
        "drafted":       counts["drafted"],
        "shipped":       counts["shipped"],
        "survival_rate": rate,
        "recommendation": rec,
        "confidence":    conf(n),
    })

# 5c) engagement: reply-rate when section is present vs absent.
# Only emit for sections with sufficient evidence on both sides.
for sec in sec_keys:
    with_sec    = [j for j in joined if sec in (j.get("shipped_sections") or [])]
    without_sec = [j for j in joined if sec not in (j.get("shipped_sections") or [])]
    def decided_reply_rate(items):
        decided = [x for x in items if x["outcome"] in ("replied","no_reply","meeting_booked")]
        if len(decided) < 2: return None, len(decided)
        wins = sum(1 for x in decided if x["outcome"] in ("replied","meeting_booked"))
        return wins / len(decided), len(decided)
    r_with,  n_with  = decided_reply_rate(with_sec)
    r_wout,  n_wout  = decided_reply_rate(without_sec)
    if r_with is None or r_wout is None: continue
    delta = r_with - r_wout
    # Only flag meaningful effects.
    if abs(delta) < 0.10: continue
    rules.append({
        "id":            f"engagement:{sec}",
        "kind":          "section_engagement",
        "section":       sec,
        "reply_rate_with":    r_with,
        "reply_rate_without": r_wout,
        "delta":         delta,
        "n_with":        n_with,
        "n_without":     n_wout,
        "confidence":    conf(min(n_with, n_wout)),
    })

# Sort rules by kind then confidence then evidence.
order = {"cluster_angle": 0, "section_survival": 1, "section_engagement": 2}
conf_order = {"high": 0, "medium": 1, "low": 2, "insufficient": 3}
rules.sort(key=lambda r: (order.get(r["kind"], 99), conf_order.get(r.get("confidence","low"), 99), -r.get("evidence_runs", r.get("n_with", 0))))

result = {
    "version":          1,
    "last_consolidated": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "runs_analyzed":    len(joined),
    "decided_outreaches": sum(1 for j in joined if j["outcome"] in ("replied","no_reply","meeting_booked")),
    "rules":            rules,
    "drift_alerts":     []   # filled in by patterns::drift after this writes
}

print(json.dumps(result, indent=2, ensure_ascii=False))
PY
  )" || { log::fail "consolidation failed"; return 1; }

  # Atomic write.
  local tmp="${pf}.tmp.$$"
  printf "%s" "$out" > "$tmp" && mv "$tmp" "$pf"

  local n; n="$(jq '.runs_analyzed' "$pf")"
  local r; r="$(jq '.rules | length' "$pf")"
  log::ok "Consolidated ${n} run(s) into ${r} rule(s)"

  # Compute drift on top of the fresh patterns.
  patterns::drift --silent || true
}

# Run consolidate only if patterns.json is missing or older than $1 days (default 7).
patterns::auto_consolidate() {
  local stale_days="${1:-7}"
  local pf; pf="$(patterns::__file)"
  if [ ! -f "$pf" ]; then
    patterns::consolidate
    return $?
  fi
  if ! command -v jq >/dev/null 2>&1; then return 0; fi
  local last; last="$(jq -r '.last_consolidated // empty' "$pf")"
  if [ -z "$last" ]; then patterns::consolidate; return $?; fi
  # Compare via python3 — date math in pure bash is unportable.
  local fresh
  fresh="$(python3 - "$last" "$stale_days" <<'PY'
import sys, datetime as dt
last = dt.datetime.strptime(sys.argv[1].replace("Z",""), "%Y-%m-%dT%H:%M:%S").replace(tzinfo=dt.timezone.utc)
days = int(sys.argv[2])
delta = dt.datetime.now(dt.timezone.utc) - last
print("yes" if delta.days < days else "no")
PY
)"
  if [ "$fresh" = "no" ]; then
    patterns::consolidate
  fi
}

# ─────────────────────────────────────────────────────────────────────────
#  Drift
#  Compare current patterns to patterns.previous.json (rotated at consolidate)
#  Emit alerts when an angle's reply_rate dropped > 0.30 absolute or a
#  section's survival_rate moved by > 0.30. Writes alerts back into
#  patterns.json's drift_alerts[] AND echoes them.
# ─────────────────────────────────────────────────────────────────────────
patterns::drift() {
  local silent=0
  if [ "${1:-}" = "--silent" ]; then silent=1; fi
  command -v python3 >/dev/null 2>&1 || return 0
  command -v jq      >/dev/null 2>&1 || return 0

  local pf prev
  pf="$(patterns::__file)"
  prev="$(patterns::__previous_file)"
  if [ ! -f "$pf" ];  then return 0; fi
  if [ ! -f "$prev" ]; then
    # No previous = no drift possible.
    return 0
  fi

  local alerts
  alerts="$(python3 - "$pf" "$prev" <<'PY'
import json, sys
def idx(rules):
    return {r["id"]: r for r in (rules or [])}
new = json.load(open(sys.argv[1])); old = json.load(open(sys.argv[2]))
new_rules = idx(new.get("rules"));  old_rules = idx(old.get("rules"))
alerts = []
for rid, nr in new_rules.items():
    orr = old_rules.get(rid)
    if not orr: continue
    if nr["kind"] == "cluster_angle":
        a = nr.get("reply_rate"); b = orr.get("reply_rate")
        if a is None or b is None: continue
        delta = a - b
        if abs(delta) >= 0.30:
            alerts.append({
                "kind": "angle_drift", "rule_id": rid,
                "angle": nr.get("angle"), "cluster": nr.get("cluster"),
                "previous_reply_rate": b, "current_reply_rate": a,
                "delta": delta,
                "direction": "down" if delta < 0 else "up"
            })
    if nr["kind"] == "section_survival":
        a = nr.get("survival_rate"); b = orr.get("survival_rate")
        if a is None or b is None: continue
        delta = a - b
        if abs(delta) >= 0.30:
            alerts.append({
                "kind": "section_drift", "rule_id": rid,
                "section": nr.get("section"),
                "previous_survival_rate": b, "current_survival_rate": a,
                "delta": delta,
                "direction": "down" if delta < 0 else "up"
            })
print(json.dumps(alerts, ensure_ascii=False))
PY
  )"

  # Write back into patterns.json.
  local tmp="${pf}.tmp.$$"
  jq --argjson a "$alerts" '.drift_alerts = $a' "$pf" > "$tmp" && mv "$tmp" "$pf"

  if [ "$silent" = "0" ]; then
    local n; n="$(printf "%s" "$alerts" | jq 'length')"
    if [ "$n" = "0" ]; then
      log::ok "No drift detected (vs. previous consolidation)."
    else
      log::warn "${n} drift alert(s):"
      printf "%s\n" "$alerts" | jq -r '.[] |
        if .kind == "angle_drift" then
          "  · angle \"\(.angle)\" reply rate \(.previous_reply_rate * 100 | floor)% → \(.current_reply_rate * 100 | floor)% (\(.direction))"
        else
          "  · section \"\(.section)\" survival \(.previous_survival_rate * 100 | floor)% → \(.current_survival_rate * 100 | floor)% (\(.direction))"
        end'
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────
#  Report — human-readable rollup
# ─────────────────────────────────────────────────────────────────────────
patterns::report() {
  command -v jq >/dev/null 2>&1 || return 0
  local pf; pf="$(patterns::__file)"
  if [ ! -f "$pf" ]; then
    log::warn "No patterns yet. Run: patterns.sh consolidate"
    return 0
  fi

  log::title "patterns report"
  log::dim "last consolidated: $(jq -r '.last_consolidated' "$pf")"
  log::dim "runs analyzed:     $(jq -r '.runs_analyzed'    "$pf")"
  log::dim "decided outreaches:$(jq -r '.decided_outreaches' "$pf")"
  echo

  # Angles
  printf "  %s\n" "Angles (by cluster):"
  jq -r '.rules
        | map(select(.kind == "cluster_angle"))
        | sort_by(-(.reply_rate // 0))
        | .[]
        | "    · \(.cluster // "any") / \(.angle) — \(.evidence_runs) runs, reply \( ( (.reply_rate // 0) * 100) | floor )% [\(.confidence)]"' "$pf"
  echo

  # Sections
  printf "  %s\n" "Section survival:"
  jq -r '.rules
        | map(select(.kind == "section_survival"))
        | sort_by(.survival_rate)
        | .[]
        | "    · \(.section) — \(.shipped)/\(.drafted) kept (\(((.survival_rate // 0) * 100) | floor)%) → \(.recommendation) [\(.confidence)]"' "$pf"
  echo

  # Engagement (delta)
  printf "  %s\n" "Section engagement (reply-rate delta):"
  jq -r '.rules
        | map(select(.kind == "section_engagement"))
        | sort_by(-(.delta))
        | .[]
        | "    · \(.section) — with: \( ((.reply_rate_with // 0)    * 100) | floor )%  vs without: \( ((.reply_rate_without // 0) * 100) | floor )%  Δ \( ((.delta // 0) * 100) | floor )pp [\(.confidence)]"' "$pf"
  echo

  # Drift
  local drift_count; drift_count="$(jq '.drift_alerts | length' "$pf")"
  if [ "$drift_count" != "0" ]; then
    printf "  %s (%s)\n" "Drift alerts since last consolidation:" "$drift_count"
    jq -r '.drift_alerts[] |
      if .kind == "angle_drift" then
        "    · angle \"\(.angle)\" reply \( ( (.previous_reply_rate // 0) * 100) | floor )% → \( ( (.current_reply_rate // 0) * 100) | floor )%"
      else
        "    · section \"\(.section)\" survival \( ( (.previous_survival_rate // 0) * 100) | floor )% → \( ( (.current_survival_rate // 0) * 100) | floor )%"
      end' "$pf"
  fi
}

# ─────────────────────────────────────────────────────────────────────────
#  Reset (patterns.json only — preserves history)
# ─────────────────────────────────────────────────────────────────────────
patterns::reset() {
  rm -f "$(patterns::__file)"
  log::ok "patterns.json removed. Run patterns.sh consolidate to rebuild."
}

# ─────────────────────────────────────────────────────────────────────────
#  Lookups — used by skills at decision points
# ─────────────────────────────────────────────────────────────────────────

# patterns::angle_for_cluster <cluster> [fallback]
# Echo the best (highest reply_rate, breaks ties on evidence) angle for the
# cluster. If no rule for that cluster, falls back to the best angle in
# the catch-all (_any). If still nothing, echoes $fallback (or empty).
patterns::angle_for_cluster() {
  local cluster="${1:?cluster required}"
  local fallback="${2:-}"
  command -v jq >/dev/null 2>&1 || { printf "%s" "$fallback"; return 0; }
  local pf; pf="$(patterns::__file)"
  if [ ! -f "$pf" ]; then printf "%s" "$fallback"; return 0; fi

  local picked
  picked="$(jq -r --arg c "$cluster" '
    [
      .rules[]?
      | select(.kind == "cluster_angle")
      | select(.cluster == $c or (.cluster == null and $c == "any"))
      | select(.confidence != "insufficient")
    ]
    | sort_by([-(.reply_rate // 0), -.evidence_runs])
    | (.[0].angle // empty)
  ' "$pf" 2>/dev/null)"

  if [ -z "$picked" ]; then
    # Fall back to the overall best.
    picked="$(jq -r '
      [ .rules[]? | select(.kind == "cluster_angle") | select(.confidence != "insufficient") ]
      | sort_by([-(.reply_rate // 0), -.evidence_runs])
      | (.[0].angle // empty)
    ' "$pf" 2>/dev/null)"
  fi

  printf "%s" "${picked:-$fallback}"
}

# patterns::section_recommendation <section>
# Echo one of: always | usually | rarely | skip | unknown
patterns::section_recommendation() {
  local section="${1:?section required}"
  command -v jq >/dev/null 2>&1 || { printf "unknown"; return 0; }
  local pf; pf="$(patterns::__file)"
  if [ ! -f "$pf" ]; then printf "unknown"; return 0; fi
  jq -r --arg s "$section" '
    [ .rules[]? | select(.kind == "section_survival" and .section == $s) ][0]
    | (.recommendation // "unknown")
  ' "$pf" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────
#  CLI entrypoint
# ─────────────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-help}" in
    consolidate)            shift; patterns::consolidate "$@" ;;
    auto-consolidate)       shift; patterns::auto_consolidate "$@" ;;
    report)                 shift; patterns::report "$@" ;;
    drift)                  shift; patterns::drift "$@" ;;
    reset)                  shift; patterns::reset "$@" ;;
    angle-for-cluster)      shift; patterns::angle_for_cluster "$@" ;;
    section-recommendation) shift; patterns::section_recommendation "$@" ;;
    -h|--help|help|*)
      sed -n '2,55p' "${BASH_SOURCE[0]}"
      ;;
  esac
fi

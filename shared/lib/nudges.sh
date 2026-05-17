#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / nudges.sh
#  Proactive prompts a skill should consider at startup BEFORE asking the
#  user what they want. The system is now collecting outcomes + patterns;
#  this lib turns that into one or two short attention-pointers.
#
#  Source it:  . "$HTML_SKILLS_LIB/nudges.sh"
#
#  Three nudge kinds, all derived from existing memory:
#    pending_replies — past_outreach[] entries > 24h old still pending
#    drift_alerts    — patterns.json.drift_alerts[] (down-direction esp.)
#    stale_consolidation — patterns.json hasn't been refreshed in > 14d
#
#  Public functions:
#    nudges::collect [pending_hours] [stale_days]
#       Print all relevant nudges as plain-language lines to stdout.
#       Empty output → no nudges.
#    nudges::collect_json [pending_hours] [stale_days]
#       Same data, JSON array form for skills that want to render
#       structured. Each entry: {kind, text, severity, payload}.
#    nudges::count [pending_hours] [stale_days]
#       Just the count. Useful for "do I have anything to say?" checks.
#
#  Severity levels (low/medium/high) map roughly to: informational /
#  worth-mentioning / should-block-on. Skills can decide how loud to be.
# ──────────────────────────────────────────────────────────────────────────

if [ -n "${__HTML_SKILLS_NUDGES_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_NUDGES_LOADED=1

if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HTML_SKILLS_LIB
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/memory.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/outcomes.sh"
# Patterns is optional — patterns.json may not exist yet.
if [ -f "${HTML_SKILLS_LIB}/patterns.sh" ]; then
  # shellcheck source=/dev/null
  . "${HTML_SKILLS_LIB}/patterns.sh"
fi

memory::init

# Collect as JSON: one object per nudge.
# kind:    pending_reply | drift_down | drift_up | stale_consolidation
# text:    plain-language one-line phrasing
# severity: low | medium | high
# payload: kind-specific structured fields
nudges::collect_json() {
  local pending_hours="${1:-24}"
  local stale_days="${2:-14}"
  command -v jq >/dev/null 2>&1 || { echo '[]'; return 0; }

  local cache out
  cache="$(memory::root)"
  out='[]'

  # ── 1. Pending replies ───────────────────────────────────────────────
  local pending_json
  pending_json="$(outcomes::pending_replies "$pending_hours" 2>/dev/null | jq -s '.' 2>/dev/null)"
  if [ -n "$pending_json" ] && [ "$pending_json" != "[]" ] && [ "$pending_json" != "null" ]; then
    local count
    count="$(printf "%s" "$pending_json" | jq 'length')"
    # Severity scales with count: 1-2 = low, 3-6 = medium, 7+ = high.
    local sev="low"
    [ "$count" -ge 3 ] && sev="medium"
    [ "$count" -ge 7 ] && sev="high"

    local top
    top="$(printf "%s" "$pending_json" | jq -r '.[0] | "\(.target_name // .slug) (\(.angle), \(.hours_old)h ago)"')"
    local text
    if [ "$count" = "1" ]; then
      text="1 outreach waiting on a reply > ${pending_hours}h — ${top}."
    else
      text="${count} outreaches waiting > ${pending_hours}h — top: ${top}."
    fi

    out="$(jq -nc \
      --argjson list "$out" \
      --arg text "$text" \
      --arg sev "$sev" \
      --argjson count "$count" \
      --argjson items "$pending_json" \
      '$list + [{kind:"pending_reply", text:$text, severity:$sev, payload:{count:$count, items:$items}}]')"
  fi

  # ── 2. Drift alerts (from patterns.json if present) ──────────────────
  local pf="${cache}/memory/patterns.json"
  if [ -f "$pf" ]; then
    local drift_count
    drift_count="$(jq '.drift_alerts | length' "$pf" 2>/dev/null || echo 0)"
    if [ "$drift_count" -gt 0 ] 2>/dev/null; then
      # Surface up to 2 drift alerts as their own nudges.
      local first_two_json
      first_two_json="$(jq -c '[.drift_alerts[]?][0:2]' "$pf")"
      printf "%s" "$first_two_json" | jq -c '.[]' | while IFS= read -r alert; do
        local kind direction sev text
        kind="$(printf "%s" "$alert" | jq -r '.kind')"
        direction="$(printf "%s" "$alert" | jq -r '.direction')"
        # Down direction is the actionable case; up is informational.
        if [ "$direction" = "down" ]; then sev="medium"; else sev="low"; fi
        if [ "$kind" = "angle_drift" ]; then
          text="$(printf "%s" "$alert" | jq -r '"angle \"" + .angle + "\" reply rate \( (.previous_reply_rate * 100 | floor) )% → \( (.current_reply_rate * 100 | floor) )% (" + .direction + ")"')"
        else
          text="$(printf "%s" "$alert" | jq -r '"section \"" + .section + "\" survival \( (.previous_survival_rate * 100 | floor) )% → \( (.current_survival_rate * 100 | floor) )% (" + .direction + ")"')"
        fi
        printf '%s\n' "$(jq -nc \
          --arg k "drift_${direction}" --arg t "$text" --arg s "$sev" \
          --argjson p "$alert" \
          '{kind:$k, text:$t, severity:$s, payload:$p}')"
      done | jq -s '.' | jq -c --argjson list "$out" '$list + .' > /tmp/htmlskills.nudges.$$
      # Merge in
      out="$(cat /tmp/htmlskills.nudges.$$)"
      rm -f /tmp/htmlskills.nudges.$$
    fi
  fi

  # ── 3. Stale consolidation ───────────────────────────────────────────
  if [ -f "$pf" ] && command -v python3 >/dev/null 2>&1; then
    local last_consol
    last_consol="$(jq -r '.last_consolidated // empty' "$pf")"
    if [ -n "$last_consol" ]; then
      local stale
      stale="$(python3 - "$last_consol" "$stale_days" <<'PY'
import sys, datetime as dt
last = dt.datetime.strptime(sys.argv[1].replace("Z",""), "%Y-%m-%dT%H:%M:%S").replace(tzinfo=dt.timezone.utc)
days = int(sys.argv[2])
delta = dt.datetime.now(dt.timezone.utc) - last
print("yes" if delta.days >= days else "no")
PY
)"
      if [ "$stale" = "yes" ]; then
        out="$(jq -nc \
          --argjson list "$out" \
          --arg t "patterns.json is older than ${stale_days} days — consider running patterns.sh consolidate for fresher recommendations." \
          '$list + [{kind:"stale_consolidation", text:$t, severity:"low", payload:{}}]')"
      fi
    fi
  fi

  # ── 4. Stale voice consolidation ─────────────────────────────────────
  local vf="${cache}/memory/voice.json"
  if [ -f "$vf" ] && command -v python3 >/dev/null 2>&1; then
    local v_content; v_content="$(cat "$vf" 2>/dev/null)"
    if [ "$v_content" != "{}" ] && [ -n "$v_content" ]; then
      local v_last
      v_last="$(jq -r '.last_consolidated // empty' "$vf" 2>/dev/null)"
      if [ -n "$v_last" ]; then
        local v_stale
        v_stale="$(python3 -c "
import sys, datetime as dt
last = dt.datetime.strptime(sys.argv[1].replace('Z',''), '%Y-%m-%dT%H:%M:%S').replace(tzinfo=dt.timezone.utc)
days = int(sys.argv[2])
delta = dt.datetime.now(dt.timezone.utc) - last
print('yes' if delta.days >= days else 'no')
" "$v_last" "$stale_days")"
        if [ "$v_stale" = "yes" ]; then
          out="$(jq -nc \
            --argjson list "$out" \
            --arg t "voice.json is older than ${stale_days} days — voice.sh consolidate will refresh your learned writing style." \
            '$list + [{kind:"stale_voice", text:$t, severity:"low", payload:{}}]')"
        fi
      fi
    fi
  fi

  printf "%s\n" "$out"
}

# Plain-language collector for skill prose / human eyes.
# One nudge per line. Empty output = no nudges to surface.
nudges::collect() {
  local pending_hours="${1:-24}"
  local stale_days="${2:-14}"
  local json
  json="$(nudges::collect_json "$pending_hours" "$stale_days")"
  if [ -z "$json" ] || [ "$json" = "[]" ]; then
    return 0
  fi
  printf "%s" "$json" | jq -r '.[] | "[\(.severity)] \(.text)"'
}

# Just count — fast path for "do we have anything to say?".
nudges::count() {
  local pending_hours="${1:-24}"
  local stale_days="${2:-14}"
  local json
  json="$(nudges::collect_json "$pending_hours" "$stale_days")"
  printf "%s" "$json" | jq 'length'
}

# CLI for direct shell testing.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-collect}" in
    collect)       shift; nudges::collect       "$@" ;;
    collect-json)  shift; nudges::collect_json  "$@" ;;
    count)         shift; nudges::count         "$@" ;;
    -h|--help|help|*)
      sed -n '2,40p' "${BASH_SOURCE[0]}"
      ;;
  esac
fi

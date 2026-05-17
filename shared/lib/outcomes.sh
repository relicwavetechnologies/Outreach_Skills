#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / outcomes.sh
#  The outcomes signal — what actually happened after we shipped a page.
#
#  Source it:  . "$HTML_SKILLS_LIB/outcomes.sh"
#
#  Two signal sources feed one append-only event log at
#    ~/.cache/html-skills/memory/outcomes/feedback.jsonl
#
#    1) track.js — auto events (page_view, scroll_*, dwell_*, cta_click).
#       Synced from a user-owned Vercel KV via track.sh.
#
#    2) One-tap user feedback — the strongest possible signal.
#       Next time the user opens Claude Code after an outreach, the
#       skill scans pending past_outreach[] entries and asks
#         "Did John reply?  (y / n / not yet)"
#       Two taps. Captures the highest-value outcome.
#
#  Public functions:
#    outcomes::append <json>                # append one event line
#    outcomes::record <kind> <run_id>       # convenience: emit a standard event
#                                            kind: opens|scroll|dwell|cta|reply|meeting
#    outcomes::stats [days]                 # quick rollup of last N days (default 30)
#    outcomes::pending_replies [hours]      # list past_outreach with outcome=pending
#                                            that are at least N hours old (default 24)
#    outcomes::set_outreach_outcome <slug> <run_id> <outcome>
#                                            # update a past_outreach entry's outcome
#                                            # outcome: pending|replied|no_reply|meeting_booked|cold
# ──────────────────────────────────────────────────────────────────────────

if [ -n "${__HTML_SKILLS_OUTCOMES_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_OUTCOMES_LOADED=1

if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HTML_SKILLS_LIB
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/memory.sh"

memory::init

outcomes::__path() {
  printf "%s\n" "$(memory::root)/memory/outcomes/feedback.jsonl"
}

# Append a single JSON event line. Validates it's parseable JSON via jq.
outcomes::append() {
  local json="${1:?json required}"
  if ! command -v jq >/dev/null 2>&1; then
    log::warn "jq not installed — outcomes::append skipped"
    return 1
  fi
  # Validate parseability + compact to one line (defensive).
  local compacted
  if ! compacted="$(printf "%s" "$json" | jq -c '.')" ; then
    log::fail "outcomes::append got invalid JSON"
    return 1
  fi
  local f
  f="$(outcomes::__path)"
  mkdir -p "$(dirname "$f")"
  printf "%s\n" "$compacted" >> "$f"
}

# Convenience: emit a standard event.
#   outcomes::record <kind> <run_id> [extras_json]
#   kind: page_view|scroll|dwell|cta_click|reply|no_reply|meeting_booked|cold
#   extras_json (optional): a JSON object string of extra fields to merge in.
outcomes::record() {
  local kind="${1:?kind required}"
  local rid="${2:?run_id required}"
  # Avoid brace-default-expansion quirks: explicit default.
  local extras="${3:-}"
  if [ -z "$extras" ]; then extras='{}'; fi
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  local merged
  if ! merged="$(jq -nc \
        --arg e "$kind" \
        --arg r "$rid" \
        --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson ex "$extras" \
        '({event:$e, run_id:$r, at:$t}) * $ex')"; then
    log::fail "outcomes::record: jq merge failed (extras was: $extras)"
    return 1
  fi
  outcomes::append "$merged"
}

# Rollup of last <days> days. Prints a small JSON summary on stdout.
outcomes::stats() {
  local days="${1:-30}"
  if ! command -v jq >/dev/null 2>&1; then
    log::warn "jq not installed — outcomes::stats unavailable"
    return 1
  fi
  local f
  f="$(outcomes::__path)"
  if [ ! -s "$f" ]; then
    echo '{"days":'"$days"',"events":0,"breakdown":{}}'
    return 0
  fi
  # Use jq to compute the cutoff and breakdown.
  jq -sR --argjson days "$days" '
    split("\n") | map(select(length>0)) | map(fromjson)
    | (now - ($days * 86400)) as $cutoff
    | map(select((.at | fromdateiso8601) >= $cutoff))
    | {
        days: $days,
        events: length,
        breakdown: (group_by(.event) | map({(.[0].event): length}) | add // {}),
        unique_runs: (map(.run_id) | unique | length),
        # Match the actual event names emitted by outcomes::set_outreach_outcome:
        #   replied | no_reply | meeting_booked | cold
        # (Earlier draft used "reply" — integration test caught the mismatch.)
        replied:   (map(select(.event=="replied"))        | length),
        no_reply:  (map(select(.event=="no_reply"))       | length),
        meetings:  (map(select(.event=="meeting_booked")) | length)
      }
  ' "$f"
}

# List pending past_outreach entries older than N hours.
# Output: one JSON per line: {slug, target_name, run_id, url, angle, hours_old}
outcomes::pending_replies() {
  local hours="${1:-24}"
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  local dir
  dir="$(memory::root)/memory/targets"
  [ -d "$dir" ] || { return 0; }

  local cutoff
  # Cutoff = now - hours*3600 seconds (epoch).
  cutoff=$(( $(date -u +%s) - hours * 3600 ))

  local f
  for f in "$dir"/*.json; do
    [ -e "$f" ] || continue
    jq -c --argjson cutoff "$cutoff" --arg slug "$(basename "$f" .json)" '
      . as $t |
      ($t.name // $slug) as $name |
      ($t.past_outreach // [])
      | map(select(.outcome == "pending"))
      | map(select((.at // "1970-01-01T00:00:00Z" | fromdateiso8601) < $cutoff))
      | map({
          slug: $slug,
          target_name: $name,
          run_id: .run_id,
          url: .url,
          angle: .angle,
          hours_old: (((now - (.at | fromdateiso8601)) / 3600) | floor)
        })
      | .[]
    ' "$f" 2>/dev/null
  done
}

# Mark an outreach entry's outcome. Updates the target file AND appends to feedback.jsonl.
outcomes::set_outreach_outcome() {
  local slug="${1:?slug required}"
  local rid="${2:?run_id required}"
  local outcome="${3:?outcome required}"
  case "$outcome" in
    pending|replied|no_reply|meeting_booked|cold) : ;;
    *) log::fail "Invalid outcome: $outcome (use: pending|replied|no_reply|meeting_booked|cold)"; return 2 ;;
  esac
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  # Verify the target exists.
  local tf
  tf="$(memory::target_path "$slug")"
  if [ ! -f "$tf" ]; then
    log::fail "No target file for $slug"
    return 1
  fi

  local current updated
  current="$(memory::read_target "$slug")"
  updated="$(printf "%s" "$current" | jq --arg r "$rid" --arg o "$outcome" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .past_outreach = ((.past_outreach // []) | map(
      if .run_id == $r then . + {outcome: $o, outcome_at: $t} else . end
    ))
  ')" || return 1
  memory::write_target "$slug" "$updated"

  # Append to outcomes log.
  outcomes::record "$outcome" "$rid" "$(jq -nc --arg s "$slug" '{slug:$s, source:"user_reported"}')"
}

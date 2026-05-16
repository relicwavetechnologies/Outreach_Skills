#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-outcomes.sh — offline tests for shared/lib/outcomes.sh
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
SANDBOX="$(mktemp -d -t htmlskills-out.XXXXXX)"

export HTML_SKILLS_LIB="${LIB}"
export HTML_SKILLS_CACHE="${SANDBOX}"
export NO_COLOR=1

# shellcheck source=/dev/null
. "${LIB}/log.sh"
# shellcheck source=/dev/null
. "${LIB}/memory.sh"
# shellcheck source=/dev/null
. "${LIB}/outcomes.sh"

memory::init

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3 (got '$1')"; else fail "$3 (expected '$2', got '$1')"; fi }

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

FEED="${SANDBOX}/memory/outcomes/feedback.jsonl"
echo
echo "▶ outcomes.sh tests"
echo "  sandbox: ${SANDBOX}"

# ── T1: append + record ──────────────────────────────────────────────────
echo
echo "▶ T1: append + record"
outcomes::append '{"event":"page_view","run_id":"r1","at":"2026-05-17T10:00:00Z"}'
lines="$(wc -l < "$FEED" | tr -d ' ')"
assert_eq "$lines" "1" "T1.1: one line written"

outcomes::record "scroll_50" "r1"
outcomes::record "cta_click" "r1" '{"label":"book a call"}'
lines="$(wc -l < "$FEED" | tr -d ' ')"
assert_eq "$lines" "3" "T1.2: three lines after record x2"

# Validate JSON of last line
last="$(tail -n1 "$FEED")"
assert_eq "$(echo "$last" | jq -r '.event')"  "cta_click"   "T1.3: last event = cta_click"
assert_eq "$(echo "$last" | jq -r '.label')"  "book a call" "T1.4: extras merged"
assert_eq "$(echo "$last" | jq -r '.run_id')" "r1"          "T1.5: run_id preserved"

# ── T2: invalid JSON rejected ────────────────────────────────────────────
echo
echo "▶ T2: invalid JSON rejected"
if outcomes::append "not json at all" 2>/dev/null; then
  fail "T2.1: invalid json should have failed"
else
  pass "T2.1: invalid json rejected"
fi

# ── T3: stats ────────────────────────────────────────────────────────────
echo
echo "▶ T3: stats"
# Add events across runs to test breakdown.
outcomes::record "page_view" "r2"
outcomes::record "reply" "r1" '{"slug":"acme"}'
stats="$(outcomes::stats 30)"
assert_eq "$(echo "$stats" | jq -r '.events')"           "5"  "T3.1: total events"
assert_eq "$(echo "$stats" | jq -r '.unique_runs')"      "2"  "T3.2: unique runs = 2"
assert_eq "$(echo "$stats" | jq -r '.replied')"          "1"  "T3.3: replied = 1"
assert_eq "$(echo "$stats" | jq -r '.breakdown.page_view')" "2" "T3.4: 2 page_views"
assert_eq "$(echo "$stats" | jq -r '.breakdown.scroll_50')" "1" "T3.5: 1 scroll_50"

# Days window: 1-day cutoff should still include all (just added).
short_stats="$(outcomes::stats 1)"
assert_eq "$(echo "$short_stats" | jq -r '.events')" "5" "T3.6: 1-day window includes recent"

# ── T4: pending_replies + set_outreach_outcome ───────────────────────────
echo
echo "▶ T4: pending replies + outcome update"
# Seed a target with a pending outreach 48h ago.
slug="acme"
memory::init_target "$slug" "Acme Corp"

# We need to manually append a past_outreach with at = 48h ago (memory::add_outreach
# uses 'now'; we want a deliberately old entry).
old_ts="$(date -u -v-48H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
TF="$(memory::target_path "$slug")"
updated="$(jq --arg t "$old_ts" '
  .past_outreach = [
    {run_id:"r-old",   url:"https://old.example", angle:"sdr", outcome:"pending", at:$t},
    {run_id:"r-fresh", url:"https://new.example", angle:"hire-growth", outcome:"pending",
     at:(now|todate)}
  ]
' "$TF")"
printf '%s' "$updated" > "$TF"

pending="$(outcomes::pending_replies 24)"
count="$(printf '%s\n' "$pending" | grep -c '^{')"
assert_eq "$count" "1" "T4.1: only old (>24h) outreach flagged"

slug_out="$(printf '%s' "$pending" | jq -r '.slug')"
assert_eq "$slug_out" "$slug" "T4.2: pending lists correct slug"

run_out="$(printf '%s' "$pending" | jq -r '.run_id')"
assert_eq "$run_out" "r-old" "T4.3: pending lists correct run_id"

# Now mark replied. Should:
#   - Update the past_outreach entry's outcome
#   - Append a "replied" event to feedback.jsonl
outcomes::set_outreach_outcome "$slug" "r-old" "replied"
new_outcome="$(jq -r '.past_outreach[] | select(.run_id=="r-old") | .outcome' "$TF")"
assert_eq "$new_outcome" "replied" "T4.4: past_outreach[].outcome updated"
last="$(tail -n1 "$FEED")"
assert_eq "$(echo "$last" | jq -r '.event')"  "replied" "T4.5: replied event appended"
assert_eq "$(echo "$last" | jq -r '.run_id')" "r-old"   "T4.6: replied event has correct run_id"
assert_eq "$(echo "$last" | jq -r '.source')" "user_reported" "T4.7: source=user_reported"

# Pending should now show only the still-pending fresh one (which is < 24h old → filtered out).
pending="$(outcomes::pending_replies 24)"
count="$(printf '%s\n' "$pending" | grep -c '^{' || true)"
assert_eq "$count" "0" "T4.8: no more old-pending after marking replied"

# ── T5: invalid outcome rejected ─────────────────────────────────────────
echo
echo "▶ T5: invalid outcome rejected"
if outcomes::set_outreach_outcome "$slug" "r-fresh" "maybe" 2>/dev/null; then
  fail "T5.1: invalid outcome should fail"
else
  pass "T5.1: invalid outcome rejected"
fi

# ── T6: missing target rejected ──────────────────────────────────────────
echo
echo "▶ T6: missing target rejected"
if outcomes::set_outreach_outcome "no-such-slug" "r-x" "replied" 2>/dev/null; then
  fail "T6.1: missing target should fail"
else
  pass "T6.1: missing target rejected"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo; echo "  failed:"; for t in "${FAILED[@]}"; do echo "    - $t"; done
  echo; echo "  sandbox: $SANDBOX"
  exit 1
fi
echo "─────────────────────────────────────────────"
rm -rf "$SANDBOX"

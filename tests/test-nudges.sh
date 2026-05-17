#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-nudges.sh — offline tests for shared/lib/nudges.sh
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
SANDBOX="$(mktemp -d -t htmlskills-nud.XXXXXX)"

export HTML_SKILLS_LIB="${LIB}"
export HTML_SKILLS_CACHE="${SANDBOX}"
export NO_COLOR=1

# shellcheck source=/dev/null
. "${LIB}/log.sh"
# shellcheck source=/dev/null
. "${LIB}/memory.sh"
# shellcheck source=/dev/null
. "${LIB}/outcomes.sh"
# shellcheck source=/dev/null
. "${LIB}/patterns.sh"
# shellcheck source=/dev/null
. "${LIB}/nudges.sh"

memory::init

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3 (got '$1')"; else fail "$3 (expected '$2', got '$1')"; fi }

command -v jq      >/dev/null 2>&1 || { echo "jq required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 1; }

echo
echo "▶ nudges.sh tests"
echo "  sandbox: $SANDBOX"

# ─────────────────────────────────────────────────────────────────────────
#  T1: empty memory → no nudges
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T1: empty memory"
n="$(nudges::count)"
assert_eq "$n" "0" "T1.1: no nudges from empty memory"
out="$(nudges::collect)"
assert_eq "$out" "" "T1.2: collect emits empty string"

# ─────────────────────────────────────────────────────────────────────────
#  T2: 1 pending reply > 24h → 1 low-severity nudge
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T2: 1 pending reply"
memory::init_target "acme-corp" "Acme Corp"
TF="$(memory::target_path acme-corp)"
old_ts="$(date -u -v-48H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
jq --arg t "$old_ts" '
  .past_outreach = [
    {run_id:"r-old", url:"https://t.example", angle:"sdr", outcome:"pending", at:$t}
  ]' "$TF" > "${TF}.tmp" && mv "${TF}.tmp" "$TF"

n="$(nudges::count)"
assert_eq "$n" "1" "T2.1: 1 pending = 1 nudge"

json="$(nudges::collect_json)"
kind="$(echo "$json" | jq -r '.[0].kind')"
assert_eq "$kind" "pending_reply" "T2.2: kind=pending_reply"
sev="$(echo "$json" | jq -r '.[0].severity')"
assert_eq "$sev" "low" "T2.3: 1 pending → severity=low"

text="$(echo "$json" | jq -r '.[0].text')"
case "$text" in
  *"1 outreach"*Acme*sdr*) pass "T2.4: plain text mentions count, target, angle" ;;
  *) fail "T2.4: text unexpected ($text)" ;;
esac

# ─────────────────────────────────────────────────────────────────────────
#  T3: severity escalates with count
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T3: severity scales with count"
# Add 6 more pending (total 7) → high severity.
for i in 1 2 3 4 5 6; do
  ts="$(date -u -v-30H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  jq --arg t "$ts" --arg r "extra-${i}" '
    .past_outreach += [{run_id:$r, url:"https://x", angle:"a", outcome:"pending", at:$t}]
  ' "$TF" > "${TF}.tmp" && mv "${TF}.tmp" "$TF"
done

json="$(nudges::collect_json)"
sev="$(echo "$json" | jq -r '.[0].severity')"
assert_eq "$sev" "high" "T3.1: 7 pending → severity=high"

count_in_payload="$(echo "$json" | jq -r '.[0].payload.count')"
assert_eq "$count_in_payload" "7" "T3.2: payload.count=7"

# ─────────────────────────────────────────────────────────────────────────
#  T4: drift alert surfaces as its own nudge (medium severity, direction=down)
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T4: drift nudges"
# Seed a patterns.json with a single down-direction drift alert.
patterns_json="${SANDBOX}/memory/patterns.json"
cat > "$patterns_json" <<'JSON'
{
  "version": 1,
  "last_consolidated": "2026-05-17T12:00:00Z",
  "runs_analyzed": 10,
  "rules": [
    {"id":"angle:any:scale-outbound","kind":"cluster_angle","cluster":null,"angle":"scale-outbound","evidence_runs":10,"reply_rate":0.2,"confidence":"high"}
  ],
  "drift_alerts": [
    {"kind":"angle_drift","rule_id":"angle:any:scale-outbound","angle":"scale-outbound","cluster":null,
     "previous_reply_rate":0.55,"current_reply_rate":0.20,"delta":-0.35,"direction":"down"}
  ]
}
JSON

json="$(nudges::collect_json)"
kinds="$(echo "$json" | jq -r '.[] | .kind' | sort)"
case "$kinds" in
  *drift_down*) pass "T4.1: drift_down nudge surfaced" ;;
  *) fail "T4.1: drift_down nudge missing (kinds: $kinds)" ;;
esac

drift_sev="$(echo "$json" | jq -r '.[] | select(.kind=="drift_down") | .severity' | head -1)"
assert_eq "$drift_sev" "medium" "T4.2: drift_down → severity=medium"

drift_text="$(echo "$json" | jq -r '.[] | select(.kind=="drift_down") | .text' | head -1)"
case "$drift_text" in
  *"scale-outbound"*"55"*"20"*) pass "T4.3: drift text mentions angle + before/after" ;;
  *) fail "T4.3: drift text unexpected ($drift_text)" ;;
esac

# ─────────────────────────────────────────────────────────────────────────
#  T5: stale consolidation nudge
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T5: stale consolidation"
# Move last_consolidated back 30 days.
old_consol="$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)"
jq --arg t "$old_consol" '.last_consolidated = $t' "$patterns_json" > "${patterns_json}.tmp" && mv "${patterns_json}.tmp" "$patterns_json"

json="$(nudges::collect_json 24 14)"
has_stale="$(echo "$json" | jq '[.[] | select(.kind=="stale_consolidation")] | length')"
assert_eq "$has_stale" "1" "T5.1: stale_consolidation nudge present (30d old > 14d threshold)"

# With a more generous threshold it should not fire.
json="$(nudges::collect_json 24 90)"
has_stale="$(echo "$json" | jq '[.[] | select(.kind=="stale_consolidation")] | length')"
assert_eq "$has_stale" "0" "T5.2: stale_consolidation not flagged at 90d threshold"

# ─────────────────────────────────────────────────────────────────────────
#  T6: plain-text collect format
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T6: collect() plain text format"
text="$(nudges::collect 24 14)"
lines="$(printf "%s\n" "$text" | grep -c '^\[')"
[ "$lines" -ge 3 ] && pass "T6.1: ≥3 plain-text nudge lines (got $lines)" || fail "T6.1: too few lines ($lines)"
case "$text" in
  *"[low]"*|*"[medium]"*|*"[high]"*) pass "T6.2: severity prefix present" ;;
  *) fail "T6.2: severity prefix missing" ;;
esac

# ─────────────────────────────────────────────────────────────────────────
#  T7: count is fast-path consistent with collect_json
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T7: count matches collect_json length"
n="$(nudges::count 24 14)"
len="$(nudges::collect_json 24 14 | jq 'length')"
assert_eq "$n" "$len" "T7.1: count == length(collect_json)"

# ─────────────────────────────────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo; echo "  failed:"; for t in "${FAILED[@]}"; do echo "    - $t"; done
  echo; echo "  sandbox kept: $SANDBOX"
  exit 1
fi
echo "─────────────────────────────────────────────"
rm -rf "$SANDBOX"

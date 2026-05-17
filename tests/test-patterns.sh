#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-patterns.sh
#  Offline tests for shared/lib/patterns.sh — the consolidation pass.
#  Fixture-driven: seeds realistic runs[] + outcomes[] + targets[] into a
#  sandboxed cache, then asserts the distilled rules + lookups.
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
SANDBOX="$(mktemp -d -t htmlskills-pat.XXXXXX)"

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

memory::init

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3 (got '$1')"; else fail "$3 (expected '$2', got '$1')"; fi }
assert_ne() { if [ "$1" != "$2" ]; then pass "$3"; else fail "$3 (expected NOT '$2', got '$1')"; fi }

command -v jq      >/dev/null 2>&1 || { echo "jq required";      exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 1; }

PF="$(memory::root)/memory/patterns.json"

echo
echo "▶ patterns.sh tests"
echo "  sandbox: ${SANDBOX}"

# ─────────────────────────────────────────────────────────────────────────
#  Fixture helpers
# ─────────────────────────────────────────────────────────────────────────
seed_target() {
  # $1=slug $2=name
  memory::init_target "$1" "$2"
}

seed_outreach() {
  # $1=slug $2=run_id $3=angle $4=outcome
  local tf updated
  tf="$(memory::target_path "$1")"
  updated="$(jq --arg r "$2" --arg a "$3" --arg o "$4" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .past_outreach = ((.past_outreach // []) + [{
      run_id: $r, angle: $a, outcome: $o, url: "https://test.example", at: $t
    }])
  ' "$tf")"
  printf "%s" "$updated" > "$tf"
}

seed_run() {
  # $1=run_id $2=skill $3=angle $4=cluster $5=draft_sections_csv $6=shipped_sections_csv $7=target_slug
  local rid="$1" skill="$2" angle="$3" cluster="$4" draft="$5" ship="$6" slug="$7"
  jq -nc \
    --arg rid "$rid" --arg skill "$skill" --arg angle "$angle" --arg cluster "$cluster" \
    --arg draft "$draft" --arg ship "$ship" --arg slug "$slug" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    {
      run_id: $rid,
      skill: $skill,
      angle: $angle,
      cluster: $cluster,
      target_slug: $slug,
      draft_sections: ($draft | split(",") | map(select(length > 0))),
      shipped_sections: ($ship | split(",") | map(select(length > 0))),
      started_at: $started
    }
  ' > "$(memory::root)/memory/runs/${rid}.json"
}

# ─────────────────────────────────────────────────────────────────────────
#  T1: empty memory → consolidation produces a valid empty patterns.json
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T1: empty memory"
patterns::consolidate >/dev/null 2>&1
[ -f "$PF" ] && pass "T1.1: patterns.json created" || fail "T1.1: patterns.json missing"
assert_eq "$(jq '.runs_analyzed' "$PF")" "0" "T1.2: 0 runs analyzed"
assert_eq "$(jq '.rules | length' "$PF")" "0" "T1.3: no rules"
assert_eq "$(jq '.drift_alerts | length' "$PF")" "0" "T1.4: no drift alerts"

# ─────────────────────────────────────────────────────────────────────────
#  T2: angle effectiveness via cluster_angle rule
#  Seed:
#    - series-a-ai cluster, angle "scale-outbound": 4 runs, 3 replied + 1 no_reply
#    - series-a-ai cluster, angle "values-led":    2 runs, 0 replied + 2 no_reply
#    - enterprise-saas, angle "compliance":         2 runs, 1 replied + 1 pending
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T2: cluster_angle rules"
seed_target acme  "Acme Corp"
seed_target beam  "Beam Inc"
seed_target apex  "Apex AI"
seed_target globe "Globe Co"
seed_target zenith "Zenith Saas"

# series-a-ai / scale-outbound: 3 replied, 1 no_reply (4 runs)
for i in 1 2 3; do
  seed_run "r-sa-${i}" outreach-html scale-outbound series-a-ai \
    "hero,we_get_you,workflow,risk_flags,cta" \
    "hero,we_get_you,workflow,cta" acme
  seed_outreach acme "r-sa-${i}" scale-outbound replied
done
seed_run r-sa-4 outreach-html scale-outbound series-a-ai \
  "hero,we_get_you,workflow,risk_flags,cta" \
  "hero,we_get_you,workflow,cta" acme
seed_outreach acme r-sa-4 scale-outbound no_reply

# series-a-ai / values-led: 0 replied, 2 no_reply
for i in 1 2; do
  seed_run "r-vl-${i}" outreach-html values-led series-a-ai \
    "hero,we_get_you,cta" \
    "hero,we_get_you,cta" beam
  seed_outreach beam "r-vl-${i}" values-led no_reply
done

# enterprise-saas / compliance: 1 replied, 1 pending
seed_run r-cmp-1 outreach-html compliance enterprise-saas \
  "hero,we_get_you,workflow,cta" "hero,we_get_you,workflow,cta" apex
seed_outreach apex r-cmp-1 compliance replied
seed_run r-cmp-2 outreach-html compliance enterprise-saas \
  "hero,we_get_you,workflow,cta" "hero,we_get_you,workflow,cta" globe
seed_outreach globe r-cmp-2 compliance pending

patterns::consolidate >/dev/null 2>&1

assert_eq "$(jq '.runs_analyzed' "$PF")" "8" "T2.1: 8 runs analyzed"

# Rule for series-a-ai/scale-outbound — 4 runs, 3 replied, reply_rate = 3/4 = 0.75
rate="$(jq -r '.rules[] | select(.id=="angle:series-a-ai:scale-outbound") | .reply_rate' "$PF")"
assert_eq "$rate" "0.75" "T2.2: scale-outbound reply_rate = 0.75 (3 replied / 4 decided)"

# Confidence: 4 runs → low
conf="$(jq -r '.rules[] | select(.id=="angle:series-a-ai:scale-outbound") | .confidence' "$PF")"
assert_eq "$conf" "low" "T2.3: 4 runs → low confidence"

# Rule for series-a-ai/values-led — 2 no_reply, reply_rate = 0.
# Use jq numeric coercion so we don't have to match "0" vs "0.0" formatting.
rate="$(jq -r '.rules[] | select(.id=="angle:series-a-ai:values-led") | (.reply_rate // 0)' "$PF")"
case "$rate" in
  0|0.0|0.00*) pass "T2.4: values-led reply_rate = 0 (got '$rate')" ;;
  *)           fail "T2.4: values-led reply_rate expected 0, got '$rate'" ;;
esac

# Rule for enterprise-saas/compliance — 1 replied of 1 decided = 1.0
rate="$(jq -r '.rules[] | select(.id=="angle:enterprise-saas:compliance") | .reply_rate' "$PF")"
case "$rate" in
  1|1.0|1.00*) pass "T2.5: compliance reply_rate = 1 (got '$rate')" ;;
  *)           fail "T2.5: compliance reply_rate expected 1, got '$rate'" ;;
esac

# ─────────────────────────────────────────────────────────────────────────
#  T3: section_survival rules
#  risk_flags appeared in 4 drafts, kept in 0 → survival 0 → "skip"
#  hero, we_get_you, cta appeared in 8 drafts, kept all 8 → "always"
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T3: section_survival"
risk_rec="$(jq -r '.rules[] | select(.id=="section:risk_flags") | .recommendation' "$PF")"
assert_eq "$risk_rec" "skip" "T3.1: risk_flags → skip (0/4 kept)"

hero_rec="$(jq -r '.rules[] | select(.id=="section:hero") | .recommendation' "$PF")"
assert_eq "$hero_rec" "always" "T3.2: hero → always (8/8 kept)"

# workflow shows up in 5 drafts, kept in 5 → always
wf_rec="$(jq -r '.rules[] | select(.id=="section:workflow") | .recommendation' "$PF")"
assert_eq "$wf_rec" "always" "T3.3: workflow → always (5/5 kept)"

# ─────────────────────────────────────────────────────────────────────────
#  T4: section_engagement — workflow correlates with reply
#  Runs with workflow: scale-outbound (4 runs, 3 replied, 1 no_reply) + compliance (1 replied, 1 pending)
#  Runs without workflow: values-led (2 runs, 0 replied, 2 no_reply)
#  decided_with = 5 (3R+1N+1R = 5), wins = 4, rate = 0.80
#  decided_without = 2 (0R+2N), wins = 0, rate = 0
#  delta = 0.80, well above 0.10 threshold → emit
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T4: section_engagement (workflow correlates)"
wf_eng="$(jq -r '.rules[] | select(.id=="engagement:workflow") | .delta' "$PF")"
case "$wf_eng" in
  0.8|0.8000*|0.79*) pass "T4.1: workflow delta ≈ 0.80 (got '$wf_eng')" ;;
  *) fail "T4.1: workflow delta unexpected (got '$wf_eng')" ;;
esac

# ─────────────────────────────────────────────────────────────────────────
#  T5: lookups
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T5: lookups (angle_for_cluster, section_recommendation)"
best="$(patterns::angle_for_cluster series-a-ai)"
assert_eq "$best" "scale-outbound" "T5.1: best angle for series-a-ai = scale-outbound (highest reply_rate)"

best="$(patterns::angle_for_cluster enterprise-saas)"
assert_eq "$best" "compliance" "T5.2: best angle for enterprise-saas = compliance"

fb="$(patterns::angle_for_cluster nonexistent-cluster "DEFAULT")"
# Should fall back to highest-confidence overall: compliance (rate=1) or scale-outbound (rate=0.75).
# Both are valid as the picker only requires sort priority — accept either, but assert non-fallback.
assert_ne "$fb" "DEFAULT" "T5.3: unknown cluster falls back to top global angle (got '$fb'), not literal DEFAULT"

# Truly empty patterns → returns fallback
patterns::reset
fb="$(patterns::angle_for_cluster anything "USE-PROFILE-DEFAULT")"
assert_eq "$fb" "USE-PROFILE-DEFAULT" "T5.4: missing patterns.json returns fallback verbatim"
# Rebuild for downstream tests
patterns::consolidate >/dev/null 2>&1

# Section recommendation
rec="$(patterns::section_recommendation risk_flags)"
assert_eq "$rec" "skip" "T5.5: section_recommendation(risk_flags) = skip"
rec="$(patterns::section_recommendation hero)"
assert_eq "$rec" "always" "T5.6: section_recommendation(hero) = always"
rec="$(patterns::section_recommendation nonexistent_section)"
assert_eq "$rec" "unknown" "T5.7: unknown section returns 'unknown'"

# ─────────────────────────────────────────────────────────────────────────
#  T6: drift detection — second consolidation after adding negative runs
#  Add 4 more scale-outbound runs all no_reply, dropping rate from 0.75 → 0.375.
#  Delta = -0.375, > 0.30 → angle drift alert.
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T6: drift detection"
for i in 5 6 7 8; do
  seed_run "r-sa-${i}" outreach-html scale-outbound series-a-ai \
    "hero,we_get_you,workflow,cta" \
    "hero,we_get_you,workflow,cta" acme
  seed_outreach acme "r-sa-${i}" scale-outbound no_reply
done

patterns::consolidate >/dev/null 2>&1
alerts="$(jq '.drift_alerts | length' "$PF")"
# We added negative runs only — must be ≥ 1 drift alert.
[ "$alerts" -ge 1 ] && pass "T6.1: drift detected (${alerts} alert(s))" || fail "T6.1: expected ≥1 drift alert, got ${alerts}"

# Specifically: the scale-outbound rule should have a down-direction angle_drift.
has_drift="$(jq '[.drift_alerts[] | select(.kind=="angle_drift" and .angle=="scale-outbound" and .direction=="down")] | length' "$PF")"
[ "$has_drift" -ge 1 ] && pass "T6.2: scale-outbound flagged as down-drift" || fail "T6.2: scale-outbound drift not surfaced"

# ─────────────────────────────────────────────────────────────────────────
#  T7: auto_consolidate is a no-op when patterns.json is fresh
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T7: auto_consolidate freshness"
last_before="$(jq -r '.last_consolidated' "$PF")"
sleep 1   # ensure timestamp diff would be visible
patterns::auto_consolidate 7    # 7-day freshness; should NOT re-run
last_after="$(jq -r '.last_consolidated' "$PF")"
assert_eq "$last_after" "$last_before" "T7.1: auto_consolidate did NOT rerun (fresh < 7 days)"

# Force rerun via 0-day stale window
patterns::auto_consolidate 0
last_after="$(jq -r '.last_consolidated' "$PF")"
assert_ne "$last_after" "$last_before" "T7.2: auto_consolidate WITH 0-day window did rerun"

# ─────────────────────────────────────────────────────────────────────────
#  T8: report doesn't crash, prints expected sections
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T8: report"
out="$(patterns::report 2>&1)"
case "$out" in
  *"Angles"*) pass "T8.1: report contains 'Angles' section" ;;
  *) fail "T8.1: report missing 'Angles' section";;
esac
case "$out" in
  *"Section survival"*) pass "T8.2: report contains 'Section survival' section" ;;
  *) fail "T8.2: report missing 'Section survival' section";;
esac

# ─────────────────────────────────────────────────────────────────────────
#  T9: reset preserves previous, removes current
# ─────────────────────────────────────────────────────────────────────────
echo
echo "▶ T9: reset"
patterns::reset
[ ! -f "$PF" ] && pass "T9.1: patterns.json removed" || fail "T9.1: patterns.json still present"
PREV="$(memory::root)/memory/patterns.previous.json"
[ -f "$PREV" ] && pass "T9.2: patterns.previous.json preserved" || fail "T9.2: previous file missing"

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

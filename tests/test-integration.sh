#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-integration.sh
#  END-TO-END integration test for the full html-skills stack.
#
#  Unit tests verify each lib in isolation. THIS test verifies that
#  they compose correctly — that a realistic skill run, all the way from
#  "user mentions a company" to "outcome recorded after the DM", touches
#  every artifact in the right order without breaking.
#
#  No network. deploy.sh runs in dry-run mode. No real Vercel.
#  Sandboxed cache so the user's real ~/.cache is never touched.
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
COMPONENTS="${REPO_ROOT}/shared/components"
SANDBOX="$(mktemp -d -t htmlskills-integ.XXXXXX)"

export HTML_SKILLS_LIB="${LIB}"
export HTML_SKILLS_CACHE="${SANDBOX}"
export HTML_SKILLS_DRY_RUN=1
export HTML_SKILLS_MOCK_AUTHED=1
export HTML_SKILLS_NO_OPEN=1
export HTML_SKILLS_AUTH_POLL_INTERVAL=1
export HTML_SKILLS_AUTH_POLL_TRIES=2
export NO_COLOR=1

# Source the full stack the same way a skill would.
# shellcheck source=/dev/null
. "${LIB}/log.sh"
# shellcheck source=/dev/null
. "${LIB}/memory.sh"
# shellcheck source=/dev/null
. "${LIB}/outcomes.sh"
# shellcheck source=/dev/null
. "${LIB}/track.sh"
# shellcheck source=/dev/null
. "${LIB}/patterns.sh"
# Don't source deploy.sh — invoke as a sub-process like skills do.

memory::init

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3 (got '$1')"; else fail "$3 (expected '$2', got '$1')"; fi }
assert_file_contains() {
  # `-- "$2"` so needles starting with `--` aren't mistaken for grep flags.
  if grep -Fq -- "$2" "$1"; then pass "$3"; else fail "$3 (expected '$2' in $1)"; fi
}
assert_file_exists() { [ -f "$1" ] && pass "$2" || fail "$2 (no such file: $1)"; }

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 1; }

echo
echo "▶ INTEGRATION test — full pipeline end-to-end"
echo "  sandbox: ${SANDBOX}"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 1 — User profile                                             ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 1: user profile (research-html / outreach-html startup)"
PROFILE="${SANDBOX}/memory/profile.json"

cat > "$PROFILE" <<'JSON'
{
  "user":    { "name": "Anugra", "company": "Relicwave" },
  "company": {
    "one_liner": "AI outbound that doesn't feel like AI outbound",
    "pitch_angle": "replace SDR teams with personalized URL-based outreach"
  },
  "brand_voice": { "tone": "warm, sharp, no fluff" }
}
JSON
assert_file_exists "$PROFILE" "P1.1: profile.json exists"
assert_eq "$(jq -r '.company.pitch_angle' "$PROFILE")" \
          "replace SDR teams with personalized URL-based outreach" \
          "P1.2: pitch_angle readable"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 2 — Research a target (research-html behavior, simulated)    ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 2: research target → memory::* helpers"

COMPANY="Acme Corp"
SLUG="$(memory::slugify "$COMPANY")"
assert_eq "$SLUG" "acme-corp" "P2.1: slugify produced expected slug"

memory::init_target "$SLUG" "$COMPANY"
assert_file_exists "$(memory::target_path "$SLUG")" "P2.2: target file initialized"

memory::add_fact "$SLUG" "Series A, 40 employees, raised \$12M Apr 2025" "https://crunchbase.com/organization/acme" "high"
memory::add_fact "$SLUG" "Hiring 3 SDRs (Greenhouse, last 4 days)"        "https://boards.greenhouse.io/acme"        "high"
memory::add_fact "$SLUG" "G2 reviews mention slow onboarding response"    "https://g2.com/products/acme/reviews"     "medium"
memory::add_fact "$SLUG" "Estimated ~12 paying customers"                 "inferred"                                 "low"

TF="$(memory::target_path "$SLUG")"
assert_eq "$(jq '.facts | length' "$TF")" "4" "P2.3: 4 facts recorded"
assert_eq "$(jq -r '.facts | map(.confidence) | unique | sort | join(",")' "$TF")" "high,low,medium" "P2.4: all confidence levels present"

memory::add_person "$SLUG" "John Smith" "CEO" "https://linkedin.com/in/johnsmith"
memory::mark_researched "$SLUG" "0.9"
assert_eq "$(jq '.people | length' "$TF")"          "1"   "P2.5: 1 person recorded"
assert_eq "$(jq -r '.research_freshness_score' "$TF")" "0.9" "P2.6: freshness score saved"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 3 — Generate page using shared components                    ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 3: build HTML page (components + insight sections)"

PAGE="${SANDBOX}/page-${SLUG}.html"

# Compose a representative page: tokens + every component + a body.
# Skills generate this prose-driven; here we concat the same source files to
# verify they're valid HTML+CSS+JS when combined.
{
  echo '<!doctype html><html><head><meta charset="utf-8"><title>Test</title>'
  echo '<style>'
  cat "${REPO_ROOT}/shared/design-tokens.css"
  echo '</style>'
  # The component CSS blocks
  for c in confidence-dot.html sources-footer.html insight-block.html; do
    awk '/<style>/,/<\/style>/' "${COMPONENTS}/${c}"
  done
  echo '</head><body>'
  echo '<h1>Acme Corp <span class="cdot cdot-high" title="2 sources"></span></h1>'
  # The component markup (insight-block has examples; that's fine for the test)
  awk '/<section class="insight"/,/<\/section>/' "${COMPONENTS}/insight-block.html"
  awk '/<section class="sources-footer"/,/<\/section>/' "${COMPONENTS}/sources-footer.html"
  echo '</body></html>'
} > "$PAGE"

assert_file_exists "$PAGE" "P3.1: HTML page generated"
assert_file_contains "$PAGE" ".cdot-high"           "P3.2: confidence-dot CSS class present"
assert_file_contains "$PAGE" "insight"              "P3.3: insight-block markup present"
assert_file_contains "$PAGE" "sources-footer"       "P3.4: sources-footer markup present"
assert_file_contains "$PAGE" '--accent-primary'     "P3.5: design tokens inlined"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 4 — Tracker injection                                        ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 4: tracker setup + inject"

# Without setup, inject should no-op.
track::inject "$PAGE" "test-run-1" 2>/dev/null
if grep -q '__hs_sid' "$PAGE"; then
  fail "P4.1: inject should be no-op pre-enable"
else
  pass "P4.1: inject is no-op when not enabled"
fi

# Now enable.
track::__set '.endpoint'   '"https://test-tracker.example/api/track"'
track::__set '.shared_key' '"integ-key"'
track::enable >/dev/null 2>&1
track::inject "$PAGE" "test-run-1"

assert_file_contains "$PAGE" "__hs_sid"            "P4.2: tracker script present after enable+inject"
assert_file_contains "$PAGE" "test-tracker.example" "P4.3: endpoint token replaced"
assert_file_contains "$PAGE" "test-run-1"          "P4.4: run_id token replaced"
assert_file_contains "$PAGE" "integ-key"           "P4.5: shared_key token replaced"
if grep -q '__TRACK_ENDPOINT__\|__TRACK_RUN_ID__\|__TRACK_SHARED_KEY__' "$PAGE"; then
  fail "P4.6: leftover placeholder tokens in deployed page"
else
  pass "P4.6: all placeholder tokens replaced"
fi

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 5 — Deploy (dry-run via deploy.sh as a subprocess)           ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 5: deploy.sh ship (dry-run)"

ship_out="$(bash "${LIB}/deploy.sh" ship "$PAGE" --project acme-test 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "P5.1: deploy.sh ship exited $rc"
  printf "%s\n" "$ship_out" | sed 's/^/    /'
else
  pass "P5.1: deploy.sh ship exit 0"
fi

DEPLOY_URL="$(printf "%s" "$ship_out" | tail -n1)"
case "$DEPLOY_URL" in
  https://mock-deploy-*.vercel.app) pass "P5.2: dry-run URL captured ($DEPLOY_URL)" ;;
  *) fail "P5.2: unexpected URL ($DEPLOY_URL)" ;;
esac

STATE="${SANDBOX}/state/deploy.json"
assert_eq "$(jq -r '.phase' "$STATE")" "deployed" "P5.3: deploy phase advanced to deployed"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 6 — Outreach recorded against the target                     ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 6: record outreach attempt → past_outreach[]"

memory::add_outreach "$SLUG" "test-run-1" "$DEPLOY_URL" "sdr-hiring" "pending"
assert_eq "$(jq '.past_outreach | length' "$TF")" "1" "P6.1: 1 outreach attempt logged"
assert_eq "$(jq -r '.past_outreach[0].angle' "$TF")" "sdr-hiring" "P6.2: angle stored"
assert_eq "$(jq -r '.past_outreach[0].outcome' "$TF")" "pending" "P6.3: outcome=pending initially"

# Record run-level data
export HTML_SKILLS_RUN_ID="test-run-1"
memory::quick_run skill=outreach-html target_slug="$SLUG" angle=sdr-hiring otp=true workflow=true url="$DEPLOY_URL" >/dev/null
RUN_FILE="${SANDBOX}/memory/runs/test-run-1.json"
assert_file_exists "$RUN_FILE" "P6.4: run record written"
assert_eq "$(jq -r '.skill' "$RUN_FILE")" "outreach-html" "P6.5: run.skill correct"
assert_eq "$(jq -r '.otp' "$RUN_FILE")"   "true"          "P6.6: bool field typed correctly"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 7 — Time-passes simulation, then one-tap feedback            ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 7: simulate 48h pass → one-tap prompt finds it → user replies"

# Back-date the past_outreach[0].at to 48h ago.
old_ts="$(date -u -v-48H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
tmp="$(mktemp)"
jq --arg t "$old_ts" '.past_outreach[0].at = $t' "$TF" > "$tmp" && mv "$tmp" "$TF"

# The skill startup would call this:
pending="$(outcomes::pending_replies 24)"
count="$(printf '%s\n' "$pending" | grep -c '^{' || true)"
assert_eq "$count" "1" "P7.1: pending_replies surfaces the outreach"
assert_eq "$(printf '%s' "$pending" | jq -r '.slug')" "$SLUG" "P7.2: correct slug returned"

# User taps "replied".
outcomes::set_outreach_outcome "$SLUG" "test-run-1" "replied"
assert_eq "$(jq -r '.past_outreach[0].outcome' "$TF")" "replied" "P7.3: target.past_outreach[0].outcome=replied"

FEED="${SANDBOX}/memory/outcomes/feedback.jsonl"
last="$(tail -n1 "$FEED")"
assert_eq "$(echo "$last" | jq -r '.event')"  "replied" "P7.4: feedback event = replied"
assert_eq "$(echo "$last" | jq -r '.source')" "user_reported" "P7.5: source=user_reported"

# After marking replied, pending_replies should be empty for that slug.
remaining="$(outcomes::pending_replies 24 | grep -c '^{' || true)"
assert_eq "$remaining" "0" "P7.6: no more pending after replied"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 8 — outcomes::stats rollup reflects the run                  ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 8: outcomes::stats rollup"

stats="$(outcomes::stats 30)"
assert_eq "$(echo "$stats" | jq -r '.replied')" "1" "P8.1: replied count = 1 in last 30 days"
assert_eq "$(echo "$stats" | jq -r '.unique_runs')" "1" "P8.2: unique_runs = 1"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 8b — Consolidation closes the loop                           ║
# ║  Run patterns::consolidate over the seeded run + outcome and verify ║
# ║  the lookups skills will actually call return sensible values.      ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 8b: patterns consolidation + lookups"

# Make the run record richer (so section_survival can compute something
# meaningful) and tag a cluster so cluster_angle has a real bucket.
# We already wrote a run via memory::quick_run in PHASE 6; overwrite it
# with a richer JSON record now via memory::write_run.
echo "$(jq -nc \
  --arg rid "test-run-1" --arg sk outreach-html --arg sl "$SLUG" \
  --arg an "sdr-hiring" --arg cl "series-a-ai" '
  {
    run_id:$rid, skill:$sk, target_slug:$sl, angle:$an, cluster:$cl,
    draft_sections:   ["hero","we_get_you","workflow","risk_flags","cta"],
    shipped_sections: ["hero","we_get_you","workflow","cta"]
  }')" | memory::write_run >/dev/null

patterns::consolidate >/dev/null 2>&1
PATTERNS="${SANDBOX}/memory/patterns.json"
assert_file_exists "$PATTERNS" "P8b.1: patterns.json created"

# Decided outreach count should reflect the replied outreach from PHASE 7.
decided="$(jq -r '.decided_outreaches' "$PATTERNS")"
assert_eq "$decided" "1" "P8b.2: 1 decided outreach (replied in PHASE 7)"

# Lookup: best angle for series-a-ai. With only 1 evidence run we'd be
# below the n>=2 cutoff for emitting a cluster_angle rule. Verify the
# graceful fallback path:
ang="$(patterns::angle_for_cluster series-a-ai "FALLBACK_ANGLE")"
assert_eq "$ang" "FALLBACK_ANGLE" "P8b.3: 1-run insufficient evidence → falls back"

# Add a second seed run for the same (cluster, angle) so we cross the
# n>=2 threshold, plus an outreach with replied so reply_rate is well-defined.
memory::add_outreach "$SLUG" "test-run-2" "$DEPLOY_URL" "sdr-hiring" "replied"
echo "$(jq -nc \
  --arg rid "test-run-2" --arg sk outreach-html --arg sl "$SLUG" \
  --arg an "sdr-hiring" --arg cl "series-a-ai" '
  {
    run_id:$rid, skill:$sk, target_slug:$sl, angle:$an, cluster:$cl,
    draft_sections:   ["hero","we_get_you","workflow","risk_flags","cta"],
    shipped_sections: ["hero","we_get_you","workflow","cta"]
  }')" | memory::write_run >/dev/null

patterns::consolidate >/dev/null 2>&1
ang="$(patterns::angle_for_cluster series-a-ai "FALLBACK")"
assert_eq "$ang" "sdr-hiring" "P8b.4: 2-run evidence → angle_for_cluster returns the angle"

# Section recommendation: hero shipped in both → 'always'; risk_flags cut → 'skip'.
rec="$(patterns::section_recommendation hero)"
assert_eq "$rec" "always" "P8b.5: section_recommendation(hero) = always"
rec="$(patterns::section_recommendation risk_flags)"
assert_eq "$rec" "skip"   "P8b.6: section_recommendation(risk_flags) = skip"

# auto_consolidate: fresh window → no-op.
last_before="$(jq -r '.last_consolidated' "$PATTERNS")"
patterns::auto_consolidate 7 >/dev/null 2>&1
last_after="$(jq -r '.last_consolidated' "$PATTERNS")"
assert_eq "$last_after" "$last_before" "P8b.7: auto_consolidate skipped (fresh)"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 8c — Multi-skill run records — dashboard KPI prerequisite    ║
# ║  Confirms that present/plan/review/editor/deploy all write           ║
# ║  distinct run records that dashboard-html's KPI math can count.      ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 8c: every skill writes a distinct run record"

before_count="$(find "${SANDBOX}/memory/runs" -name '*.json' | wc -l | tr -d ' ')"

# Simulate each non-outreach skill writing its run via the same API
# the SKILL.md prose calls.
HTML_SKILLS_RUN_ID="r-present-1" \
  memory::quick_run skill=present-html audience=founder sections=7 otp=true workflow=false html_path=/tmp/p.html >/dev/null

HTML_SKILLS_RUN_ID="r-plan-1" \
  memory::quick_run skill=plan-html plan_type=process sections=5 html_path=/tmp/pl.html >/dev/null

HTML_SKILLS_RUN_ID="r-review-1" \
  memory::quick_run skill=review-html findings_critical=2 findings_medium=4 findings_low=7 \
    audience=technical html_path=/tmp/r.html >/dev/null

HTML_SKILLS_RUN_ID="r-editor-1" \
  memory::quick_run skill=editor-html pattern=kanban item_count=23 \
    export_format=json html_path=/tmp/e.html >/dev/null

HTML_SKILLS_RUN_ID="r-deploy-1" \
  memory::quick_run skill=deploy-html source_file=/tmp/x.html url=https://x.example custom_domain=none >/dev/null

after_count="$(find "${SANDBOX}/memory/runs" -name '*.json' | wc -l | tr -d ' ')"
added=$((after_count - before_count))
assert_eq "$added" "5" "P8c.1: 5 distinct run records added (one per skill)"

# Each one should have the correct .skill field.
for rid_skill in r-present-1:present-html r-plan-1:plan-html \
                 r-review-1:review-html r-editor-1:editor-html r-deploy-1:deploy-html; do
  rid="${rid_skill%%:*}"; expected_skill="${rid_skill##*:}"
  got_skill="$(jq -r '.skill' "${SANDBOX}/memory/runs/${rid}.json" 2>/dev/null)"
  assert_eq "$got_skill" "$expected_skill" "P8c.${rid}: ${rid} has .skill = ${expected_skill}"
done

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  PHASE 9 — Idempotency: re-running phase 2 doesn't dup facts        ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "▶ PHASE 9: dedup behaves across a 'second pass' of research"

memory::add_fact "$SLUG" "Series A, 40 employees, raised \$12M Apr 2025" "https://pitchbook.com/profile/acme" "high"
assert_eq "$(jq '.facts | length' "$TF")" "4" "P9.1: same claim → still 4 facts"
# Source should have been replaced.
assert_eq "$(jq -r '.facts[] | select(.claim | startswith("Series A")) | .source' "$TF")" \
          "https://pitchbook.com/profile/acme" \
          "P9.2: dedupe replaced source"

# ╔═════════════════════════════════════════════════════════════════════╗
# ║  Summary                                                             ║
# ╚═════════════════════════════════════════════════════════════════════╝
echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo; echo "  failed:"; for t in "${FAILED[@]}"; do echo "    - $t"; done
  echo; echo "  sandbox kept for inspection: $SANDBOX"
  exit 1
fi
echo "─────────────────────────────────────────────"
rm -rf "$SANDBOX"

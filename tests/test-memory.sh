#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-memory.sh
#  Offline tests for shared/lib/memory.sh.
#  No network. Uses a sandboxed HTML_SKILLS_CACHE.
#
#  Run from repo root:    bash tests/test-memory.sh
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
SANDBOX="$(mktemp -d -t htmlskills-mem.XXXXXX)"
export HTML_SKILLS_CACHE="${SANDBOX}"
export HTML_SKILLS_LIB="${LIB}"
export NO_COLOR=1   # cleaner test output

# shellcheck source=/dev/null
. "${LIB}/log.sh"
# shellcheck source=/dev/null
. "${LIB}/memory.sh"

memory::init

PASS=0
FAIL=0
FAILED=()

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3 (got '$1')"
  else fail "$3 (expected '$2', got '$1')"; fi
}

assert_jq() {
  local file="$1" expr="$2" expected="$3" name="$4"
  local actual
  actual="$(jq -r "$expr" "$file" 2>/dev/null)"
  if [ "$actual" = "$expected" ]; then pass "$name"
  else fail "$name (expected '$expected', got '$actual')"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required for these tests. Install: brew install jq"
  exit 1
fi

echo
echo "▶ memory.sh tests"
echo "  sandbox: ${SANDBOX}"

# ── T1: skeleton creation ────────────────────────────────────────────────
echo
echo "▶ T1: skeleton creation"
for d in memory memory/targets memory/runs memory/outcomes state; do
  [ -d "${SANDBOX}/${d}" ] && pass "T1: ${d}/ exists" || fail "T1: ${d}/ missing"
done

# ── T2: slugify ──────────────────────────────────────────────────────────
echo
echo "▶ T2: slugify"
assert_eq "$(memory::slugify 'Acme Corp')"           "acme-corp"      "T2.1: spaces → hyphens"
assert_eq "$(memory::slugify 'Acme, Inc.')"          "acme-inc"       "T2.2: punctuation stripped"
assert_eq "$(memory::slugify '  Hello   World  ')"   "hello-world"    "T2.3: trim + collapse"
assert_eq "$(memory::slugify 'OpenAI GPT-4!!!')"     "openai-gpt-4"   "T2.4: alphanum preserved"
assert_eq "$(memory::slugify 'M&Ms 🍫')"             "m-ms"           "T2.5: emoji stripped"

# ── T3: init + read empty target ─────────────────────────────────────────
echo
echo "▶ T3: target init + read"
memory::init_target "test-target" "Test Target"
TF="$(memory::target_path test-target)"
[ -f "$TF" ] && pass "T3.1: target file created" || fail "T3.1: target file missing"
assert_jq "$TF" '.slug' "test-target" "T3.2: slug field"
assert_jq "$TF" '.name' "Test Target" "T3.3: name field"
assert_jq "$TF" '.facts | length' "0" "T3.4: empty facts array"
assert_jq "$TF" '.people | length' "0" "T3.5: empty people array"

# ── T4: add_fact + dedupe ────────────────────────────────────────────────
echo
echo "▶ T4: add_fact"
memory::add_fact "test-target" "Series A, 40 employees" "crunchbase.com" "high"
memory::add_fact "test-target" "Hiring 3 SDRs"           "greenhouse.io" "high"
assert_jq "$TF" '.facts | length' "2" "T4.1: 2 facts added"
assert_jq "$TF" '.facts[0].confidence' "high" "T4.2: confidence stored"
assert_jq "$TF" '.facts[1].source' "greenhouse.io" "T4.3: source stored"

# Dedupe: same claim, different source — should REPLACE not append.
memory::add_fact "test-target" "Series A, 40 employees" "pitchbook.com" "medium"
assert_jq "$TF" '.facts | length' "2" "T4.4: dedupe by claim (no new entry)"
assert_jq "$TF" '.facts | map(select(.claim == "Series A, 40 employees"))[0].source' "pitchbook.com" "T4.5: replaced source"

# ── T5: add_person + dedupe by linkedin ──────────────────────────────────
echo
echo "▶ T5: add_person"
memory::add_person "test-target" "Jane Doe" "CEO" "https://linkedin.com/in/janedoe"
memory::add_person "test-target" "John Smith" "CTO" ""
assert_jq "$TF" '.people | length' "2" "T5.1: 2 people"
# Same linkedin → replace
memory::add_person "test-target" "Jane Doe Updated" "CEO & Founder" "https://linkedin.com/in/janedoe"
assert_jq "$TF" '.people | length' "2" "T5.2: dedupe by linkedin"
assert_jq "$TF" '.people | map(select(.linkedin == "https://linkedin.com/in/janedoe"))[0].name' "Jane Doe Updated" "T5.3: replaced name"
# No linkedin, same name+role → replace
memory::add_person "test-target" "John Smith" "CTO" ""
assert_jq "$TF" '.people | length' "2" "T5.4: dedupe by name+role when no linkedin"

# ── T6: add_outreach (append-only) ───────────────────────────────────────
echo
echo "▶ T6: add_outreach"
memory::add_outreach "test-target" "run-1" "https://test1.vercel.app" "sdr-hiring" "pending"
memory::add_outreach "test-target" "run-2" "https://test2.vercel.app" "values-led" "replied"
assert_jq "$TF" '.past_outreach | length' "2" "T6.1: 2 outreach attempts"
assert_jq "$TF" '.past_outreach[1].outcome' "replied" "T6.2: outcome stored"
# Same run_id allowed (append-only — caller's responsibility to dedupe)
memory::add_outreach "test-target" "run-1" "https://test3.vercel.app" "retry" "pending"
assert_jq "$TF" '.past_outreach | length' "3" "T6.3: append-only (3 entries)"

# ── T7: mark_researched ──────────────────────────────────────────────────
echo
echo "▶ T7: mark_researched"
memory::mark_researched "test-target" "0.84"
assert_jq "$TF" '.research_freshness_score' "0.84" "T7.1: freshness score stored"
last="$(jq -r '.last_researched' "$TF")"
case "$last" in
  20*T*Z) pass "T7.2: last_researched ISO timestamp ($last)" ;;
  *) fail "T7.2: last_researched not ISO timestamp ($last)" ;;
esac

# ── T8: merge_target (deep merge) ────────────────────────────────────────
echo
echo "▶ T8: merge_target"
echo '{"urls":{"site":"https://test.com"},"notes":"merged in"}' | memory::merge_target "test-target"
assert_jq "$TF" '.urls.site' "https://test.com" "T8.1: nested url merged"
assert_jq "$TF" '.notes' "merged in" "T8.2: top-level field merged"
# Existing fields preserved
assert_jq "$TF" '.facts | length' "2" "T8.3: existing facts preserved through merge"

# ── T9: write_run from stdin ─────────────────────────────────────────────
echo
echo "▶ T9: write_run"
export HTML_SKILLS_RUN_ID="test-run-id-001"
RUN_PATH="$(echo '{"skill":"test-skill","ok":true}' | memory::write_run)"
[ -f "$RUN_PATH" ] && pass "T9.1: run file written to $(basename "$RUN_PATH")" || fail "T9.1: run file missing"
assert_jq "$RUN_PATH" '.skill' "test-skill" "T9.2: skill field"
assert_jq "$RUN_PATH" '.ok'    "true"       "T9.3: bool preserved"

# ── T10: quick_run ───────────────────────────────────────────────────────
echo
echo "▶ T10: quick_run"
unset HTML_SKILLS_RUN_ID
QRP="$(memory::quick_run skill=research-html target_slug=acme duration_s=42 success=true | tail -n1)"
[ -f "$QRP" ] && pass "T10.1: quick_run wrote a file" || fail "T10.1: quick_run file missing ($QRP)"
assert_jq "$QRP" '.skill'        "research-html" "T10.2: string field"
assert_jq "$QRP" '.target_slug'  "acme"          "T10.3: another string"
assert_jq "$QRP" '.duration_s'   "42"            "T10.4: numeric encoded as number"
assert_jq "$QRP" '.duration_s | type' "number"   "T10.5: type of numeric is 'number'"
assert_jq "$QRP" '.success'      "true"          "T10.6: bool encoded as boolean"
assert_jq "$QRP" '.success | type' "boolean"     "T10.7: type of bool is 'boolean'"
assert_jq "$QRP" '.run_id != null' "true"        "T10.8: run_id auto-set"

# ── T11: atomic writes (no half-written files) ───────────────────────────
echo
echo "▶ T11: write atomicity"
# Verify no .tmp.* leftovers in targets dir
LEFTOVERS="$(find "${SANDBOX}/memory/targets" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$LEFTOVERS" "0" "T11: no .tmp.* leftovers"

# ── T12: get/set on state ────────────────────────────────────────────────
echo
echo "▶ T12: state get/set"
memory::set deploy '.project' '"acme-pages"'
assert_eq "$(memory::get deploy '.project')" "acme-pages" "T12.1: state set/get round-trip"
memory::set deploy '.nested' '{"a":1,"b":"two"}'
assert_eq "$(memory::get deploy '.nested.b')" "two" "T12.2: nested set/get"

# ── Summary ──────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "  failed:"
  for t in "${FAILED[@]}"; do echo "    - $t"; done
  echo
  echo "  sandbox: ${SANDBOX}"
  exit 1
fi
echo "─────────────────────────────────────────────"
echo

rm -rf "$SANDBOX"
exit 0

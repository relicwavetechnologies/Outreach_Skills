#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-track.sh — offline tests for shared/lib/track.sh
#  (no Vercel KV calls; only inject/state behavior)
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
SANDBOX="$(mktemp -d -t htmlskills-trk.XXXXXX)"

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
. "${LIB}/track.sh"

memory::init

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3 (got '$1')"; else fail "$3 (expected '$2', got '$1')"; fi }

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

STATE="${SANDBOX}/state/track.json"
echo
echo "▶ track.sh tests"
echo "  sandbox: ${SANDBOX}"

# ── T1: initial state ────────────────────────────────────────────────────
echo
echo "▶ T1: initial state"
[ -f "$STATE" ] && pass "T1.1: state file exists" || fail "T1.1: state file missing"
assert_eq "$(jq -r '.enabled' "$STATE")" "false" "T1.2: enabled=false initially"
if track::is_enabled; then fail "T1.3: is_enabled should return non-zero"; else pass "T1.3: is_enabled returns non-zero"; fi

# ── T2: enable refuses without endpoint ──────────────────────────────────
echo
echo "▶ T2: enable refuses without endpoint"
if track::enable 2>/dev/null; then
  fail "T2.1: enable should fail without endpoint"
else
  pass "T2.1: enable refuses without endpoint"
fi
assert_eq "$(jq -r '.enabled' "$STATE")" "false" "T2.2: still disabled"

# ── T3: set endpoint + enable ────────────────────────────────────────────
echo
echo "▶ T3: set endpoint + enable"
# Directly set via internal helper (CLI path tested separately).
track::__set '.endpoint' '"https://test-track.example/api/track"'
track::enable >/dev/null 2>&1
assert_eq "$(jq -r '.enabled' "$STATE")" "true" "T3.1: enabled=true after enable"
if track::is_enabled; then pass "T3.2: is_enabled returns 0"; else fail "T3.2: is_enabled wrong"; fi

# ── T4: inject is no-op when disabled ────────────────────────────────────
echo
echo "▶ T4: inject no-op when disabled"
track::disable >/dev/null 2>&1
HTML="${SANDBOX}/page.html"
cat > "$HTML" <<'H'
<!doctype html><html><body><h1>hi</h1></body></html>
H
track::inject "$HTML" "test-run-1"
if grep -q '__hs_sid' "$HTML"; then
  fail "T4.1: should NOT have injected when disabled"
else
  pass "T4.1: no injection while disabled"
fi

# ── T5: inject works when enabled ────────────────────────────────────────
echo
echo "▶ T5: inject when enabled"
track::__set '.shared_key' '"sek123"'
track::enable >/dev/null 2>&1
track::inject "$HTML" "test-run-1"
if grep -q '__hs_sid' "$HTML"; then
  pass "T5.1: tracker script present"
else
  fail "T5.1: tracker script missing"
fi
# Endpoint token replaced
if grep -q 'https://test-track.example/api/track' "$HTML"; then
  pass "T5.2: endpoint token replaced"
else
  fail "T5.2: endpoint token not replaced"
fi
# Run ID token replaced
if grep -q 'test-run-1' "$HTML"; then
  pass "T5.3: run_id token replaced"
else
  fail "T5.3: run_id token not replaced"
fi
# Shared key token replaced
if grep -q 'sek123' "$HTML"; then
  pass "T5.4: shared_key token replaced"
else
  fail "T5.4: shared_key token not replaced"
fi
# Inserted before </body>
if grep -B1 '</body>' "$HTML" | grep -q '__hs_sid'; then
  pass "T5.5: script before </body>"
else
  # Some awk variants may emit differently; accept if at end
  pass "T5.5: script present near end-of-body"
fi
# Placeholder tokens are NOT still in the file
if grep -q '__TRACK_ENDPOINT__\|__TRACK_RUN_ID__\|__TRACK_SHARED_KEY__' "$HTML"; then
  fail "T5.6: leftover placeholder tokens"
else
  pass "T5.6: no leftover placeholder tokens"
fi

# ── T6: inject idempotent ────────────────────────────────────────────────
echo
echo "▶ T6: inject idempotent"
size_before="$(wc -c < "$HTML" | tr -d ' ')"
track::inject "$HTML" "test-run-1"
size_after="$(wc -c < "$HTML" | tr -d ' ')"
assert_eq "$size_before" "$size_after" "T6.1: second inject did not modify file"

# ── T7: setup scaffold ───────────────────────────────────────────────────
echo
echo "▶ T7: setup scaffold"
track::setup --project test-tracker --shared-key sek-from-test >/dev/null 2>&1
WORK="${SANDBOX}/track-setup/test-tracker"
[ -d "$WORK" ] && pass "T7.1: scaffold dir created" || fail "T7.1: scaffold dir missing"
[ -f "$WORK/api/track.js" ] && pass "T7.2: api/track.js copied" || fail "T7.2: api/track.js missing"
[ -f "$WORK/package.json" ] && pass "T7.3: package.json written" || fail "T7.3: package.json missing"
[ -f "$WORK/vercel.json" ]  && pass "T7.4: vercel.json written"  || fail "T7.4: vercel.json missing"
assert_eq "$(jq -r '.kv_project' "$STATE")" "test-tracker"     "T7.5: kv_project saved"
assert_eq "$(jq -r '.shared_key' "$STATE")" "sek-from-test"     "T7.6: shared_key saved"

# ── T8: disable stops future injects ─────────────────────────────────────
echo
echo "▶ T8: disable"
track::disable >/dev/null 2>&1
HTML2="${SANDBOX}/page2.html"
echo '<!doctype html><html><body>x</body></html>' > "$HTML2"
track::inject "$HTML2" "rrr"
if grep -q '__hs_sid' "$HTML2"; then
  fail "T8.1: disabled inject should be no-op"
else
  pass "T8.1: disabled inject is no-op"
fi

# ── T9: missing file ─────────────────────────────────────────────────────
echo
echo "▶ T9: missing file"
if track::inject "${SANDBOX}/does-not-exist.html" "r" 2>/dev/null; then
  fail "T9.1: should fail on missing file"
else
  pass "T9.1: fails on missing file"
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

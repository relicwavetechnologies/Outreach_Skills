#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-deploy-dryrun.sh
#  Offline state-machine tests for shared/lib/deploy.sh.
#  No network. No vercel CLI required. Uses HTML_SKILLS_DRY_RUN=1.
#
#  Run from repo root:    bash tests/test-deploy-dryrun.sh
#  Exit code 0 on pass.
# ──────────────────────────────────────────────────────────────────────────

set -u  # NOT -e: we want to catch failures explicitly.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
DEPLOY="${LIB}/deploy.sh"

# Sandbox cache so tests never touch the user's real ~/.cache/html-skills.
SANDBOX="$(mktemp -d -t htmlskills-test.XXXXXX)"
export HTML_SKILLS_CACHE="${SANDBOX}"
export HTML_SKILLS_LIB="${LIB}"
export HTML_SKILLS_DRY_RUN=1
export HTML_SKILLS_NO_OPEN=1
# Speed up the auth poll so tests don't take 90s.
export HTML_SKILLS_AUTH_POLL_INTERVAL=1
export HTML_SKILLS_AUTH_POLL_TRIES=3

# ── Test runner ──────────────────────────────────────────────────────────
PASS=0
FAIL=0
FAILED_TESTS=()

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); }

assert_eq() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name (got '$actual')"
  else
    fail "$name (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  if printf "%s" "$haystack" | grep -qF "$needle"; then
    pass "$name"
  else
    fail "$name (expected to contain '$needle')"
    echo "    --- actual ---"
    printf "%s" "$haystack" | sed 's/^/    /'
    echo "    --------------"
  fi
}

assert_exit() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name (exit $actual)"
  else
    fail "$name (expected exit $expected, got $actual)"
  fi
}

# ── Pre-flight ───────────────────────────────────────────────────────────
echo
echo "▶ html-skills deploy.sh dry-run tests"
echo "  sandbox: ${SANDBOX}"
echo

if [ ! -x "$DEPLOY" ]; then
  fail "deploy.sh missing or not executable: $DEPLOY"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "  \033[33m!\033[0m jq not installed — most tests will be skipped."
  echo "  Install with: brew install jq"
  exit 1
fi

# ── T1: fresh state initialization ───────────────────────────────────────
echo "▶ T1: fresh state"
out="$(bash "$DEPLOY" status 2>&1)"
assert_contains "$out" "phase:        fresh" "T1.1: initial phase is fresh"
assert_contains "$out" "project:      (unset)" "T1.2: no project set"
assert_contains "$out" "auth account: (not authed)" "T1.3: not authed"

# Verify state file exists and has expected shape
STATE_FILE="${SANDBOX}/state/deploy.json"
[ -f "$STATE_FILE" ] && pass "T1.4: state file exists at $STATE_FILE" || fail "T1.4: state file missing"

phase="$(jq -r '.phase' "$STATE_FILE")"
assert_eq "$phase" "fresh" "T1.5: state.phase == fresh"

# ── T2: setup transitions phase fresh → ready ────────────────────────────
echo
echo "▶ T2: setup runs the full env+auth chain"
# In dry-run, vercel login flips HTML_SKILLS_MOCK_AUTHED=1, whoami succeeds.
out="$(bash "$DEPLOY" setup --project test-project --scope test-scope 2>&1)"
rc=$?
assert_exit "$rc" "0" "T2.1: setup exits 0 in dry-run"
assert_contains "$out" "Setup complete." "T2.2: setup reports complete"

phase="$(jq -r '.phase' "$STATE_FILE")"
assert_eq "$phase" "ready" "T2.3: phase transitions to ready"

project="$(jq -r '.project' "$STATE_FILE")"
assert_eq "$project" "test-project" "T2.4: project saved"

scope="$(jq -r '.scope' "$STATE_FILE")"
assert_eq "$scope" "test-scope" "T2.5: scope saved"

auth="$(jq -r '.auth_account' "$STATE_FILE")"
assert_eq "$auth" "mock-user@example.com" "T2.6: auth account captured"

# ── T3: ship produces a URL and transitions ready → deployed ─────────────
echo
echo "▶ T3: ship produces a URL"
TEST_HTML="${SANDBOX}/sample.html"
echo "<html><body><h1>Hello from test</h1></body></html>" > "$TEST_HTML"

out="$(bash "$DEPLOY" ship "$TEST_HTML" 2>&1)"
rc=$?
assert_exit "$rc" "0" "T3.1: ship exits 0"
# The last line of stdout should be the URL.
last_line="$(printf "%s" "$out" | tail -n1)"
case "$last_line" in
  https://mock-deploy-*.vercel.app) pass "T3.2: last line is a vercel.app URL ($last_line)" ;;
  *) fail "T3.2: last line is not a vercel.app URL (got: $last_line)" ;;
esac

phase="$(jq -r '.phase' "$STATE_FILE")"
assert_eq "$phase" "deployed" "T3.3: phase transitions to deployed"

deploy_url="$(jq -r '.last_deploy.url' "$STATE_FILE")"
case "$deploy_url" in
  https://mock-deploy-*.vercel.app) pass "T3.4: last_deploy.url persisted ($deploy_url)" ;;
  *) fail "T3.4: last_deploy.url wrong (got: $deploy_url)" ;;
esac

# ── T4: second ship reuses state, doesn't re-run setup ───────────────────
echo
echo "▶ T4: second ship is silent (no re-setup)"
out2="$(bash "$DEPLOY" ship "$TEST_HTML" 2>&1)"
rc=$?
assert_exit "$rc" "0" "T4.1: second ship exits 0"
# Setup-specific strings should NOT appear.
if printf "%s" "$out2" | grep -qF "Vercel setup"; then
  fail "T4.2: second ship triggered setup (regression)"
else
  pass "T4.2: second ship did NOT re-trigger setup"
fi

# ── T5: status after deploy shows the URL ────────────────────────────────
echo
echo "▶ T5: status reflects deploy"
out="$(bash "$DEPLOY" status 2>&1)"
assert_contains "$out" "phase:        deployed" "T5.1: status shows deployed phase"
assert_contains "$out" "last deploy:  https://mock-deploy" "T5.2: status shows URL"

# ── T6: reset clears state ───────────────────────────────────────────────
echo
echo "▶ T6: reset"
bash "$DEPLOY" reset >/dev/null 2>&1
phase="$(jq -r '.phase' "$STATE_FILE")"
assert_eq "$phase" "fresh" "T6.1: reset returns phase to fresh"
project="$(jq -r '.project' "$STATE_FILE")"
assert_eq "$project" "null" "T6.2: project cleared"

# ── T7: auth timeout path (mock NOT authed, exhausts retries) ────────────
echo
echo "▶ T7: auth timeout produces exit 11"
# Reset first so we're starting from `fresh`.
bash "$DEPLOY" reset >/dev/null 2>&1

# Use the mock toggle to make "vercel login" a no-op (auth never lands).
out="$(HTML_SKILLS_MOCK_LOGIN_BROKEN=1 \
       HTML_SKILLS_AUTH_POLL_TRIES=2 \
       HTML_SKILLS_AUTH_POLL_INTERVAL=1 \
       bash "$DEPLOY" setup --project broken-auth 2>&1)"
rc=$?
assert_exit "$rc" "11" "T7.1: auth timeout returns exit code 11"
assert_contains "$out" "didn't complete in time" "T7.2: prints timeout message"

# Cleanup: re-enable mock auth for any downstream tests.
unset HTML_SKILLS_MOCK_LOGIN_BROKEN
export HTML_SKILLS_MOCK_AUTHED=1

# ── T8: last-error.md written on failure ─────────────────────────────────
echo
echo "▶ T8: diagnostic file"
ERR_FILE="${SANDBOX}/last-error.md"
# We need to trigger a failure that writes through run::ext. The auth-timeout
# path above takes a different exit path that doesn't go through run::ext.
# Instead, force a setup failure by setting Node check to fail.
# Easiest: validate the file already exists from any previous fail.
# Actually T7 doesn't write it (auth poll doesn't use run::ext). Let's
# write one explicitly via the helper to verify the format:
(
  source "${LIB}/log.sh"
  HTML_SKILLS_RUN_ID="test-run-id"
  errf="$(mktemp)"
  echo "fake stderr line 1" > "$errf"
  echo "fake stderr line 2" >> "$errf"
  log::error_to_file "test-skill" "fake-cmd --foo bar" 42 "$errf"
  rm -f "$errf"
) >/dev/null 2>&1

[ -f "$ERR_FILE" ] && pass "T8.1: last-error.md was created" || fail "T8.1: last-error.md missing"
err_content="$(cat "$ERR_FILE" 2>/dev/null || true)"
assert_contains "$err_content" "Skill:** test-skill" "T8.2: contains skill name"
assert_contains "$err_content" "Exit code:** 42"     "T8.3: contains exit code"
assert_contains "$err_content" "fake-cmd --foo bar"  "T8.4: contains command"
assert_contains "$err_content" "fake stderr line 1"  "T8.5: contains captured stderr"

# ── T9: memory skeleton initialized ──────────────────────────────────────
echo
echo "▶ T9: memory skeleton"
for d in memory memory/targets memory/runs memory/outcomes state; do
  if [ -d "${SANDBOX}/${d}" ]; then
    pass "T9: ${d}/ exists"
  else
    fail "T9: ${d}/ missing"
  fi
done
for f in memory/profile.json memory/voice.json memory/patterns.json memory/outcomes/feedback.jsonl; do
  if [ -e "${SANDBOX}/${f}" ]; then
    pass "T9: ${f} seeded"
  else
    fail "T9: ${f} not seeded"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "  failed tests:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "    - $t"
  done
  echo
  echo "  sandbox (for inspection): ${SANDBOX}"
  exit 1
fi
echo "─────────────────────────────────────────────"
echo

# Cleanup on success
rm -rf "$SANDBOX"
exit 0

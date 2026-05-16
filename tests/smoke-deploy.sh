#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/smoke-deploy.sh
#  REAL Vercel deploy + verify + teardown.
#  Only run this when you want a true end-to-end production sanity check.
#
#  Requires:
#    - vercel CLI installed and authed (run: vercel login)
#    - jq
#    - curl
#    - VERCEL_SMOKE_PROJECT env var with a throwaway project name
#      (e.g. export VERCEL_SMOKE_PROJECT=html-skills-smoke)
#
#  Run from repo root:    bash tests/smoke-deploy.sh
#  Exit 0 on success.
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
DEPLOY="${LIB}/deploy.sh"

# Sandbox cache.
SANDBOX="$(mktemp -d -t htmlskills-smoke.XXXXXX)"
export HTML_SKILLS_CACHE="${SANDBOX}"
export HTML_SKILLS_LIB="${LIB}"
export HTML_SKILLS_NO_OPEN=1
# Real run — DO NOT set DRY_RUN.

PASS=0
FAIL=0

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }

cleanup() {
  echo
  echo "▶ Cleanup"
  if [ -n "${DEPLOYED_URL:-}" ]; then
    # Attempt to delete the deployment via vercel rm.
    local proj
    proj="${VERCEL_SMOKE_PROJECT:-}"
    if [ -n "$proj" ]; then
      if vercel remove "$proj" --yes --safe 2>/dev/null; then
        pass "Cleaned up project $proj"
      else
        printf "  \033[33m!\033[0m Manual cleanup may be needed: vercel remove %s --yes\n" "$proj"
      fi
    fi
  fi
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

echo
echo "▶ html-skills deploy.sh production smoke test"
echo "  sandbox: ${SANDBOX}"
echo

# ── Pre-flight ───────────────────────────────────────────────────────────
if ! command -v vercel >/dev/null 2>&1; then
  fail "vercel CLI not installed. Skipping smoke test."
  exit 1
fi
if ! vercel whoami >/dev/null 2>&1; then
  fail "vercel CLI not authed. Run: vercel login"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  fail "jq not installed."
  exit 1
fi
if [ -z "${VERCEL_SMOKE_PROJECT:-}" ]; then
  fail "Set VERCEL_SMOKE_PROJECT to a throwaway project name."
  exit 1
fi

WHO="$(vercel whoami 2>/dev/null)"
pass "Authed as $WHO"

# ── Build a recognizable sample page ─────────────────────────────────────
STAMP="$(date -u +%Y%m%d%H%M%S)"
SAMPLE="${SANDBOX}/smoke-${STAMP}.html"
cat > "$SAMPLE" <<HTML
<!doctype html>
<html><head><meta charset="utf-8"><title>html-skills smoke ${STAMP}</title></head>
<body><h1>html-skills smoke test</h1><p>stamp: ${STAMP}</p></body></html>
HTML
pass "Wrote sample page: $SAMPLE"

# ── Ship ─────────────────────────────────────────────────────────────────
echo
echo "▶ Deploying $SAMPLE …"
SHIP_OUT="$(bash "$DEPLOY" ship "$SAMPLE" --project "$VERCEL_SMOKE_PROJECT" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "ship exited $rc"
  printf "%s\n" "$SHIP_OUT" | sed 's/^/    /'
  exit 1
fi

DEPLOYED_URL="$(printf "%s" "$SHIP_OUT" | tail -n1)"
case "$DEPLOYED_URL" in
  https://*) pass "Got URL: $DEPLOYED_URL" ;;
  *) fail "Bad URL on stdout: $DEPLOYED_URL"; exit 1 ;;
esac

# ── Verify reachability + stamp present ──────────────────────────────────
echo
echo "▶ Verifying $DEPLOYED_URL responds"
# Vercel propagation can be a couple seconds; retry up to 6 times.
for i in 1 2 3 4 5 6; do
  body="$(curl -fsSL "$DEPLOYED_URL" 2>/dev/null || true)"
  if printf "%s" "$body" | grep -qF "stamp: ${STAMP}"; then
    pass "Page reachable + correct stamp"
    break
  fi
  if [ "$i" = "6" ]; then
    fail "Page did not return expected stamp after 6 tries"
    echo "    response body (truncated):"
    printf "%s" "$body" | head -c 400 | sed 's/^/    /'
    exit 1
  fi
  sleep 2
done

# ── Verify state ─────────────────────────────────────────────────────────
echo
phase="$(jq -r '.phase' "${SANDBOX}/state/deploy.json")"
[ "$phase" = "deployed" ] && pass "state.phase == deployed" || fail "phase is $phase, expected deployed"

stored_url="$(jq -r '.last_deploy.url' "${SANDBOX}/state/deploy.json")"
[ "$stored_url" = "$DEPLOYED_URL" ] && pass "state.last_deploy.url matches stdout" || fail "URL mismatch"

# ── Summary ──────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
[ "$FAIL" -gt 0 ] && exit 1
echo "─────────────────────────────────────────────"
echo
exit 0

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/lint-js.sh — parse-check JS files we ship
#  Catches syntax errors in track.js / track-server.js before they go live.
#  Uses node --check (no execution, no side effects).
#  Skipped with a warning (not a failure) if node isn't installed.
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }

echo
echo "▶ JS parse check"

if ! command -v node >/dev/null 2>&1; then
  printf "  \033[33m!\033[0m node not installed — skipping JS lint (CI must have node)\n"
  exit 0
fi
NODE_VERSION="$(node --version 2>/dev/null)"
echo "  node: ${NODE_VERSION}"

# Files we want to parse-check.
JS_FILES=(
  "shared/components/track.js"
  "shared/components/track-server.js"
)

for f in "${JS_FILES[@]}"; do
  path="${REPO_ROOT}/${f}"
  if [ ! -f "$path" ]; then
    fail "${f}: file missing"
    continue
  fi

  # `node --check` syntax-checks without executing. For ESM (track-server.js
  # uses `import { kv } from '@vercel/kv'`), node insists on a recognized
  # module type — supplying  --input-type=module  via stdin is the most
  # portable way to syntax-check an ESM file without writing package.json.
  case "$f" in
    *track-server.js)
      # ESM module syntax check (import keyword present).
      if node --input-type=module --check < "$path" 2>/tmp/lint-js.err; then
        pass "${f} parses as ESM"
      else
        fail "${f} parse error: $(head -n1 /tmp/lint-js.err)"
      fi
      ;;
    *)
      # Classic script syntax check.
      if node --check "$path" 2>/tmp/lint-js.err; then
        pass "${f} parses as classic script"
      else
        fail "${f} parse error: $(head -n1 /tmp/lint-js.err)"
      fi
      ;;
  esac
done

# Extra defensive check: track.js must not contain TODO/FIXME/console.log
# (the latter would leak from deployed pages).
if [ -f "${REPO_ROOT}/shared/components/track.js" ]; then
  if grep -Eq '\b(TODO|FIXME)\b' "${REPO_ROOT}/shared/components/track.js"; then
    fail "track.js: leftover TODO/FIXME markers"
  else
    pass "track.js: no TODO/FIXME markers"
  fi
  if grep -Eq 'console\.(log|warn|error|debug)' "${REPO_ROOT}/shared/components/track.js"; then
    fail "track.js: contains console.* calls (would noise up users' devtools)"
  else
    pass "track.js: no console.* calls"
  fi
fi

# track.js must declare strict mode and an IIFE wrapper.
if [ -f "${REPO_ROOT}/shared/components/track.js" ]; then
  if grep -Fq "'use strict'" "${REPO_ROOT}/shared/components/track.js"; then
    pass "track.js: 'use strict' present"
  else
    fail "track.js: missing 'use strict'"
  fi
  # IIFE may be anywhere after the doc comment — check the whole file.
  if grep -Eq '^\s*\(function\s*\(' "${REPO_ROOT}/shared/components/track.js"; then
    pass "track.js: IIFE wrapper present (scoped, won't pollute globals)"
  else
    fail "track.js: no IIFE wrapper detected"
  fi
fi

# track-server.js must clamp every string field. Smoke check.
if [ -f "${REPO_ROOT}/shared/components/track-server.js" ]; then
  if grep -Fq '.slice(' "${REPO_ROOT}/shared/components/track-server.js"; then
    pass "track-server.js: .slice() length-caps present"
  else
    fail "track-server.js: missing .slice() length caps (defensive limits)"
  fi
fi

rm -f /tmp/lint-js.err

echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo; echo "  failed:"; for t in "${FAILED[@]}"; do echo "    - $t"; done
  exit 1
fi
echo "─────────────────────────────────────────────"

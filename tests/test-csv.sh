#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-csv.sh
#  Offline tests for shared/lib/csv.sh.
#  Requires python3 + jq.
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
SANDBOX="$(mktemp -d -t htmlskills-csv.XXXXXX)"

export HTML_SKILLS_LIB="${LIB}"
export NO_COLOR=1

# shellcheck source=/dev/null
. "${LIB}/log.sh"
# shellcheck source=/dev/null
. "${LIB}/csv.sh"

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3 (got '$1')"
  else fail "$3 (expected '$2', got '$1')"; fi
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required for these tests."; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required."; exit 1
fi

echo
echo "▶ csv.sh tests"
echo "  sandbox: $SANDBOX"

# ── T1: simple CSV ───────────────────────────────────────────────────────
echo
echo "▶ T1: simple CSV"
SIMPLE="$SANDBOX/simple.csv"
cat > "$SIMPLE" <<'CSV'
name,company,linkedin
John Smith,Acme Corp,https://linkedin.com/in/johnsmith
Sarah Lee,Beam Inc,https://linkedin.com/in/sarahlee
CSV

if csv::validate "$SIMPLE"; then pass "T1.1: validate ok"; else fail "T1.1: validate failed"; fi

count="$(csv::count "$SIMPLE")"
assert_eq "$count" "2" "T1.2: count == 2"

header="$(csv::header "$SIMPLE")"
assert_eq "$(echo "$header" | jq -r '.[0]')" "name"     "T1.3: header[0] == name"
assert_eq "$(echo "$header" | jq -r '.[2]')" "linkedin" "T1.4: header[2] == linkedin"

row1="$(csv::row "$SIMPLE" 1)"
assert_eq "$(echo "$row1" | jq -r '.name')" "John Smith" "T1.5: row1.name"
assert_eq "$(echo "$row1" | jq -r '.company')" "Acme Corp" "T1.6: row1.company"

lines="$(csv::parse "$SIMPLE" | wc -l | tr -d ' ')"
assert_eq "$lines" "2" "T1.7: parse emits 2 jsonl rows"

# ── T2: quoted fields with embedded commas ───────────────────────────────
echo
echo "▶ T2: quoted commas"
QUOTED="$SANDBOX/quoted.csv"
cat > "$QUOTED" <<'CSV'
name,title,company
"Smith, John","CEO, Founder","Acme, Inc"
"Lee","CTO","Beam"
CSV

if csv::validate "$QUOTED"; then pass "T2.1: validate ok"; else fail "T2.1: validate failed"; fi
row1="$(csv::row "$QUOTED" 1)"
assert_eq "$(echo "$row1" | jq -r '.name')"    "Smith, John"    "T2.2: comma inside quoted name preserved"
assert_eq "$(echo "$row1" | jq -r '.title')"   "CEO, Founder"   "T2.3: comma inside title preserved"
assert_eq "$(echo "$row1" | jq -r '.company')" "Acme, Inc"      "T2.4: comma inside company preserved"

# ── T3: escaped quotes ────────────────────────────────────────────────────
echo
echo "▶ T3: escaped quotes (RFC 4180 doubled-double-quote)"
ESC="$SANDBOX/escaped.csv"
cat > "$ESC" <<'CSV'
name,quote
John,"He said ""hello"" loud"
CSV

if csv::validate "$ESC"; then pass "T3.1: validate ok"; else fail "T3.1: validate failed"; fi
row1="$(csv::row "$ESC" 1)"
expected='He said "hello" loud'
got="$(echo "$row1" | jq -r '.quote')"
assert_eq "$got" "$expected" "T3.2: escaped quote unwrapped"

# ── T4: BOM + UTF-8 ──────────────────────────────────────────────────────
echo
echo "▶ T4: UTF-8 BOM + non-ASCII"
BOM="$SANDBOX/bom.csv"
# Write BOM bytes + content
printf '\xef\xbb\xbfname,company\nJané,Café\n' > "$BOM"
header="$(csv::header "$BOM")"
assert_eq "$(echo "$header" | jq -r '.[0]')" "name" "T4.1: BOM stripped from first header"
row1="$(csv::row "$BOM" 1)"
assert_eq "$(echo "$row1" | jq -r '.name')"    "Jané" "T4.2: utf-8 name preserved"
assert_eq "$(echo "$row1" | jq -r '.company')" "Café" "T4.3: utf-8 company preserved"

# ── T5: detect_field (case-insensitive substring) ────────────────────────
echo
echo "▶ T5: detect_field"
DET="$SANDBOX/detect.csv"
cat > "$DET" <<'CSV'
Full Name,Email Address,LinkedIn URL,Company Name
Test,t@t.co,https://linkedin.com/in/test,Test
CSV
assert_eq "$(csv::detect_field "$DET" linkedin)"  "LinkedIn URL"  "T5.1: detect linkedin"
assert_eq "$(csv::detect_field "$DET" email)"     "Email Address" "T5.2: detect email"
assert_eq "$(csv::detect_field "$DET" name)"      "Full Name"     "T5.3: 'name' matches Full Name first (left-to-right)"
assert_eq "$(csv::detect_field "$DET" website url)" "LinkedIn URL" "T5.4: fallback to second needle"
csv::detect_field "$DET" nonexistent >/dev/null 2>&1 && fail "T5.5: should fail on missing" || pass "T5.5: missing → exit non-zero"

# ── T6: empty CSV + header-only ──────────────────────────────────────────
echo
echo "▶ T6: edge cases"
EMPTY="$SANDBOX/empty.csv"
: > "$EMPTY"
if csv::validate "$EMPTY" >/dev/null 2>&1; then fail "T6.1: empty CSV should fail validate"; else pass "T6.1: empty CSV fails validate"; fi

HEADER_ONLY="$SANDBOX/header-only.csv"
echo "name,company" > "$HEADER_ONLY"
if csv::validate "$HEADER_ONLY"; then pass "T6.2: header-only validates"; else fail "T6.2: header-only should validate"; fi
count="$(csv::count "$HEADER_ONLY")"
assert_eq "$count" "0" "T6.3: header-only count == 0"

# ── T7: empty cells become empty strings, not null ───────────────────────
echo
echo "▶ T7: empty cells"
SPARSE="$SANDBOX/sparse.csv"
cat > "$SPARSE" <<'CSV'
name,company,linkedin
John,,
,Beam,https://linkedin.com/in/whoever
CSV
row1="$(csv::row "$SPARSE" 1)"
assert_eq "$(echo "$row1" | jq -r '.company')" ""  "T7.1: empty cell → empty string"
assert_eq "$(echo "$row1" | jq -r '.company | type')" "string" "T7.2: type is string, not null"

# ── T8: multi-line quoted field ──────────────────────────────────────────
echo
echo "▶ T8: multi-line quoted field"
ML="$SANDBOX/ml.csv"
cat > "$ML" <<'CSV'
name,bio
John,"Founder of Acme.
Previously at Stripe."
CSV
if csv::validate "$ML"; then pass "T8.1: multi-line validates"; else fail "T8.1: multi-line should validate"; fi
row1="$(csv::row "$ML" 1)"
got="$(echo "$row1" | jq -r '.bio')"
case "$got" in
  *"Previously at Stripe"*) pass "T8.2: newline preserved in quoted field" ;;
  *) fail "T8.2: newline lost (got: $got)" ;;
esac

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
echo
rm -rf "$SANDBOX"
exit 0

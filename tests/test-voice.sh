#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/test-voice.sh — offline tests for shared/lib/voice.sh
#  Seeds realistic run records with text samples and asserts the
#  distilled voice.json + style_directive + tone_summary behave correctly.
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/shared/lib"
SANDBOX="$(mktemp -d -t htmlskills-voice.XXXXXX)"

export HTML_SKILLS_LIB="${LIB}"
export HTML_SKILLS_CACHE="${SANDBOX}"
export NO_COLOR=1

# shellcheck source=/dev/null
. "${LIB}/log.sh"
# shellcheck source=/dev/null
. "${LIB}/memory.sh"
# shellcheck source=/dev/null
. "${LIB}/voice.sh"

memory::init

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3 (got '$1')"; else fail "$3 (expected '$2', got '$1')"; fi }
assert_ne() { if [ "$1" != "$2" ]; then pass "$3"; else fail "$3 (expected NOT '$2', got '$1')"; fi }

command -v jq      >/dev/null 2>&1 || { echo "jq required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 1; }

VF="$(memory::root)/memory/voice.json"

echo
echo "▶ voice.sh tests"
echo "  sandbox: ${SANDBOX}"

# ── Helper: seed a run with text samples ─────────────────────────────────
seed_run_text() {
  local rid="$1" dm="$2" hero="$3" trojan="$4" started="$5"
  jq -nc \
    --arg rid "$rid" --arg dm "$dm" --arg hero "$hero" \
    --arg trojan "$trojan" --arg started "$started" \
    '{
      run_id:$rid, skill:"outreach-html",
      started_at:$started,
      dm_text:$dm, hero_text:$hero, trojan_text:$trojan
    }' > "$(memory::root)/memory/runs/${rid}.json"
}

# ── T1: empty memory → voice.json with zero samples ──────────────────────
echo
echo "▶ T1: empty memory"
voice::consolidate >/dev/null 2>&1
[ -f "$VF" ] && pass "T1.1: voice.json created" || fail "T1.1: voice.json missing"
assert_eq "$(jq -r '.runs_analyzed' "$VF")" "0" "T1.2: 0 runs analyzed"
assert_eq "$(jq -r '.dm_samples' "$VF")"    "0" "T1.3: 0 DM samples"
assert_eq "$(jq -r '.tone_signals.avg_sentence_words_dm' "$VF")" "null" "T1.4: avg_sentence null"

# Style directive should be empty (no data).
sd="$(voice::style_directive 2>/dev/null)"
assert_eq "$sd" "" "T1.5: style_directive empty when no data"

# Tone summary should also be empty.
ts="$(voice::tone_summary 2>/dev/null)"
assert_eq "$ts" "" "T1.6: tone_summary empty when no data"

# ── T2: seed a few runs, sentence stats compute correctly ────────────────
echo
echo "▶ T2: sentence + word stats from seeded DMs"
seed_run_text "r1" \
  "Saw you hiring SDRs. Built a quick page on what that could look like with code. Take a look." \
  "Three SDRs to do what code does in an afternoon." \
  "You are about to spend 400k a year on humans doing what your founders showed could be code." \
  "2026-05-17T12:00:00Z"

seed_run_text "r2" \
  "Saw the Series A. Built you a 90-second page on scale without headcount. Worth your time." \
  "Scale outreach. Not the headcount." \
  "What if your next ten reps could be one engineer plus this page?" \
  "2026-05-16T12:00:00Z"

seed_run_text "r3" \
  "Quick one — saw your Greenhouse post for three SDRs. Built you a tighter alternative. 90 seconds." \
  "Hire your next ten reps once. Use them forever." \
  "Your ICP knows you are coming before you arrive — automate the part that scales." \
  "2026-05-15T12:00:00Z"

voice::consolidate >/dev/null 2>&1

assert_eq "$(jq -r '.dm_samples' "$VF")"     "3" "T2.1: 3 DM samples"
assert_eq "$(jq -r '.hero_samples' "$VF")"   "3" "T2.2: 3 hero samples"
assert_eq "$(jq -r '.trojan_samples' "$VF")" "3" "T2.3: 3 trojan samples"

# avg_sentence_words_dm should be positive number around 8-12.
avg_sent="$(jq -r '.tone_signals.avg_sentence_words_dm' "$VF")"
assert_ne "$avg_sent" "null" "T2.4: avg_sentence_words_dm not null"
case "$avg_sent" in
  0|0.0) fail "T2.5: avg_sentence > 0 (got $avg_sent)" ;;
  *)     pass "T2.5: avg_sentence > 0 (got $avg_sent)" ;;
esac

# avg_dm_words should be positive.
avg_dm="$(jq -r '.tone_signals.avg_dm_words' "$VF")"
case "$avg_dm" in
  0|0.0|null) fail "T2.6: avg_dm_words > 0 (got $avg_dm)" ;;
  *)          pass "T2.6: avg_dm_words > 0 (got $avg_dm)" ;;
esac

# avg_hero_words should be smaller than avg_dm (heros are short).
avg_hero="$(jq -r '.tone_signals.avg_hero_words' "$VF")"
case "$avg_hero" in
  0|0.0|null) fail "T2.7: avg_hero > 0" ;;
  *)          pass "T2.7: avg_hero > 0 (got $avg_hero)" ;;
esac

# ── T3: preferred opener detection ───────────────────────────────────────
echo
echo "▶ T3: openers"
# Two of three DMs start with "saw" — should be a preferred opener.
prefs="$(jq -r '.openers.preferred[]?' "$VF" | tr '\n' '|')"
case "$prefs" in
  *saw*) pass "T3.1: 'saw' detected as preferred opener (full: $prefs)" ;;
  *)     fail "T3.1: 'saw' not detected (got: $prefs)" ;;
esac

# ── T4: style_directive emits non-empty when data exists ─────────────────
echo
echo "▶ T4: style_directive output"
sd="$(voice::style_directive)"
[ -n "$sd" ] && pass "T4.1: style_directive non-empty with data" || fail "T4.1: still empty"

case "$sd" in
  *"sentence"*|*"words"*) pass "T4.2: directive mentions sentence/word counts" ;;
  *) fail "T4.2: directive missing key signals (got: $sd)" ;;
esac

# Should contain at least one opener phrase.
case "$sd" in
  *"Open DMs with"*) pass "T4.3: directive mentions openers" ;;
  *) fail "T4.3: directive missing openers section" ;;
esac

# ── T5: tone_summary one-liner ───────────────────────────────────────────
echo
echo "▶ T5: tone_summary"
ts="$(voice::tone_summary)"
[ -n "$ts" ] && pass "T5.1: tone_summary non-empty" || fail "T5.1: empty"
case "$ts" in
  *"w/sent"*) pass "T5.2: summary mentions w/sent" ;;
  *) fail "T5.2: summary missing w/sent ($ts)" ;;
esac

# ── T6: time-decay weighting — older run with extreme outlier weights less ─
echo
echo "▶ T6: time-decay weighting"
# Add an OLD run (90 days back) with very long DM. It should be dampened
# relative to the recent runs.
old_ts="$(date -u -v-90d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)"
seed_run_text "r-old" \
  "Hello there. I hope this finds you well. I wanted to reach out about a really exciting opportunity that I believe could be incredibly beneficial for your business and team. Would love to set up a quick chat at your convenience to discuss further." \
  "An exciting opportunity for your business and team." \
  "" \
  "$old_ts"

# Consolidate with default 30-day half-life.
voice::consolidate >/dev/null 2>&1
avg_dm_with_old="$(jq -r '.tone_signals.avg_dm_words' "$VF")"

# With NO decay (huge half-life), the old run would dominate.
voice::consolidate --half-life 9999 >/dev/null 2>&1
avg_dm_no_decay="$(jq -r '.tone_signals.avg_dm_words' "$VF")"

# Compare — decayed should be SMALLER than no-decay (old long DM dampened).
result="$(python3 -c "
a = float('$avg_dm_with_old')
b = float('$avg_dm_no_decay')
print('ok' if a < b else 'bad')
")"
assert_eq "$result" "ok" "T6.1: decayed avg < no-decay avg (old outlier dampened)"

# ── T7: voice_corrections flow through ───────────────────────────────────
echo
echo "▶ T7: voice_corrections honored"
# Add a run with explicit corrections.
jq -nc '{
  run_id:"r-corrections", skill:"outreach-html",
  started_at:"2026-05-17T12:00:00Z",
  voice_corrections:[
    {kind:"avoid_word", text:"leverage"},
    {kind:"rejected_opener", text:"i hope this finds you well"}
  ]
}' > "$(memory::root)/memory/runs/r-corrections.json"

voice::consolidate >/dev/null 2>&1
avoids="$(jq -r '.vocabulary.avoid | join(",")' "$VF")"
case "$avoids" in
  *leverage*) pass "T7.1: 'leverage' in vocabulary.avoid" ;;
  *) fail "T7.1: vocabulary.avoid missing 'leverage' (got: $avoids)" ;;
esac

rejecteds="$(jq -r '.openers.rejected | join("|")' "$VF")"
case "$rejecteds" in
  *"i hope this finds you well"*) pass "T7.2: opener 'i hope...' in rejected" ;;
  *) fail "T7.2: openers.rejected missing (got: $rejecteds)" ;;
esac

# ── T8: auto_consolidate freshness ───────────────────────────────────────
echo
echo "▶ T8: auto_consolidate freshness"
last_before="$(jq -r '.last_consolidated' "$VF")"
sleep 1
voice::auto_consolidate 7 >/dev/null 2>&1
last_after="$(jq -r '.last_consolidated' "$VF")"
assert_eq "$last_after" "$last_before" "T8.1: auto_consolidate skipped (fresh)"

voice::auto_consolidate 0 >/dev/null 2>&1
last_after="$(jq -r '.last_consolidated' "$VF")"
assert_ne "$last_after" "$last_before" "T8.2: auto_consolidate WITH 0-day window did rerun"

# ── T9: reset preserves previous ─────────────────────────────────────────
echo
echo "▶ T9: reset"
voice::reset >/dev/null 2>&1
content="$(cat "$VF")"
assert_eq "$content" "{}" "T9.1: voice.json cleared (= {})"
PREV="$(memory::root)/memory/voice.previous.json"
[ -f "$PREV" ] && pass "T9.2: voice.previous.json preserved" || fail "T9.2: previous missing"

# ── T10: degrades gracefully when runs have no text samples ──────────────
echo
echo "▶ T10: graceful degradation"
rm -f "$(memory::root)/memory/runs/"*.json
# Seed a run with NO text fields.
jq -nc '{run_id:"r-bare", skill:"outreach-html", started_at:"2026-05-17T12:00:00Z"}' \
  > "$(memory::root)/memory/runs/r-bare.json"
voice::consolidate >/dev/null 2>&1
assert_eq "$(jq -r '.dm_samples' "$VF")" "0" "T10.1: 0 DM samples (no text in run)"
# style_directive should be empty (no usable signals).
sd="$(voice::style_directive 2>/dev/null)"
assert_eq "$sd" "" "T10.2: style_directive empty when no text"

# ── Summary ──────────────────────────────────────────────────────────────
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

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / voice.sh
#  Learn the user WRITING voice from text samples in run records.
#  Distills sentence rhythm, openers, vocabulary, and punctuation
#  signature into ~/.cache/html-skills/memory/voice.json.
#
#  This is the layer that closes the system-learns-from-YOU gap.
#  patterns.sh learns about targets and angles; voice.sh learns about
#  how YOU write.
#
#  Source it:  . "$HTML_SKILLS_LIB/voice.sh"
#
#  Run records are scanned for these optional text fields:
#    dm_text          the suggested LinkedIn DM (1-3 sentences)
#    hero_text        the page hero headline
#    trojan_text      the trojan-horse one-liner
#    draft_text       flat-concatenated drafted prose (optional)
#    shipped_text     flat-concatenated prose that survived (optional)
#
#  Skills that emit none of these contribute nothing to voice signals.
#  voice.json degrades gracefully. (No errors, no warnings.)
#
#  Time-decay weighting: recent runs count more. Half-life default 30
#  days; configurable via --half-life.
#
#  Public functions:
#    voice::consolidate [--half-life N]    rebuild voice.json
#    voice::auto_consolidate [stale_days]  no-op if voice.json is fresh
#                                           (default 14 days)
#    voice::report                         human-readable summary
#    voice::style_directive                short paragraph of style
#                                           guidance for skill drafting.
#                                           Echoes EMPTY when no data.
#    voice::tone_summary                   one-line tone summary
#    voice::reset                          wipe voice.json
#
#  Implementation note: most of the heavy lifting is in
#  shared/lib/voice_consolidate.py — the heredoc pattern that patterns.sh
#  uses trips bash 3.2 quote-tracking when text-analysis code includes
#  the apostrophes and parens needed for natural-language work. We keep
#  the python in its own file so the shell wrapper stays parseable on
#  every macOS bash.
# ──────────────────────────────────────────────────────────────────────────

if [ -n "${__HTML_SKILLS_VOICE_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_VOICE_LOADED=1

if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HTML_SKILLS_LIB
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/memory.sh"

memory::init

voice::__file()          { printf "%s\n" "$(memory::root)/memory/voice.json"; }
voice::__previous_file() { printf "%s\n" "$(memory::root)/memory/voice.previous.json"; }
voice::__consolidate_py() { printf "%s\n" "${HTML_SKILLS_LIB}/voice_consolidate.py"; }

# ─────────────────────────────────────────────────────────────────────────
#  Consolidate — invoke the python distiller, write voice.json atomically.
# ─────────────────────────────────────────────────────────────────────────
voice::consolidate() {
  command -v python3 >/dev/null 2>&1 || { log::fail "python3 required"; return 10; }
  command -v jq      >/dev/null 2>&1 || { log::fail "jq required";      return 10; }

  local half_life=30
  while [ $# -gt 0 ]; do
    case "$1" in
      --half-life) half_life="$2"; shift 2 ;;
      *) log::fail "Unknown flag: $1"; return 2 ;;
    esac
  done

  local root vf prev py
  root="$(memory::root)"
  vf="$(voice::__file)"
  prev="$(voice::__previous_file)"
  py="$(voice::__consolidate_py)"

  if [ ! -f "$py" ]; then
    log::fail "voice_consolidate.py missing at $py"
    return 12
  fi

  # Rotate current -> previous for future drift work.
  if [ -f "$vf" ] && [ "$(cat "$vf" 2>/dev/null)" != "{}" ]; then
    cp "$vf" "$prev"
  fi

  log::info "Distilling voice from runs (half-life: ${half_life}d) ..."

  local out
  if ! out="$(python3 "$py" "$root" "$half_life")"; then
    log::fail "voice consolidation failed"
    return 1
  fi

  local tmp="${vf}.tmp.$$"
  printf "%s" "$out" > "$tmp" && mv "$tmp" "$vf"

  local dm_n hero_n
  dm_n="$(jq -r '.dm_samples' "$vf")"
  hero_n="$(jq -r '.hero_samples' "$vf")"
  log::ok "Voice distilled - ${dm_n} DM sample(s), ${hero_n} hero sample(s)."
}

# ─────────────────────────────────────────────────────────────────────────
#  Auto-consolidate (no-op if fresh)
# ─────────────────────────────────────────────────────────────────────────
voice::auto_consolidate() {
  local stale_days="${1:-14}"
  local vf; vf="$(voice::__file)"
  if [ ! -f "$vf" ] || [ "$(cat "$vf" 2>/dev/null)" = "{}" ]; then
    voice::consolidate
    return $?
  fi
  command -v jq >/dev/null 2>&1 || return 0
  local last; last="$(jq -r '.last_consolidated // empty' "$vf")"
  if [ -z "$last" ]; then voice::consolidate; return $?; fi

  command -v python3 >/dev/null 2>&1 || return 0
  local fresh
  fresh="$(python3 -c "
import sys, datetime as dt
last = dt.datetime.strptime(sys.argv[1].replace('Z',''), '%Y-%m-%dT%H:%M:%S').replace(tzinfo=dt.timezone.utc)
days = int(sys.argv[2])
delta = dt.datetime.now(dt.timezone.utc) - last
print('yes' if delta.days < days else 'no')
" "$last" "$stale_days")"
  if [ "$fresh" = "no" ]; then
    voice::consolidate
  fi
}

# ─────────────────────────────────────────────────────────────────────────
#  Reset
# ─────────────────────────────────────────────────────────────────────────
voice::reset() {
  local vf; vf="$(voice::__file)"
  echo '{}' > "$vf"
  log::ok "voice.json cleared (history preserved in voice.previous.json)."
}

# ─────────────────────────────────────────────────────────────────────────
#  Report — human-readable rollup (delegates to python for string-building)
# ─────────────────────────────────────────────────────────────────────────
voice::report() {
  command -v jq      >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local vf; vf="$(voice::__file)"
  if [ ! -f "$vf" ] || [ "$(cat "$vf")" = "{}" ]; then
    log::warn "No voice data yet. Run: voice.sh consolidate"
    return 0
  fi
  python3 -c "
import json, sys
v = json.load(open(sys.argv[1]))
def s(k, d=''): return v.get(k, d)
print('\n  voice report')
print('  last consolidated: ' + str(s('last_consolidated')))
print('  samples:           {} DMs, {} heros, {} trojans'.format(
    s('dm_samples', 0), s('hero_samples', 0), s('trojan_samples', 0)))
print()
print('  Tone signals:')
for k, val in (v.get('tone_signals') or {}).items():
    show = '-' if val is None else val
    print('    - {}: {}'.format(k, show))
print()
print('  Preferred openers:')
op = (v.get('openers') or {}).get('preferred') or []
if not op:
    print('    (not enough samples)')
else:
    for o in op: print('    - ' + o)
print()
print('  Words you use:')
voc = (v.get('vocabulary') or {}).get('use') or []
if not voc:
    print('    (not enough samples)')
else:
    for w in voc: print('    - ' + w)
print()
sig = v.get('punctuation_signature')
if sig:
    print('  Punctuation signature: ' + sig)
" "$vf"
}

# ─────────────────────────────────────────────────────────────────────────
#  Style directive — short paragraph of guidance for skill drafting.
#  Echoes empty when no usable data.
# ─────────────────────────────────────────────────────────────────────────
voice::style_directive() {
  command -v python3 >/dev/null 2>&1 || return 0
  local vf; vf="$(voice::__file)"
  if [ ! -f "$vf" ] || [ "$(cat "$vf")" = "{}" ]; then
    return 0
  fi
  python3 -c "
import json, sys
v = json.load(open(sys.argv[1]))
ts = v.get('tone_signals', {}) or {}
op = (v.get('openers') or {}).get('preferred') or []
voc_use = (v.get('vocabulary') or {}).get('use') or []
voc_av  = (v.get('vocabulary') or {}).get('avoid') or []
sig = v.get('punctuation_signature')

have_data = bool(op or voc_use or voc_av or sig or any(ts.get(k) for k in ts))
if not have_data: sys.exit(0)

lines = ['Match the user learned writing voice:']
def gi(k):
    return int(round(ts.get(k))) if ts.get(k) else None

if gi('avg_sentence_words_dm') is not None:
    lines.append('- Target ~' + str(gi('avg_sentence_words_dm')) + ' words per sentence in DMs.')
if gi('avg_dm_words') is not None:
    lines.append('- DMs are ~' + str(gi('avg_dm_words')) + ' words total (tight).')
if gi('avg_hero_words') is not None:
    lines.append('- Hero headlines: ~' + str(gi('avg_hero_words')) + ' words.')
if gi('avg_trojan_words') is not None:
    lines.append('- Trojan-horse one-liners: ~' + str(gi('avg_trojan_words')) + ' words.')
if op:
    lines.append('- Open DMs with phrasing like: ' + ', '.join(repr(o) for o in op[:3]) + '.')
if voc_use:
    lines.append('- Words the user actually uses: ' + ', '.join(voc_use[:6]) + '.')
if voc_av:
    lines.append('- Words to avoid: ' + ', '.join(voc_av[:6]) + '.')
if sig:
    lines.append('- Punctuation signature: ' + sig + '.')

print('\n'.join(lines))
" "$vf"
}

# ─────────────────────────────────────────────────────────────────────────
#  Tone summary — one-line, for dashboards / hand-back messages.
# ─────────────────────────────────────────────────────────────────────────
voice::tone_summary() {
  command -v python3 >/dev/null 2>&1 || return 0
  local vf; vf="$(voice::__file)"
  if [ ! -f "$vf" ] || [ "$(cat "$vf")" = "{}" ]; then return 0; fi
  python3 -c "
import json, sys
v = json.load(open(sys.argv[1]))
t = v.get('tone_signals') or {}
def g(k): return t.get(k)
parts = []
if g('avg_sentence_words_dm'): parts.append(str(int(g('avg_sentence_words_dm'))) + 'w/sent')
if g('avg_dm_words'):          parts.append(str(int(g('avg_dm_words'))) + 'w DMs')
if g('avg_hero_words'):        parts.append(str(int(g('avg_hero_words'))) + 'w heros')
sig = v.get('punctuation_signature')
if sig: parts.append(sig)
print(' . '.join(parts))
" "$vf"
}

# ─────────────────────────────────────────────────────────────────────────
#  CLI entrypoint
# ─────────────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-help}" in
    consolidate)        shift; voice::consolidate "$@" ;;
    auto-consolidate)   shift; voice::auto_consolidate "$@" ;;
    report)             shift; voice::report "$@" ;;
    style-directive)    shift; voice::style_directive "$@" ;;
    tone-summary)       shift; voice::tone_summary "$@" ;;
    reset)              shift; voice::reset "$@" ;;
    -h|--help|help|*)
      sed -n '2,45p' "${BASH_SOURCE[0]}"
      ;;
  esac
fi

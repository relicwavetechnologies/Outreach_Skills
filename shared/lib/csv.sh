#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / csv.sh
#  RFC 4180 CSV parser used by mailmerge-html.
#  Wraps python3's csv module for correctness (quoted fields with embedded
#  commas, escaped quotes, multi-line quoted fields, etc.).
#
#  Source it:  . "$HTML_SKILLS_LIB/csv.sh"
#
#  Public functions:
#    csv::require                # ensures python3 is available; exit 10 if not
#    csv::validate <file>        # 0 if well-formed, non-zero otherwise
#    csv::header <file>          # prints header row as JSON array on stdout
#    csv::count  <file>          # prints row count (excludes header)
#    csv::parse  <file>          # emits one JSON object per data row (jsonl)
#    csv::row    <file> <n>      # emits Nth data row (1-indexed) as JSON object
#    csv::detect_field <file> <field-substring...>
#                                # prints actual header that loosely matches any
#                                # of the given substrings (case-insensitive).
#                                # Useful for "find the linkedin column" etc.
# ──────────────────────────────────────────────────────────────────────────

if [ -n "${__HTML_SKILLS_CSV_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_CSV_LOADED=1

if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HTML_SKILLS_LIB
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"

csv::require() {
  if command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  log::fail "Missing dependency: python3"
  log::dim "macOS:  python3 ships with the Xcode CLT — \`xcode-select --install\`"
  log::dim "Linux:  install via your package manager (apt/dnf/pacman)"
  exit 10
}

csv::validate() {
  local file="${1:?file required}"
  if [ ! -f "$file" ]; then
    log::fail "No such CSV: $file"
    return 2
  fi
  csv::require
  python3 - "$file" <<'PY'
import csv, sys
path = sys.argv[1]
try:
    with open(path, newline='', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        rows = list(reader)
    if not rows:
        sys.stderr.write("empty CSV\n"); sys.exit(3)
    width = len(rows[0])
    if width == 0:
        sys.stderr.write("empty header\n"); sys.exit(4)
    for i, row in enumerate(rows[1:], start=2):
        # Permit short rows (treated as missing trailing cells) but flag wider rows.
        if len(row) > width:
            sys.stderr.write(f"row {i} has {len(row)} cells; header has {width}\n")
            sys.exit(5)
    sys.exit(0)
except UnicodeDecodeError as e:
    sys.stderr.write(f"non-utf8 file: {e}\n"); sys.exit(6)
except csv.Error as e:
    sys.stderr.write(f"csv error: {e}\n"); sys.exit(7)
PY
}

csv::header() {
  local file="${1:?file required}"
  csv::require
  python3 - "$file" <<'PY'
import csv, json, sys
with open(sys.argv[1], newline='', encoding='utf-8-sig') as f:
    reader = csv.reader(f)
    try:
        header = next(reader)
    except StopIteration:
        print("[]")
        sys.exit(0)
    print(json.dumps([h.strip() for h in header], ensure_ascii=False))
PY
}

csv::count() {
  local file="${1:?file required}"
  csv::require
  python3 - "$file" <<'PY'
import csv, sys
with open(sys.argv[1], newline='', encoding='utf-8-sig') as f:
    reader = csv.reader(f)
    rows = sum(1 for _ in reader)
print(max(0, rows - 1))
PY
}

# Emit one JSON object per data row on stdout (jsonl). Keys are header values.
# Empty cells become empty strings (NOT null) so downstream skill prompts have
# predictable types.
csv::parse() {
  local file="${1:?file required}"
  csv::require
  python3 - "$file" <<'PY'
import csv, json, sys
with open(sys.argv[1], newline='', encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    for row in reader:
        # Normalize: strip keys + values, ensure string types.
        obj = {(k.strip() if k else ''): (v.strip() if v is not None else '') for k, v in row.items() if k is not None}
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
PY
}

csv::row() {
  local file="${1:?file required}"
  local n="${2:?row number required}"
  csv::require
  python3 - "$file" "$n" <<'PY'
import csv, json, sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path, newline='', encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, start=1):
        if i == n:
            obj = {(k.strip() if k else ''): (v.strip() if v is not None else '') for k, v in row.items() if k is not None}
            print(json.dumps(obj, ensure_ascii=False))
            sys.exit(0)
sys.stderr.write(f"row {n} not found\n"); sys.exit(8)
PY
}

# csv::detect_field <file> <substring> [<substring2>...]
# Returns the FIRST header name (case-insensitive) that contains ANY substring.
# Exit 1 if none found.
csv::detect_field() {
  local file="${1:?file required}"
  shift
  if [ "$#" -eq 0 ]; then
    log::fail "csv::detect_field: at least one substring required"
    return 2
  fi
  csv::require
  python3 - "$file" "$@" <<'PY'
import csv, sys
path = sys.argv[1]
needles = [s.lower() for s in sys.argv[2:]]
with open(path, newline='', encoding='utf-8-sig') as f:
    try:
        header = next(csv.reader(f))
    except StopIteration:
        sys.exit(1)
for h in header:
    hl = h.strip().lower()
    for n in needles:
        if n in hl:
            print(h.strip())
            sys.exit(0)
sys.exit(1)
PY
}

# CLI for direct testing.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-help}" in
    validate)     shift; csv::validate "$@" ;;
    header)       shift; csv::header   "$@" ;;
    count)        shift; csv::count    "$@" ;;
    parse)        shift; csv::parse    "$@" ;;
    row)          shift; csv::row      "$@" ;;
    detect-field) shift; csv::detect_field "$@" ;;
    -h|--help|help|*)
      sed -n '2,40p' "${BASH_SOURCE[0]}"
      ;;
  esac
fi

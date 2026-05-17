#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  tests/lint-skills.sh
#  Static analysis of skills/*/SKILL.md.
#
#  Catches mistakes that integration tests can't (because they would
#  only surface when an LLM executes the skill against real data):
#    - Malformed / missing YAML frontmatter
#    - Triple-backtick bash blocks that don't parse (bash -n)
#    - References to shared/lib/X.sh or shared/components/X.html
#      that don't exist in the repo
#    - References to memory::* / outcomes::* / track::* helpers that
#      aren't actually defined in their respective libraries
#
#  Run from repo root:    bash tests/lint-skills.sh
# ──────────────────────────────────────────────────────────────────────────

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${REPO_ROOT}/skills"
LIB="${REPO_ROOT}/shared/lib"
COMPONENTS="${REPO_ROOT}/shared/components"

PASS=0; FAIL=0; FAILED=()
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); FAILED+=("$1"); }

command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 1; }

# Collect defined helper functions from each lib.
LIB_FNS_FILE="$(mktemp)"
for f in "$LIB"/*.sh; do
  # Match `name::sub()` style function declarations.
  grep -hoE '^[a-z_]+::[a-z_]+\(\)' "$f" | sed 's/()//' >> "$LIB_FNS_FILE" 2>/dev/null || true
done
# A handful of helpers come from external tools (jq, vercel, etc.) — list known
# good ones we won't flag.
KNOWN_EXTERNAL=$'\nrun::ext\ndeploy::__phase\ndeploy::__set_phase'  # internals invoked from within deploy.sh prose

echo
echo "▶ lint skills — static analysis"
echo "  skills dir: $SKILLS_DIR"

if [ ! -d "$SKILLS_DIR" ]; then
  fail "no skills/ directory"
  exit 1
fi

for skill_dir in "$SKILLS_DIR"/*/; do
  skill="$(basename "$skill_dir")"
  md="${skill_dir}SKILL.md"
  echo
  echo "▶ $skill"

  if [ ! -f "$md" ]; then
    fail "$skill: SKILL.md missing"
    continue
  fi

  # ── 1. Frontmatter (YAML between leading --- ... --- lines) ───────────
  python3 - "$md" "$skill" <<'PY' || true
import sys, re
path, skill = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    text = f.read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m:
    print(f"FAIL:{skill}: missing or malformed --- frontmatter ---")
    sys.exit(2)
fm = m.group(1)
# Lightweight check: required fields name + description, single-line values.
required = ['name', 'description']
missing = [k for k in required if not re.search(rf'^{k}:\s*\S', fm, re.MULTILINE)]
if missing:
    print(f"FAIL:{skill}: frontmatter missing fields: {missing}")
    sys.exit(2)
# `name:` value should match the directory name.
name_m = re.search(r'^name:\s*(\S+)', fm, re.MULTILINE)
if name_m and name_m.group(1) != skill:
    print(f"FAIL:{skill}: frontmatter name='{name_m.group(1)}' != directory '{skill}'")
    sys.exit(2)
print(f"OK:{skill}: frontmatter")
PY
  case "$(python3 - "$md" "$skill" 2>/dev/null <<'PY'
import sys, re
path, skill = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8').read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m: sys.exit(2)
fm = m.group(1)
if not re.search(r'^name:\s*\S', fm, re.MULTILINE): sys.exit(2)
if not re.search(r'^description:\s*\S', fm, re.MULTILINE): sys.exit(2)
name_m = re.search(r'^name:\s*(\S+)', fm, re.MULTILINE)
if name_m and name_m.group(1) != skill: sys.exit(2)
PY
  )" in
    "") pass "$skill: frontmatter OK (name, description, matches dir)" ;;
    *)  fail "$skill: frontmatter problem" ;;
  esac

  # ── 2. Bash code blocks parse cleanly (bash -n) ──────────────────────
  # Extract ```bash blocks → temp file → bash -n.
  blocks_dir="$(mktemp -d)"
  python3 - "$md" "$blocks_dir" <<'PY'
import re, sys, pathlib, textwrap
text = open(sys.argv[1], encoding='utf-8').read()
dest = pathlib.Path(sys.argv[2])
# Tolerate indented fenced blocks (markdown inside numbered lists indents
# both opener and closer). We accept up to 4 spaces of indent on each fence.
pat = re.compile(
    r'^[\t ]{0,4}```bash\s*\n'
    r'(.*?)'
    r'\n[\t ]{0,4}```\s*$',
    re.DOTALL | re.MULTILINE,
)
blocks = pat.findall(text)
for i, b in enumerate(blocks, 1):
    # If the captured content has uniform leading indent, strip it so bash -n
    # sees clean code. textwrap.dedent handles only the common prefix.
    cleaned = textwrap.dedent(b)
    (dest / f"block-{i}.sh").write_text(cleaned)
print(f"Extracted {len(blocks)} bash blocks", file=sys.stderr)
PY
  block_fail=0
  shopt -s nullglob
  for b in "$blocks_dir"/*.sh; do
    if ! bash -n "$b" 2>"${b}.err"; then
      block_fail=1
      fail "$skill: bash block parse error in $(basename "$b") — $(head -n1 "${b}.err")"
    fi
  done
  shopt -u nullglob
  if [ "$block_fail" = "0" ]; then
    n=$(ls "$blocks_dir"/*.sh 2>/dev/null | wc -l | tr -d ' ')
    pass "$skill: $n bash block(s) parse cleanly"
  fi
  rm -rf "$blocks_dir"

  # ── 3. Referenced shared/lib/*.sh files exist ────────────────────────
  # Find paths like  ../../shared/lib/X.sh  OR  shared/lib/X.sh  OR  \$HTML_SKILLS_LIB/X.sh
  refs="$(grep -oE '(\.\./\.\./shared/lib/|shared/lib/|\$HTML_SKILLS_LIB/|\$\{HTML_SKILLS_LIB\}/)[a-z_.-]+\.sh' "$md" | sed -E 's|.*/||' | sort -u || true)"
  missing_libs=""
  for r in $refs; do
    if [ ! -f "$LIB/$r" ]; then missing_libs="${missing_libs} $r"; fi
  done
  if [ -n "$missing_libs" ]; then
    fail "$skill: missing lib refs:$missing_libs"
  else
    n="$(printf "%s" "$refs" | wc -w | tr -d ' ')"
    pass "$skill: $n lib reference(s) all resolve"
  fi

  # ── 4. Referenced shared/components/*.html exist ─────────────────────
  refs="$(grep -oE '(\.\./\.\./shared/components/|shared/components/)[a-z_.-]+\.html' "$md" | sed -E 's|.*/||' | sort -u || true)"
  missing_comps=""
  for r in $refs; do
    if [ ! -f "$COMPONENTS/$r" ]; then missing_comps="${missing_comps} $r"; fi
  done
  if [ -n "$missing_comps" ]; then
    fail "$skill: missing component refs:$missing_comps"
  else
    n="$(printf "%s" "$refs" | wc -w | tr -d ' ')"
    pass "$skill: $n component reference(s) all resolve"
  fi

  # ── 5. Referenced helper functions exist in some lib ─────────────────
  # Look for  memory::add_fact  /  outcomes::record  /  track::inject  etc.
  refs="$(grep -hoE '\b(memory|outcomes|track|deploy|log|csv|run)::[a-z_]+' "$md" | sort -u || true)"
  missing_fns=""
  for fn in $refs; do
    if ! grep -Fxq -- "$fn" "$LIB_FNS_FILE" \
       && ! printf "%s" "$KNOWN_EXTERNAL" | grep -Fxq -- "$fn" ; then
      missing_fns="${missing_fns} $fn"
    fi
  done
  if [ -n "$missing_fns" ]; then
    fail "$skill: helper functions referenced but not defined in any lib:$missing_fns"
  else
    n="$(printf "%s" "$refs" | wc -w | tr -d ' ')"
    pass "$skill: $n helper reference(s) all resolve"
  fi
done

rm -f "$LIB_FNS_FILE"

echo
echo "─────────────────────────────────────────────"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo; echo "  failed:"; for t in "${FAILED[@]}"; do echo "    - $t"; done
  exit 1
fi
echo "─────────────────────────────────────────────"

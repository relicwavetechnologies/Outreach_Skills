#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills installer
#
#  Default:
#    curl -fsSL https://raw.githubusercontent.com/relicwavetechnologies/Outreach_Skills/main/install.sh | bash
#
#  With auto-install of optional deps (jq, python3, node):
#    curl -fsSL https://raw.githubusercontent.com/relicwavetechnologies/Outreach_Skills/main/install.sh | bash -s -- --auto-deps
#
#  Drops SKILL.md files into ~/.claude/skills/html-skills/ and/or
#  ~/.codex/skills/html-skills/ so Claude Code and Codex can use them.
#  Asks plain-language questions. Non-technical friendly.
# ──────────────────────────────────────────────────────────────────────────

set -e

# ── Args ─────────────────────────────────────────────────────────────────
AUTO_DEPS=0
for arg in "$@"; do
  case "$arg" in
    --auto-deps)  AUTO_DEPS=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) ;;  # unknown flags pass through; future-proofing
  esac
done

# ── Config ───────────────────────────────────────────────────────────────
GITHUB_USERNAME="relicwavetechnologies"
GITHUB_REPO="Outreach_Skills"
GITHUB_BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USERNAME}/${GITHUB_REPO}/${GITHUB_BRANCH}"

ALL_SKILLS=(research-html present-html deploy-html outreach-html mailmerge-html dashboard-html plan-html review-html editor-html)
OUTREACH_BUNDLE=(research-html present-html deploy-html outreach-html mailmerge-html)
SHARED_FILES=(profile.md design-tokens.css SCHEMAS.md)
SHARED_LIB_FILES=(log.sh memory.sh deploy.sh csv.sh outcomes.sh track.sh patterns.sh nudges.sh voice.sh voice_consolidate.py)
SHARED_COMPONENT_FILES=(confidence-dot.html sources-footer.html insight-block.html mailmerge-dashboard.html dashboard.html track.js track-server.js)

# ── Colors (tput when available, fallback to ANSI) ───────────────────────
# Guard tput failures so a missing $TERM doesn't kill the script under `set -e`.
if command -v tput >/dev/null 2>&1 && [ -t 1 ] && [ -n "${TERM:-}" ] && tput sgr0 >/dev/null 2>&1; then
  BOLD=$(tput bold)
  DIM=$(tput dim)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  CYAN=$(tput setaf 6)
  RESET=$(tput sgr0)
else
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
fi

ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
info()  { printf "  ${BLUE}↓${RESET} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
fail()  { printf "  ${RED}✗${RESET} %s\n" "$1"; }
title() { printf "\n${BOLD}${CYAN}%s${RESET}\n" "$1"; }
dim()   { printf "  ${DIM}%s${RESET}\n" "$1"; }

# ── Welcome ──────────────────────────────────────────────────────────────
clear 2>/dev/null || true
cat <<EOF

${BOLD}${CYAN}  html-skills installer${RESET}
  ${DIM}Skills that turn Claude/Codex into a rich-HTML generator.${RESET}

EOF

# ── 1. Pick install target (Claude / Codex / Both) ───────────────────────
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

claude_exists=false
codex_exists=false
[ -d "$CLAUDE_DIR" ] && claude_exists=true
[ -d "$CODEX_DIR" ]  && codex_exists=true

title "Where should I install?"

if $claude_exists && $codex_exists; then
  dim "Found both Claude Code and Codex on this machine."
  printf "    1) Claude Code only  (${DIM}~/.claude/skills${RESET})\n"
  printf "    2) Codex only        (${DIM}~/.codex/skills${RESET})\n"
  printf "    3) Both              (${DIM}recommended${RESET})\n"
  printf "  Pick [1/2/${BOLD}3${RESET}]: "
  read -r choice </dev/tty
  case "${choice:-3}" in
    1) targets=("$CLAUDE_DIR") ;;
    2) targets=("$CODEX_DIR") ;;
    *) targets=("$CLAUDE_DIR" "$CODEX_DIR") ;;
  esac
elif $claude_exists; then
  ok "Found Claude Code — installing to ~/.claude/skills"
  targets=("$CLAUDE_DIR")
elif $codex_exists; then
  ok "Found Codex — installing to ~/.codex/skills"
  targets=("$CODEX_DIR")
else
  warn "Didn't find Claude Code or Codex installed yet."
  dim "I'll create ~/.claude/skills/ so it's ready when you install Claude Code."
  mkdir -p "$CLAUDE_DIR"
  targets=("$CLAUDE_DIR")
fi

# ── 2. Pick skills to install ────────────────────────────────────────────
title "Which skills do you want?"

printf "    1) ${BOLD}All 7${RESET}              (${DIM}everything — recommended${RESET})\n"
printf "    2) ${BOLD}Outreach bundle${RESET}    (${DIM}research + present + deploy + outreach${RESET})\n"
printf "    3) ${BOLD}Pick individually${RESET}\n"
printf "  Pick [${BOLD}1${RESET}/2/3]: "
read -r choice </dev/tty

case "${choice:-1}" in
  2)
    selected=("${OUTREACH_BUNDLE[@]}")
    ;;
  3)
    selected=()
    dim "Hit enter to skip, or 'y' to include:"
    for skill in "${ALL_SKILLS[@]}"; do
      printf "    Install %s? [y/${BOLD}N${RESET}]: " "$skill"
      read -r reply </dev/tty
      [[ "$reply" =~ ^[Yy]$ ]] && selected+=("$skill")
    done
    if [ ${#selected[@]} -eq 0 ]; then
      fail "Nothing picked. Bye!"
      exit 0
    fi
    ;;
  *)
    selected=("${ALL_SKILLS[@]}")
    ;;
esac

# ── 3. Download ──────────────────────────────────────────────────────────
download() {
  local url="$1"
  local dest="$2"
  if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

network_error_msg() {
  fail "Couldn't reach GitHub."
  dim "Either your internet is down, or the repo URL is wrong."
  dim "Repo: https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO}"
  dim "Try again in a minute, or grab the files manually from the repo."
}

for target in "${targets[@]}"; do
  install_root="${target}/skills/html-skills"
  shared_root="${install_root}/shared"
  lib_root="${shared_root}/lib"
  components_root="${shared_root}/components"
  mkdir -p "$shared_root" "$lib_root" "$components_root"

  title "Installing to ${install_root}"

  # Shared files first
  for f in "${SHARED_FILES[@]}"; do
    info "Downloading shared/${f}"
    if download "${BASE_URL}/shared/${f}" "${shared_root}/${f}"; then
      ok "shared/${f}"
    else
      network_error_msg
      exit 1
    fi
  done

  # Shared executable library (deploy state machine + helpers)
  for f in "${SHARED_LIB_FILES[@]}"; do
    info "Downloading shared/lib/${f}"
    if download "${BASE_URL}/shared/lib/${f}" "${lib_root}/${f}"; then
      chmod +x "${lib_root}/${f}"
      ok "shared/lib/${f}"
    else
      network_error_msg
      exit 1
    fi
  done

  # Reusable HTML component snippets (confidence dots, sources footer, insight blocks)
  for f in "${SHARED_COMPONENT_FILES[@]}"; do
    info "Downloading shared/components/${f}"
    if download "${BASE_URL}/shared/components/${f}" "${components_root}/${f}"; then
      ok "shared/components/${f}"
    else
      network_error_msg
      exit 1
    fi
  done

  # Each skill
  for skill in "${selected[@]}"; do
    skill_dir="${install_root}/${skill}"
    mkdir -p "$skill_dir"
    info "Downloading ${skill}/SKILL.md"
    if download "${BASE_URL}/skills/${skill}/SKILL.md" "${skill_dir}/SKILL.md"; then
      ok "${skill}"
    else
      network_error_msg
      exit 1
    fi
  done
done

# ── 3b. Initialize per-user cache (memory skeleton + deploy state) ───────
title "Initializing local cache"

# Pick the most recent install_root to source memory.sh from. Both copies are
# identical, so either works; we just need one to exist.
init_root="${targets[0]}/skills/html-skills/shared/lib"
if [ -f "${init_root}/memory.sh" ]; then
  # shellcheck source=/dev/null
  HTML_SKILLS_LIB="${init_root}" . "${init_root}/memory.sh"
  memory::init
  ok "Cache ready at ~/.cache/html-skills/"
  dim "  memory/  — profile, voice, patterns, targets, runs, outcomes"
  dim "  state/   — deploy.json (vercel setup + last deploy)"
else
  warn "Couldn't source memory.sh from ${init_root} — cache not pre-initialized."
  dim "First skill run will create it automatically."
fi

# ── 3c. Optional dependency check ────────────────────────────────────────
#
#  Default mode (no --auto-deps): just REPORTS which deps are missing and
#  prints the platform-correct install command. Conservative — never
#  installs system packages without explicit consent.
#
#  --auto-deps mode: for each missing dep, asks once "Install via <PM>? [y/N]".
#  Per-dep confirmation keeps the user in control even within the "auto"
#  mode. Decline → falls back to the same report-and-suggest as default.
#
#  Vercel + Node are deliberately handled lazily by deploy.sh on first
#  ship; we don't push them at install time. install.sh only proactively
#  installs jq (used by every memory operation) and python3 (used by
#  csv/voice/patterns) if --auto-deps is set.

# Pick the platform package manager.
detect_pm() {
  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then echo "brew"; return; fi
      echo "macos-no-brew"; return ;;
    Linux)
      if   command -v apt-get >/dev/null 2>&1; then echo "apt"
      elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
      elif command -v pacman  >/dev/null 2>&1; then echo "pacman"
      elif command -v zypper  >/dev/null 2>&1; then echo "zypper"
      elif command -v apk     >/dev/null 2>&1; then echo "apk"
      else echo "linux-unknown"; fi
      return ;;
    *) echo "unknown"; return ;;
  esac
}

# Print the platform-specific install command for a dep.
install_hint() {
  local pkg="$1" pm="$2"
  case "$pm" in
    brew)         echo "brew install $pkg" ;;
    apt)          echo "sudo apt-get update && sudo apt-get install -y $pkg" ;;
    dnf)          echo "sudo dnf install -y $pkg" ;;
    pacman)       echo "sudo pacman -S --noconfirm $pkg" ;;
    zypper)       echo "sudo zypper install -y $pkg" ;;
    apk)          echo "sudo apk add $pkg" ;;
    macos-no-brew) echo "install Homebrew from https://brew.sh, then: brew install $pkg" ;;
    *)            echo "install $pkg via your platform's package manager" ;;
  esac
}

# Try to install a package. Returns 0 on success.
auto_install() {
  local pkg="$1" pm="$2"
  case "$pm" in
    brew)    brew install "$pkg" ;;
    apt)     sudo apt-get update -qq && sudo apt-get install -y "$pkg" ;;
    dnf)     sudo dnf install -y "$pkg" ;;
    pacman)  sudo pacman -S --noconfirm "$pkg" ;;
    zypper)  sudo zypper install -y "$pkg" ;;
    apk)     sudo apk add "$pkg" ;;
    *)       return 1 ;;
  esac
}

# Handle a single dep: detect, report, optionally offer auto-install.
handle_dep() {
  local cmd="$1" pkg="$2" why="$3" required="${4:-soft}"
  if command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in
      jq)      ok "jq found ($(jq --version 2>/dev/null))" ;;
      python3) ok "python3 found ($(python3 --version 2>&1))" ;;
      node)    ok "Node found ($(node --version 2>/dev/null))" ;;
      *)       ok "$cmd found" ;;
    esac
    return 0
  fi

  # Missing — always report why.
  if [ "$required" = "hard" ]; then
    warn "$cmd not installed — $why"
  else
    dim "$cmd not installed — $why"
  fi
  local pm; pm="$(detect_pm)"
  local hint; hint="$(install_hint "$pkg" "$pm")"

  if [ "$AUTO_DEPS" = "1" ] && [[ "$pm" =~ ^(brew|apt|dnf|pacman|zypper|apk)$ ]]; then
    printf "    ${BOLD}Install %s via %s?${RESET} [y/${BOLD}N${RESET}]: " "$pkg" "$pm"
    local reply=""
    if [ -t 0 ]; then
      read -r reply </dev/tty 2>/dev/null || reply=""
    else
      read -r reply </dev/tty 2>/dev/null || reply=""
    fi
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      if auto_install "$pkg" "$pm"; then
        ok "$pkg installed"
        return 0
      else
        warn "auto-install of $pkg failed — run manually:"
        dim "  $hint"
        return 1
      fi
    fi
  fi

  dim "  install with: $hint"
}

title "Checking optional dependencies"
if [ "$AUTO_DEPS" = "1" ]; then
  dim "(running with --auto-deps — will offer to install missing deps via $(detect_pm))"
fi

# Required-ish: jq (every memory op) + python3 (csv/voice/patterns).
handle_dep jq      jq      "needed for state updates" hard
handle_dep python3 python3 "needed by mailmerge/voice/patterns for parsing + analysis" hard

# Lazily handled by deploy.sh on first ship; just report status.
handle_dep node    node    "deploy-html installs it on first ship if missing" soft
if command -v vercel >/dev/null 2>&1; then
  ok "Vercel CLI found"
else
  dim "Vercel CLI not found — deploy-html will install it on first ship."
fi

# ── 4. Done — show usage ─────────────────────────────────────────────────
cat <<EOF

${BOLD}${GREEN}  Done — html-skills installed.${RESET}

${BOLD}Try these in Claude Code or Codex:${RESET}

  ${CYAN}Research:${RESET}     "Research Acme Corp for me"
  ${CYAN}Outreach:${RESET}     "Do an outreach to John at Acme"
  ${CYAN}Mailmerge:${RESET}    "Mailmerge to these 20 founders in this CSV"
  ${CYAN}Dashboard:${RESET}    "Show me the dashboard" / "how's outreach going"
  ${CYAN}Present:${RESET}      "Turn this doc into a presentation"
  ${CYAN}Plan:${RESET}         "Plan out how we'd onboard our first 10 customers"
  ${CYAN}Review:${RESET}       "Review the latest PR for me"
  ${CYAN}Edit:${RESET}         "Make me a kanban to triage these 40 leads"
  ${CYAN}Deploy:${RESET}       "Put this HTML file on a live URL"

${DIM}  First time you run a skill it'll ask a few questions.${RESET}
${DIM}  After that, it remembers your preferences and just goes.${RESET}

EOF

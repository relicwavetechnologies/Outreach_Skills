#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / log.sh
#  Shared logging + diagnostics helpers used by every shell-side skill action.
#
#  Source it:  . "$HTML_SKILLS_LIB/log.sh"
#
#  Provides:
#    log::ok    "msg"          # ✓ green status line
#    log::info  "msg"          # ↓ blue info line
#    log::warn  "msg"          # ! yellow warning
#    log::fail  "msg"          # ✗ red failure
#    log::dim   "msg"          # dim aside
#    log::title "msg"          # bold cyan section title
#    log::error_to_file <skill> <command> <exit_code> <stderr_path>
#                                # writes ~/.cache/html-skills/last-error.md
#    log::set_run_id <skill>   # exports HTML_SKILLS_RUN_ID
# ──────────────────────────────────────────────────────────────────────────

# Idempotent guard so multiple sources don't redefine.
if [ -n "${__HTML_SKILLS_LOG_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_LOG_LOADED=1

# ── Colors (tput when available, ANSI fallback) ──────────────────────────
if command -v tput >/dev/null 2>&1 && [ -t 1 ] && [ -n "${TERM:-}" ] && tput sgr0 >/dev/null 2>&1; then
  __LOG_BOLD=$(tput bold)
  __LOG_DIM=$(tput dim)
  __LOG_RED=$(tput setaf 1)
  __LOG_GREEN=$(tput setaf 2)
  __LOG_YELLOW=$(tput setaf 3)
  __LOG_BLUE=$(tput setaf 4)
  __LOG_CYAN=$(tput setaf 6)
  __LOG_RESET=$(tput sgr0)
else
  __LOG_BOLD=$'\033[1m'; __LOG_DIM=$'\033[2m'
  __LOG_RED=$'\033[31m'; __LOG_GREEN=$'\033[32m'
  __LOG_YELLOW=$'\033[33m'; __LOG_BLUE=$'\033[34m'; __LOG_CYAN=$'\033[36m'
  __LOG_RESET=$'\033[0m'
fi

# Honor NO_COLOR (https://no-color.org)
if [ -n "${NO_COLOR:-}" ]; then
  __LOG_BOLD=""; __LOG_DIM=""; __LOG_RED=""; __LOG_GREEN=""
  __LOG_YELLOW=""; __LOG_BLUE=""; __LOG_CYAN=""; __LOG_RESET=""
fi

log::ok()    { printf "  ${__LOG_GREEN}✓${__LOG_RESET} %s\n" "$*"; }
log::info()  { printf "  ${__LOG_BLUE}↓${__LOG_RESET} %s\n" "$*"; }
log::warn()  { printf "  ${__LOG_YELLOW}!${__LOG_RESET} %s\n" "$*"; }
log::fail()  { printf "  ${__LOG_RED}✗${__LOG_RESET} %s\n" "$*"; }
log::dim()   { printf "  ${__LOG_DIM}%s${__LOG_RESET}\n" "$*"; }
log::title() { printf "\n${__LOG_BOLD}${__LOG_CYAN}%s${__LOG_RESET}\n" "$*"; }

# ── Run ID for correlating logs across a single skill invocation ─────────
# Format: YYYYMMDD-HHMMSS-<skill>-<rand>
log::set_run_id() {
  local skill="${1:-skill}"
  local ts
  ts="$(date -u +%Y%m%d-%H%M%S 2>/dev/null || echo "unknown")"
  local rand
  rand="$(printf '%04x' $((RANDOM % 65536)))"
  HTML_SKILLS_RUN_ID="${ts}-${skill}-${rand}"
  export HTML_SKILLS_RUN_ID
}

# ── Diagnostic file: written on any hard failure ─────────────────────────
# Args: <skill> <failed_command> <exit_code> [stderr_path]
log::error_to_file() {
  local skill="${1:-unknown}"
  local cmd="${2:-unknown}"
  local code="${3:-?}"
  local stderr_path="${4:-}"
  # Honor HTML_SKILLS_CACHE override (used by tests, sandboxing).
  local cache="${HTML_SKILLS_CACHE:-${HOME}/.cache/html-skills}"
  mkdir -p "$cache"
  local out="${cache}/last-error.md"

  {
    echo "# html-skills — last error"
    echo
    echo "- **When:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- **Skill:** ${skill}"
    echo "- **Run ID:** ${HTML_SKILLS_RUN_ID:-n/a}"
    echo "- **Exit code:** ${code}"
    echo
    echo "## Command"
    echo
    echo '```'
    echo "${cmd}"
    echo '```'
    if [ -n "$stderr_path" ] && [ -f "$stderr_path" ]; then
      echo
      echo "## Last 40 lines of output"
      echo
      echo '```'
      tail -n 40 "$stderr_path" 2>/dev/null || echo "(could not read $stderr_path)"
      echo '```'
    fi
    echo
    echo "## Suggested next step"
    echo
    case "$code" in
      124) echo "- Command timed out. Check your internet, then re-run the skill." ;;
      127) echo "- Command not found. The required tool isn't installed — re-run the install script." ;;
      1)   echo "- Generic failure. Read the output above; if it mentions auth, run \`vercel login\` and try again." ;;
      *)   echo "- Re-run the skill once. If it fails again, paste this file into a GitHub issue." ;;
    esac
    echo
    echo "_File path: \`${out}\`_"
  } > "$out"

  log::fail "Hit a problem — diagnostic written to ${out}"
}

# Capture stderr from a command run via run::with_diag (defined in deploy.sh).
# Exported so subshells inherit definitions if needed.
export -f log::ok log::info log::warn log::fail log::dim log::title log::set_run_id log::error_to_file 2>/dev/null || true

#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / deploy.sh
#  Production-grade Vercel deploy state machine.
#  Shared by deploy-html and outreach-html skills (single source of truth).
#
#  PHASES (state/deploy.json → "phase"):
#    fresh           — nothing set up yet
#    awaiting-auth   — vercel login launched, polling for completion
#    ready           — node + cli + auth + project all verified
#    deployed        — last action was a successful deploy
#
#  COMMANDS:
#    deploy.sh status                       # print current state, exit 0
#    deploy.sh check                        # pre-flight env checks (no network writes)
#    deploy.sh setup --project NAME \
#                    [--scope SCOPE]        # interactive-ish setup; idempotent
#                    [--domain DOMAIN]
#                    [--webhook URL]
#    deploy.sh ship <html-file>             # deploy a file; runs setup if needed
#                    [--project NAME] [--scope SCOPE]
#                    [--domain D] [--webhook W]
#                    [--open]               # open URL after deploy
#    deploy.sh reset                        # wipe state (asks for confirmation)
#
#  ENV:
#    HTML_SKILLS_DRY_RUN=1   — mock all external calls (vercel/brew/npm/node)
#    HTML_SKILLS_NO_OPEN=1   — never auto-open URLs in browser
#    HTML_SKILLS_CACHE=...   — override cache root (default ~/.cache/html-skills)
#    HTML_SKILLS_AUTH_POLL_INTERVAL=5  — seconds between whoami retries
#    HTML_SKILLS_AUTH_POLL_TRIES=18    — max retries (default 90s window)
#
#  EXIT CODES:
#    0   success
#    2   bad args
#    10  env missing (node / vercel CLI / not installable)
#    11  auth failed after poll window
#    12  link/deploy failed after retries
#    20  user aborted
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Locate sibling libs ──────────────────────────────────────────────────
if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/memory.sh"

memory::init

CACHE="$(memory::root)"
STATE_FILE="$(memory::state_file deploy)"

# ── Defaults ─────────────────────────────────────────────────────────────
AUTH_POLL_INTERVAL="${HTML_SKILLS_AUTH_POLL_INTERVAL:-5}"
AUTH_POLL_TRIES="${HTML_SKILLS_AUTH_POLL_TRIES:-18}"   # 18 × 5s = 90s
CMD_TIMEOUT="${HTML_SKILLS_CMD_TIMEOUT:-90}"            # per-external-call timeout
DEPLOY_TIMEOUT="${HTML_SKILLS_DEPLOY_TIMEOUT:-180}"     # vercel deploy can be slow

# ── External call wrapper with timeout + diagnostic on failure ───────────
# Usage: run::ext <skill-id> <timeout> -- <cmd ...>
#   Writes stderr to a temp file; on failure invokes log::error_to_file.
run::ext() {
  local skill="$1"; shift
  local t="$1"; shift
  if [ "$1" = "--" ]; then shift; fi

  local errf
  errf="$(mktemp -t htmlskills.err.XXXXXX)"
  local rc=0

  if [ "${HTML_SKILLS_DRY_RUN:-0}" = "1" ]; then
    # Mocked execution — see deploy::__mock at bottom.
    deploy::__mock "$@" 2>"$errf" || rc=$?
  else
    if command -v timeout >/dev/null 2>&1; then
      timeout "$t" "$@" 2>"$errf" || rc=$?
    elif command -v gtimeout >/dev/null 2>&1; then
      gtimeout "$t" "$@" 2>"$errf" || rc=$?
    else
      "$@" 2>"$errf" || rc=$?
    fi
  fi

  if [ "$rc" -ne 0 ]; then
    log::error_to_file "$skill" "$*" "$rc" "$errf"
    memory::set deploy '.last_error' "$(jq -Rn --arg c "$*" --arg r "$rc" \
      '{command:$c, exit_code:($r|tonumber), at: now|todate}')" 2>/dev/null || true
  fi
  rm -f "$errf"
  return "$rc"
}

# Single dispatch point for ALL `vercel` calls. Honors HTML_SKILLS_DRY_RUN
# so the mock layer is exercised consistently (this was the bug: parts of
# the script were calling `vercel` directly, bypassing the mock).
# Usage:
#   deploy::__vercel <args...>           — quiet, just returns exit code
#   deploy::__vercel_capture <args...>   — echoes stdout (also honors dry-run)
deploy::__vercel() {
  if [ "${HTML_SKILLS_DRY_RUN:-0}" = "1" ]; then
    deploy::__mock vercel "$@"
    return $?
  fi
  vercel "$@"
}

deploy::__vercel_capture() {
  if [ "${HTML_SKILLS_DRY_RUN:-0}" = "1" ]; then
    deploy::__mock vercel "$@"
    return $?
  fi
  vercel "$@"
}

# ── Helpers ──────────────────────────────────────────────────────────────
deploy::__phase() {
  memory::get deploy '.phase' || echo "fresh"
}

deploy::__set_phase() {
  local p="$1"
  memory::set deploy '.phase' "\"$p\""
  log::dim "phase → ${p}"
}

deploy::__require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log::fail "Missing dependency: jq"
    log::dim "Install on macOS:  brew install jq"
    log::dim "Install on Linux:  apt install jq  (or your distro's equivalent)"
    exit 10
  fi
}

deploy::__has_brew()   { command -v brew   >/dev/null 2>&1; }
deploy::__has_node()   { command -v node   >/dev/null 2>&1; }
deploy::__has_vercel() { command -v vercel >/dev/null 2>&1; }

# ── Public: status ───────────────────────────────────────────────────────
deploy::status() {
  deploy::__require_jq
  local phase project auth url
  phase="$(memory::get deploy '.phase')"
  project="$(memory::get deploy '.project')"
  auth="$(memory::get deploy '.auth_account')"
  url="$(memory::get deploy '.last_deploy.url')"

  log::title "deploy state"
  log::dim "phase:        ${phase:-fresh}"
  log::dim "project:      ${project:-(unset)}"
  log::dim "auth account: ${auth:-(not authed)}"
  log::dim "last deploy:  ${url:-(none)}"
  log::dim "state file:   ${STATE_FILE}"
}

# ── Public: check (no-network, no-write, pure inspection) ────────────────
deploy::check() {
  deploy::__require_jq
  local ok=1

  if deploy::__has_node; then
    local nv
    nv="$(node --version 2>/dev/null || echo unknown)"
    log::ok "Node found (${nv})"
    memory::set deploy '.node_version' "\"${nv}\""
  else
    log::warn "Node not found"
    ok=0
  fi

  if deploy::__has_vercel; then
    local vp
    vp="$(command -v vercel)"
    log::ok "Vercel CLI found (${vp})"
    memory::set deploy '.vercel_cli_path' "\"${vp}\""
  else
    log::warn "Vercel CLI not found"
    ok=0
  fi

  if deploy::__has_vercel || [ "${HTML_SKILLS_DRY_RUN:-0}" = "1" ]; then
    local who
    if who="$(deploy::__vercel_capture whoami 2>/dev/null)"; then
      log::ok "Authed as ${who}"
      memory::set deploy '.auth_account' "\"${who}\""
      memory::set deploy '.auth_last_verified' "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    else
      log::warn "Vercel CLI installed but not authed"
      ok=0
    fi
  fi

  [ "$ok" = "1" ] && return 0 || return 1
}

# ── Phase transitions ────────────────────────────────────────────────────
# Ensure Node ≥ 18. Try brew on macOS; otherwise instruct.
deploy::__ensure_node() {
  if deploy::__has_node; then
    local v
    v="$(node --version | sed 's/^v//' | cut -d. -f1)"
    if [ "${v:-0}" -ge 18 ] 2>/dev/null; then
      return 0
    fi
    log::warn "Node ${v} is too old (need 18+)."
  else
    log::info "Node isn't installed — Vercel needs it."
  fi

  case "$(uname -s)" in
    Darwin)
      if deploy::__has_brew; then
        log::info "Installing Node via Homebrew (about a minute)…"
        run::ext deploy-html "$CMD_TIMEOUT" -- brew install node || {
          log::fail "Homebrew install of Node failed."
          return 10
        }
      else
        log::fail "Homebrew not installed. Get it from https://brew.sh, then re-run."
        return 10
      fi
      ;;
    Linux)
      log::fail "Install Node 18+ via your package manager (apt/dnf), then re-run."
      return 10
      ;;
    *)
      log::fail "Unsupported OS for auto-install. Install Node 18+ manually."
      return 10
      ;;
  esac
}

deploy::__ensure_vercel_cli() {
  if deploy::__has_vercel; then
    return 0
  fi
  log::info "Installing Vercel CLI (about 20s)…"
  if run::ext deploy-html "$CMD_TIMEOUT" -- npm install -g vercel; then
    return 0
  fi
  log::warn "Global npm install failed — retrying with sudo."
  if run::ext deploy-html "$CMD_TIMEOUT" -- sudo npm install -g vercel; then
    return 0
  fi
  log::fail "Could not install Vercel CLI."
  return 10
}

# Wait for vercel login to actually land. THIS is the fix for the bug.
# vercel login returns 0 the moment the browser opens; we have to poll whoami.
deploy::__ensure_auth() {
  if deploy::__vercel whoami >/dev/null 2>&1; then
    local who
    who="$(deploy::__vercel_capture whoami 2>/dev/null)"
    memory::set deploy '.auth_account' "\"${who}\""
    memory::set deploy '.auth_last_verified' "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    return 0
  fi

  log::info "Need to log into Vercel — opening browser. Pick whichever account you want."
  deploy::__set_phase "awaiting-auth"

  # Fire login (non-blocking on stderr, blocking on stdin which goes nowhere).
  if [ "${HTML_SKILLS_DRY_RUN:-0}" = "1" ]; then
    deploy::__vercel login >/dev/null 2>&1 || true
  else
    # vercel login is interactive; don't capture stderr or it'll hang trying to draw a TTY.
    # We launch it and then poll separately.
    vercel login </dev/null >/dev/null 2>&1 &
    # Give it a moment to open the browser.
    sleep 2
    # User finishes in browser; whoami flips when done.
  fi

  log::dim "Waiting for auth… (up to $((AUTH_POLL_INTERVAL * AUTH_POLL_TRIES))s)"
  local i=0
  while [ "$i" -lt "$AUTH_POLL_TRIES" ]; do
    if deploy::__vercel whoami >/dev/null 2>&1; then
      local who
      who="$(deploy::__vercel_capture whoami 2>/dev/null)"
      log::ok "Logged in as ${who}"
      memory::set deploy '.auth_account' "\"${who}\""
      memory::set deploy '.auth_last_verified' "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
      return 0
    fi
    sleep "$AUTH_POLL_INTERVAL"
    i=$((i + 1))
  done

  log::fail "Auth didn't complete in time."
  log::dim "Run \`vercel login\` manually, then try again."
  return 11
}

# ── Public: setup (interactive-ish, idempotent) ──────────────────────────
deploy::setup() {
  deploy::__require_jq

  local project="" scope="" domain="" webhook=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --scope)   scope="$2";   shift 2 ;;
      --domain)  domain="$2";  shift 2 ;;
      --webhook) webhook="$2"; shift 2 ;;
      *) log::fail "Unknown setup flag: $1"; exit 2 ;;
    esac
  done

  log::title "Vercel setup"
  deploy::__ensure_node || exit $?
  deploy::__ensure_vercel_cli || exit $?
  deploy::__ensure_auth || exit $?

  if [ -n "$project" ]; then
    memory::set deploy '.project' "\"${project}\""
    log::ok "Project: ${project}"
  fi
  if [ -n "$scope" ]; then
    memory::set deploy '.scope' "\"${scope}\""
    log::ok "Scope: ${scope}"
  fi
  if [ -n "$domain" ]; then
    memory::set deploy '.custom_domain' "\"${domain}\""
    log::ok "Custom domain: ${domain}"
  fi
  if [ -n "$webhook" ]; then
    memory::set deploy '.webhook' "\"${webhook}\""
    log::ok "Webhook configured"
  fi

  deploy::__set_phase "ready"
  log::ok "Setup complete."
}

# ── Public: ship (the actual deploy) ─────────────────────────────────────
deploy::ship() {
  deploy::__require_jq

  local file="" project="" scope="" domain="" webhook="" open_after=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --scope)   scope="$2";   shift 2 ;;
      --domain)  domain="$2";  shift 2 ;;
      --webhook) webhook="$2"; shift 2 ;;
      --open)    open_after=1; shift ;;
      -*)        log::fail "Unknown ship flag: $1"; exit 2 ;;
      *)         if [ -z "$file" ]; then file="$1"; else log::fail "Extra arg: $1"; exit 2; fi; shift ;;
    esac
  done

  if [ -z "$file" ]; then
    log::fail "Usage: deploy.sh ship <html-file>"
    exit 2
  fi
  if [ ! -f "$file" ] && [ ! -d "$file" ]; then
    log::fail "No such file or directory: ${file}"
    exit 2
  fi

  # Pull defaults from state.
  [ -z "$project" ] && project="$(memory::get deploy '.project')"
  [ -z "$scope"   ] && scope="$(memory::get deploy '.scope')"
  [ -z "$domain"  ] && domain="$(memory::get deploy '.custom_domain')"
  [ -z "$webhook" ] && webhook="$(memory::get deploy '.webhook')"

  if [ -z "$project" ]; then
    log::fail "No project name set. Run: deploy.sh setup --project NAME"
    exit 2
  fi

  # ── Phase guard: if state is fresh/awaiting, run setup first.
  local phase
  phase="$(deploy::__phase)"
  if [ "$phase" = "fresh" ] || [ "$phase" = "awaiting-auth" ]; then
    deploy::setup --project "$project" ${scope:+--scope "$scope"} \
      ${domain:+--domain "$domain"} ${webhook:+--webhook "$webhook"} || exit $?
  else
    # Re-verify auth quickly — it can expire silently.
    if ! deploy::__vercel whoami >/dev/null 2>&1; then
      log::warn "Vercel session expired — re-authing."
      deploy::__ensure_auth || exit $?
    fi
  fi

  # ── Build temp project dir
  local ts
  ts="$(date -u +%Y%m%d-%H%M%S)"
  local work="${CACHE}/deploy/${ts}"
  mkdir -p "$work"

  if [ -d "$file" ]; then
    cp -R "$file"/. "$work/"
    [ -f "$work/index.html" ] || {
      log::fail "Directory has no index.html"
      rm -rf "$work"
      exit 2
    }
  else
    cp "$file" "$work/index.html"
  fi

  cat > "$work/vercel.json" <<'JSON'
{ "cleanUrls": true, "trailingSlash": false }
JSON

  # ── Link project (idempotent)
  log::info "Linking project to ${project}…"
  pushd "$work" >/dev/null
  local link_args=(link --yes --project "$project")
  [ -n "$scope" ] && link_args+=(--scope "$scope")
  if ! run::ext deploy-html "$CMD_TIMEOUT" -- vercel "${link_args[@]}"; then
    popd >/dev/null
    rm -rf "$work"
    log::fail "vercel link failed."
    exit 12
  fi

  # ── Deploy
  log::info "Deploying to production… (up to ${DEPLOY_TIMEOUT}s)"
  local out url=""
  out="$(mktemp -t htmlskills.deploy.XXXXXX)"

  local deploy_args=(--prod --yes)
  [ -n "$scope" ] && deploy_args+=(--scope "$scope")

  if run::ext deploy-html "$DEPLOY_TIMEOUT" -- vercel "${deploy_args[@]}" > "$out" 2>&1; then
    # Robust URL parse: last https://*.vercel.app on a line by itself, OR any first match.
    url="$(grep -Eo 'https://[a-zA-Z0-9.-]+\.vercel\.app[^[:space:]]*' "$out" | tail -n1 || true)"
    if [ -z "$url" ] && command -v jq >/dev/null 2>&1; then
      # Fallback: try vercel ls --json
      url="$(deploy::__vercel_capture ls --json 2>/dev/null | jq -r '.[0].url // empty' 2>/dev/null | head -n1 || true)"
      [ -n "$url" ] && [[ "$url" != http* ]] && url="https://${url}"
    fi
  fi

  rm -f "$out"
  popd >/dev/null

  if [ -z "$url" ]; then
    log::fail "Deploy completed but I couldn't capture the URL."
    log::dim "Check the Vercel dashboard: https://vercel.com/dashboard"
    rm -rf "$work"
    exit 12
  fi

  # ── Optional custom domain alias
  if [ -n "$domain" ]; then
    log::info "Aliasing to ${domain}…"
    if ! run::ext deploy-html "$CMD_TIMEOUT" -- vercel alias set "$url" "$domain"; then
      log::warn "Alias failed — the vercel.app URL still works."
    fi
  fi

  # ── Webhook ping
  if [ -n "$webhook" ]; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsS -X POST -H 'Content-Type: application/json' \
        -d "{\"text\":\"New page live: ${url}\"}" "$webhook" >/dev/null 2>&1 || \
        log::warn "Webhook ping failed (non-fatal)."
    fi
  fi

  # ── Persist
  memory::set deploy '.last_deploy' "$(jq -Rn --arg u "$url" --arg s "$(basename "$file")" \
    '{url:$u, source:$s, at: now|todate}')"
  deploy::__set_phase "deployed"

  rm -rf "$work"

  log::ok "Live: ${url}"
  if [ -n "$domain" ]; then
    log::ok "Also: https://${domain}"
  fi

  # ── Open in browser
  if [ "$open_after" = "1" ] && [ "${HTML_SKILLS_NO_OPEN:-0}" != "1" ]; then
    case "$(uname -s)" in
      Darwin) open "$url" >/dev/null 2>&1 || true ;;
      Linux)  xdg-open "$url" >/dev/null 2>&1 || true ;;
    esac
  fi

  # Emit URL on stdout (last line) so callers can capture it.
  printf "%s\n" "$url"
}

# ── Public: reset ────────────────────────────────────────────────────────
deploy::reset() {
  rm -f "$STATE_FILE"
  memory::init
  log::ok "Reset deploy state."
}

# ── Mock layer for HTML_SKILLS_DRY_RUN=1 ─────────────────────────────────
# Lets tests exercise the state machine without hitting the network.
deploy::__mock() {
  local cmd="$1"; shift
  case "$cmd" in
    node)
      case "${1:-}" in --version) echo "v20.10.0" ;; esac
      ;;
    npm)
      # npm install -g vercel → succeed silently
      :
      ;;
    brew)
      # brew install node → succeed silently
      :
      ;;
    sudo)
      shift
      deploy::__mock "$@"
      ;;
    vercel)
      case "${1:-}" in
        --version) echo "Vercel CLI 33.0.0" ;;
        whoami)
          # Honor a mock auth toggle: HTML_SKILLS_MOCK_AUTHED=1 means authed.
          if [ "${HTML_SKILLS_MOCK_AUTHED:-0}" = "1" ]; then
            echo "mock-user@example.com"
            return 0
          else
            echo "Not authenticated" >&2
            return 1
          fi
          ;;
        login)
          # Flip the mock to authed after "login" — UNLESS the test
          # has asked us to simulate auth never landing.
          if [ "${HTML_SKILLS_MOCK_LOGIN_BROKEN:-0}" != "1" ]; then
            export HTML_SKILLS_MOCK_AUTHED=1
          fi
          ;;
        link)
          echo "Linked to mock-team/mock-project"
          ;;
        --prod|deploy)
          echo "https://mock-deploy-$(date -u +%s).vercel.app"
          ;;
        alias) echo "Aliased." ;;
        ls)
          if [ "${2:-}" = "--json" ]; then
            echo '[{"url":"mock-deploy.vercel.app"}]'
          fi
          ;;
        *) : ;;
      esac
      ;;
    timeout|gtimeout)
      shift
      deploy::__mock "$@"
      ;;
    *)
      : # no-op for anything else
      ;;
  esac
  return 0
}

# ── CLI entrypoint ───────────────────────────────────────────────────────
# Only execute if this file is invoked directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  log::set_run_id "deploy"
  case "${1:-status}" in
    status) shift; deploy::status "$@" ;;
    check)  shift; deploy::check "$@" ;;
    setup)  shift; deploy::setup "$@" ;;
    ship)   shift; deploy::ship  "$@" ;;
    reset)  shift; deploy::reset "$@" ;;
    -h|--help|help)
      sed -n '2,40p' "${BASH_SOURCE[0]}"
      ;;
    *)
      log::fail "Unknown command: $1"
      log::dim "Try: status | check | setup | ship | reset"
      exit 2
      ;;
  esac
fi

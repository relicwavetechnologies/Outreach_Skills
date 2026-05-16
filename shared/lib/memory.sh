#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / memory.sh
#  Initializes and manages ~/.cache/html-skills/ memory + state.
#
#  Source it:  . "$HTML_SKILLS_LIB/memory.sh"
#
#  Directory layout this file is responsible for:
#    ~/.cache/html-skills/
#      memory/
#        profile.json           # canonical user/company profile
#        voice.json             # learned voice attributes
#        patterns.json          # distilled rules across runs
#        targets/               # per-target context (acme-corp.json, ...)
#        runs/                  # per-run logs ({run_id}.json)
#        outcomes/feedback.jsonl
#      state/
#        deploy.json            # vercel setup state (single source of truth)
#      last-error.md            # written on failure by log.sh
#
#  Public functions:
#    memory::init                       # create skeleton if missing (idempotent)
#    memory::root                       # echo cache root
#    memory::state_file <name>          # echo path to state/<name>.json
#    memory::read_state <name>          # cat state/<name>.json (empty {} if missing)
#    memory::write_state <name> <json>  # atomic write
#    memory::get <name> <jq-path>       # read a field via jq (empty if missing)
#    memory::set <name> <jq-path> <val> # set a field via jq; <val> is a JSON literal
#    memory::log_run <run.json>         # append/save a run record
#    memory::slugify <text>             # slug for filenames
# ──────────────────────────────────────────────────────────────────────────

if [ -n "${__HTML_SKILLS_MEMORY_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_MEMORY_LOADED=1

# Locate log.sh (sibling file). Skills set HTML_SKILLS_LIB explicitly.
if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HTML_SKILLS_LIB
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"

memory::root() {
  printf "%s\n" "${HTML_SKILLS_CACHE:-${HOME}/.cache/html-skills}"
}

memory::init() {
  local root
  root="$(memory::root)"
  mkdir -p \
    "${root}/memory/targets" \
    "${root}/memory/runs" \
    "${root}/memory/outcomes" \
    "${root}/state"

  # Seed structured files if absent. Use jq to write valid JSON.
  local m="${root}/memory"
  [ -f "${m}/profile.json" ]   || echo '{}'      > "${m}/profile.json"
  [ -f "${m}/voice.json" ]     || echo '{}'      > "${m}/voice.json"
  [ -f "${m}/patterns.json" ]  || echo '{}'      > "${m}/patterns.json"
  [ -f "${m}/outcomes/feedback.jsonl" ] || : > "${m}/outcomes/feedback.jsonl"

  # Deploy state — phase-driven state machine. See deploy.sh for transitions.
  local s="${root}/state/deploy.json"
  if [ ! -f "$s" ]; then
    cat > "$s" <<'JSON'
{
  "phase": "fresh",
  "project": null,
  "scope": null,
  "auth_account": null,
  "custom_domain": null,
  "webhook": null,
  "vercel_cli_path": null,
  "node_version": null,
  "auth_last_verified": null,
  "last_deploy": null,
  "last_error": null
}
JSON
  fi
}

memory::state_file() {
  local name="${1:?state name required}"
  printf "%s\n" "$(memory::root)/state/${name}.json"
}

memory::read_state() {
  local name="${1:?state name required}"
  local f
  f="$(memory::state_file "$name")"
  if [ -f "$f" ]; then
    cat "$f"
  else
    echo '{}'
  fi
}

# Atomic write via temp file + mv.
memory::write_state() {
  local name="${1:?state name required}"
  local json="${2:?json required}"
  local f
  f="$(memory::state_file "$name")"
  mkdir -p "$(dirname "$f")"
  local tmp="${f}.tmp.$$"
  printf "%s" "$json" > "$tmp"
  mv "$tmp" "$f"
}

# Get a JSON field via jq path. Returns empty string if jq missing or path absent.
memory::get() {
  local name="${1:?state name required}"
  local path="${2:?jq path required}"
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  memory::read_state "$name" | jq -r "${path} // empty" 2>/dev/null || true
}

# Set a JSON field. <val> must be a JSON literal (e.g. '"acme"', 'null', '42', 'true').
memory::set() {
  local name="${1:?state name required}"
  local path="${2:?jq path required}"
  local val="${3:?value required}"
  if ! command -v jq >/dev/null 2>&1; then
    log::warn "jq not installed — can't update ${name} (${path})"
    return 1
  fi
  local current updated
  current="$(memory::read_state "$name")"
  updated="$(printf "%s" "$current" | jq "${path} = ${val}")" || {
    log::fail "jq failed updating ${name} (${path})"
    return 1
  }
  memory::write_state "$name" "$updated"
}

# Save a run record. Input: full JSON on stdin OR file path as $1.
memory::log_run() {
  local src="${1:-}"
  local id="${HTML_SKILLS_RUN_ID:-run-$(date -u +%s)}"
  local dest="$(memory::root)/memory/runs/${id}.json"
  mkdir -p "$(dirname "$dest")"
  if [ -n "$src" ] && [ -f "$src" ]; then
    cp "$src" "$dest"
  else
    cat > "$dest"
  fi
  printf "%s\n" "$dest"
}

# Slugify: lowercase, alphanum + hyphen only, collapse repeats.
memory::slugify() {
  local s="$*"
  s="$(printf "%s" "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf "%s" "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  printf "%s\n" "$s"
}

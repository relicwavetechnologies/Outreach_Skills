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

# ─────────────────────────────────────────────────────────────────────────
#  Target memory — per-entity knowledge (companies, founders, prospects)
#  Schema documented in shared/SCHEMAS.md.
# ─────────────────────────────────────────────────────────────────────────

memory::target_path() {
  local slug="${1:?slug required}"
  printf "%s\n" "$(memory::root)/memory/targets/${slug}.json"
}

# Read a target. Returns {} if missing.
memory::read_target() {
  local slug="${1:?slug required}"
  local f
  f="$(memory::target_path "$slug")"
  if [ -f "$f" ]; then
    cat "$f"
  else
    echo '{}'
  fi
}

# Atomic write — full overwrite.
memory::write_target() {
  local slug="${1:?slug required}"
  local json="${2:?json required}"
  local f
  f="$(memory::target_path "$slug")"
  mkdir -p "$(dirname "$f")"
  local tmp="${f}.tmp.$$"
  printf "%s" "$json" > "$tmp"
  mv "$tmp" "$f"
}

# Initialize a target file with a baseline structure if missing.
# Args: <slug> <display-name>
memory::init_target() {
  local slug="${1:?slug required}"
  local name="${2:-$slug}"
  local f
  f="$(memory::target_path "$slug")"
  if [ ! -f "$f" ]; then
    if ! command -v jq >/dev/null 2>&1; then
      log::warn "jq not installed — initializing $slug as empty object"
      memory::write_target "$slug" '{}'
      return 0
    fi
    local skeleton
    skeleton="$(jq -n --arg s "$slug" --arg n "$name" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
      slug: $s,
      name: $n,
      urls: {},
      created_at: $t,
      last_researched: null,
      research_freshness_score: 0,
      facts: [],
      people: [],
      past_outreach: [],
      do_not_use_angles: [],
      user_corrections: []
    }')"
    memory::write_target "$slug" "$skeleton"
  fi
}

# Deep-merge a JSON patch into a target.
# Reads patch from stdin OR from $2 (file path).
# Semantics: jq * (recursive merge). Arrays in the patch REPLACE existing
# arrays — use memory::add_fact / memory::add_person to append instead.
memory::merge_target() {
  local slug="${1:?slug required}"
  local patch_file="${2:-}"
  if ! command -v jq >/dev/null 2>&1; then
    log::warn "jq not installed — can't merge target $slug"
    return 1
  fi
  local current patch merged
  current="$(memory::read_target "$slug")"
  if [ -n "$patch_file" ] && [ -f "$patch_file" ]; then
    patch="$(cat "$patch_file")"
  else
    patch="$(cat)"
  fi
  merged="$(jq -n --argjson a "$current" --argjson b "$patch" '$a * $b')" || {
    log::fail "jq merge failed for $slug"
    return 1
  }
  memory::write_target "$slug" "$merged"
}

# Append a fact. Deduplicates on .claim.
# Args: <slug> <claim> <source> <confidence: high|medium|low>
memory::add_fact() {
  local slug="${1:?slug required}"
  local claim="${2:?claim required}"
  local source="${3:?source required}"
  local conf="${4:-medium}"
  if ! command -v jq >/dev/null 2>&1; then
    log::warn "jq not installed — can't add fact to $slug"
    return 1
  fi
  memory::init_target "$slug" "$slug"
  local current updated
  current="$(memory::read_target "$slug")"
  updated="$(printf "%s" "$current" | jq \
    --arg c "$claim" --arg s "$source" --arg k "$conf" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .facts = (
      (.facts // [])
      | map(select(.claim != $c))
      | . + [{claim: $c, source: $s, confidence: $k, fetched: $t}]
    )
  ')" || return 1
  memory::write_target "$slug" "$updated"
}

# Append a person. Dedupes on .linkedin OR .name+.role.
# Args: <slug> <name> <role> [linkedin]
memory::add_person() {
  local slug="${1:?slug required}"
  local name="${2:?name required}"
  local role="${3:?role required}"
  local linkedin="${4:-}"
  if ! command -v jq >/dev/null 2>&1; then
    log::warn "jq not installed — can't add person to $slug"
    return 1
  fi
  memory::init_target "$slug" "$slug"
  local current updated
  current="$(memory::read_target "$slug")"
  updated="$(printf "%s" "$current" | jq \
    --arg n "$name" --arg r "$role" --arg l "$linkedin" '
    .people = (
      (.people // [])
      | map(select(
          (if $l != "" then .linkedin != $l else (.name != $n or .role != $r) end)
        ))
      | . + [{name: $n, role: $r, linkedin: $l}]
    )
  ')" || return 1
  memory::write_target "$slug" "$updated"
}

# Append a past outreach attempt.
# Args: <slug> <run_id> <url> <angle> <outcome>
memory::add_outreach() {
  local slug="${1:?slug required}"
  local rid="${2:?run_id required}"
  local url="${3:?url required}"
  local angle="${4:?angle required}"
  local outcome="${5:-pending}"
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  memory::init_target "$slug" "$slug"
  local current updated
  current="$(memory::read_target "$slug")"
  updated="$(printf "%s" "$current" | jq \
    --arg r "$rid" --arg u "$url" --arg a "$angle" --arg o "$outcome" \
    --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .past_outreach = ((.past_outreach // []) + [{run_id: $r, url: $u, angle: $a, outcome: $o, at: $t}])
  ')" || return 1
  memory::write_target "$slug" "$updated"
}

# Mark research freshness — call after a successful research pass.
# Args: <slug> [freshness_score 0..1]
memory::mark_researched() {
  local slug="${1:?slug required}"
  local score="${2:-1.0}"
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  memory::init_target "$slug" "$slug"
  local current updated
  current="$(memory::read_target "$slug")"
  updated="$(printf "%s" "$current" | jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$score" '
    .last_researched = $t
    | .research_freshness_score = ($s | tonumber)
  ')" || return 1
  memory::write_target "$slug" "$updated"
}

# ─────────────────────────────────────────────────────────────────────────
#  Run logging — every skill emits one record per execution.
#  Schema in shared/SCHEMAS.md.
# ─────────────────────────────────────────────────────────────────────────

# Save a run record from stdin (JSON) or from a file path.
# Returns the path on stdout.
memory::write_run() {
  local src="${1:-}"
  local id="${HTML_SKILLS_RUN_ID:-run-$(date -u +%Y%m%d-%H%M%S)-$$}"
  local dest="$(memory::root)/memory/runs/${id}.json"
  mkdir -p "$(dirname "$dest")"
  if [ -n "$src" ] && [ -f "$src" ]; then
    cp "$src" "$dest"
  else
    cat > "$dest"
  fi
  printf "%s\n" "$dest"
}

# Backwards-compat alias (used by p0 deploy code paths).
memory::log_run() { memory::write_run "$@"; }

# Quick run logger — convenient one-shot. Pass key=value pairs.
# Numeric values (matching ^[0-9.]+$) are encoded as JSON numbers,
# booleans as JSON true/false, everything else as strings.
#   memory::quick_run skill=research-html target_slug=acme-corp duration_s=42
memory::quick_run() {
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  local args=()
  args+=(-n --arg run_id "${HTML_SKILLS_RUN_ID:-run-$(date -u +%Y%m%d-%H%M%S)-$$}")
  args+=(--arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
  local filter='{run_id: $run_id, started_at: $started_at'
  for kv in "$@"; do
    local k="${kv%%=*}"
    local v="${kv#*=}"
    if [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
      args+=(--argjson "$k" "$v")
      filter+=", $k: \$$k"
    elif [ "$v" = "true" ] || [ "$v" = "false" ] || [ "$v" = "null" ]; then
      args+=(--argjson "$k" "$v")
      filter+=", $k: \$$k"
    else
      args+=(--arg "$k" "$v")
      filter+=", $k: \$$k"
    fi
  done
  filter+='}'
  jq "${args[@]}" "$filter" | memory::write_run
}

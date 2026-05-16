#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  html-skills / track.sh
#  Wires the tracker into generated pages, scaffolds the user's server,
#  and syncs events from Vercel KV back into ~/.cache/html-skills/memory/.
#
#  Source it:  . "$HTML_SKILLS_LIB/track.sh"
#
#  State lives at ~/.cache/html-skills/state/track.json:
#    {
#      "enabled": true|false,
#      "endpoint": "https://your-track.vercel.app/api/track",
#      "shared_key": "<short random string>",
#      "kv_project": "<vercel project name>",
#      "last_synced": "<iso8601>"
#    }
#
#  Public functions:
#    track::status                    — print current tracking state
#    track::enable                    — flip enabled=true (server must already exist)
#    track::disable                   — flip enabled=false (skills stop injecting)
#    track::is_enabled                — exit 0 if enabled, non-zero otherwise
#    track::inject <html-file> <run_id>
#                                     — inject the configured tracker into a page
#                                       (in-place; no-op if not enabled)
#    track::setup --project NAME      — scaffold + deploy the serverless function
#                                       (writes api/track.js, deploys via deploy.sh,
#                                       prompts user to enable Vercel KV)
#    track::sync [--run RUN_ID]       — pull events from KV → feedback.jsonl
#                                       (requires curl + jq + Vercel KV REST creds
#                                        which the user must set as KV_REST_API_URL
#                                        and KV_REST_API_TOKEN in their env)
# ──────────────────────────────────────────────────────────────────────────

if [ -n "${__HTML_SKILLS_TRACK_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
__HTML_SKILLS_TRACK_LOADED=1

if [ -z "${HTML_SKILLS_LIB:-}" ]; then
  HTML_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export HTML_SKILLS_LIB
fi
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/log.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/memory.sh"
# shellcheck source=/dev/null
. "${HTML_SKILLS_LIB}/outcomes.sh"

memory::init

# Track state lives in its own file (not deploy.json).
track::__state_file() { printf "%s\n" "$(memory::root)/state/track.json"; }

track::__init() {
  local f
  f="$(track::__state_file)"
  if [ ! -f "$f" ]; then
    cat > "$f" <<'JSON'
{
  "enabled": false,
  "endpoint": null,
  "shared_key": null,
  "kv_project": null,
  "last_synced": null
}
JSON
  fi
}
track::__init

track::__get() {
  local path="${1:?path required}"
  command -v jq >/dev/null 2>&1 || return 0
  jq -r "${path} // empty" "$(track::__state_file)" 2>/dev/null || true
}

track::__set() {
  local path="${1:?path required}"
  local val="${2:?value required}"
  command -v jq >/dev/null 2>&1 || return 1
  local f tmp
  f="$(track::__state_file)"
  tmp="${f}.tmp.$$"
  jq "${path} = ${val}" "$f" > "$tmp" && mv "$tmp" "$f"
}

track::status() {
  log::title "tracking state"
  log::dim "enabled:     $(track::__get '.enabled')"
  log::dim "endpoint:    $(track::__get '.endpoint')"
  log::dim "kv_project:  $(track::__get '.kv_project')"
  log::dim "last_synced: $(track::__get '.last_synced')"
}

track::is_enabled() {
  local e
  e="$(track::__get '.enabled')"
  [ "$e" = "true" ]
}

track::enable() {
  if [ -z "$(track::__get '.endpoint')" ]; then
    log::fail "Can't enable — no endpoint configured. Run: track.sh setup --project NAME"
    return 2
  fi
  track::__set '.enabled' 'true'
  log::ok "Tracker enabled. Skills will inject track.js into deployed pages."
}

track::disable() {
  track::__set '.enabled' 'false'
  log::ok "Tracker disabled. Skills will skip injection. (Existing live pages still fire — re-deploy them to stop.)"
}

# Inject the tracker into <html-file> by replacing placeholder tokens and
# adding the <script> just before </body>. In-place edit.
# Args: <html-file> <run_id>
# No-op if tracker is disabled.
track::inject() {
  local file="${1:?html file required}"
  local run_id="${2:?run_id required}"
  if [ ! -f "$file" ]; then
    log::fail "track::inject — no such file: $file"
    return 2
  fi
  if ! track::is_enabled; then
    return 0
  fi

  local endpoint key
  endpoint="$(track::__get '.endpoint')"
  key="$(track::__get '.shared_key')"
  if [ -z "$endpoint" ]; then
    log::warn "Tracker enabled but no endpoint set — skipping injection"
    return 0
  fi

  # Locate the track.js component beside us (works for repo + installed layouts).
  local tjs
  for candidate in \
    "${HTML_SKILLS_LIB}/../components/track.js" \
    "${HTML_SKILLS_LIB}/../../shared/components/track.js" \
    "$(dirname "${HTML_SKILLS_LIB}")/components/track.js"; do
    if [ -f "$candidate" ]; then tjs="$candidate"; break; fi
  done
  if [ -z "${tjs:-}" ]; then
    log::warn "track.js not found — skipping injection"
    return 0
  fi

  # Build the configured snippet by replacing the three tokens.
  # Use a temp file so we can splice without word-splitting a multi-line
  # JS body (awk's -v can't carry literal newlines).
  local snippet_file
  snippet_file="$(mktemp -t htmlskills.snip.XXXXXX)"
  {
    printf '<script>\n'
    sed \
      -e "s|__TRACK_ENDPOINT__|${endpoint}|g" \
      -e "s|__TRACK_RUN_ID__|${run_id}|g" \
      -e "s|__TRACK_SHARED_KEY__|${key:-}|g" \
      "$tjs"
    printf '</script>\n'
  } > "$snippet_file"

  # Skip if already injected.
  if grep -q '__hs_sid' "$file"; then
    rm -f "$snippet_file"
    return 0
  fi

  # Insert just before </body>. awk reads the snippet line-by-line at the
  # point of splice (works with multi-line content because it's getline'd,
  # not interpolated).
  local tmp="${file}.tmp.$$"
  awk -v sfile="$snippet_file" '
    BEGIN { inserted = 0 }
    /<\/body>/ && !inserted {
      while ((getline line < sfile) > 0) print line
      close(sfile)
      inserted = 1
    }
    { print }
    END {
      if (!inserted) {
        while ((getline line < sfile) > 0) print line
        close(sfile)
      }
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  rm -f "$snippet_file"
}

# Pull events from Vercel KV → feedback.jsonl
# Requires: KV_REST_API_URL + KV_REST_API_TOKEN in env (Vercel exposes both
# when you enable KV on a project; copy into your shell once).
# Usage:
#   track::sync             — pull recent events globally
#   track::sync --run RID   — pull events for one run only
track::sync() {
  command -v curl >/dev/null 2>&1 || { log::fail "curl required"; return 10; }
  command -v jq   >/dev/null 2>&1 || { log::fail "jq required";   return 10; }

  if [ -z "${KV_REST_API_URL:-}" ] || [ -z "${KV_REST_API_TOKEN:-}" ]; then
    log::fail "KV_REST_API_URL / KV_REST_API_TOKEN not set in env."
    log::dim "Copy these from your Vercel project's KV → 'Quick Start' → '.env.local' tab."
    return 11
  fi

  local key="hs:recent"
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) key="hs:run:$2"; shift 2 ;;
      *) log::fail "Unknown flag: $1"; return 2 ;;
    esac
  done

  log::info "Syncing events from KV key: ${key}"

  # LRANGE 0 -1 returns the whole list.
  local raw
  if ! raw="$(curl -fsSL \
        -H "Authorization: Bearer ${KV_REST_API_TOKEN}" \
        "${KV_REST_API_URL}/lrange/${key}/0/-1" 2>/dev/null)"; then
    log::fail "KV fetch failed"
    return 12
  fi

  # Response shape: {"result":["<json-string>","<json-string>", ...]}
  # Each list item was lpush'd as a JSON STRING by the serverless fn.
  local out="$(memory::root)/memory/outcomes/feedback.jsonl"
  mkdir -p "$(dirname "$out")"

  # De-dupe against what's already in feedback.jsonl using (run_id, session, event, at).
  local existing_keys
  existing_keys="$(mktemp)"
  if [ -s "$out" ]; then
    jq -r '[(.run_id // ""), (.session // ""), (.event // ""), (.at // "")] | @tsv' "$out" 2>/dev/null > "$existing_keys" || :
  fi

  local added=0 dups=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local k
    k="$(printf '%s' "$line" | jq -r '[(.run_id // ""), (.session // ""), (.event // ""), (.at // "")] | @tsv' 2>/dev/null)"
    if grep -Fxq -- "$k" "$existing_keys" 2>/dev/null; then
      dups=$((dups+1))
    else
      printf '%s\n' "$line" >> "$out"
      printf '%s\n' "$k"    >> "$existing_keys"
      added=$((added+1))
    fi
  done < <(printf '%s' "$raw" | jq -r '.result[]? // empty')

  rm -f "$existing_keys"

  track::__set '.last_synced' "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  log::ok "Sync done: +${added} new, ${dups} duplicates."
}

# Setup wizard: scaffolds api/track.js, deploys it, captures the URL.
# Usage: track::setup --project NAME [--shared-key KEY]
track::setup() {
  local project="" key=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project)    project="$2"; shift 2 ;;
      --shared-key) key="$2";     shift 2 ;;
      *) log::fail "Unknown flag: $1"; return 2 ;;
    esac
  done
  if [ -z "$project" ]; then
    log::fail "Usage: track.sh setup --project NAME [--shared-key KEY]"
    return 2
  fi
  # Generate a random key if not provided.
  if [ -z "$key" ]; then
    if command -v openssl >/dev/null 2>&1; then
      key="$(openssl rand -hex 12)"
    else
      key="$(printf '%s' "$(date -u +%s%N)$RANDOM" | shasum -a 256 | head -c 24)"
    fi
  fi

  # Locate track-server.js.
  local svr
  for candidate in \
    "${HTML_SKILLS_LIB}/../components/track-server.js" \
    "${HTML_SKILLS_LIB}/../../shared/components/track-server.js" \
    "$(dirname "${HTML_SKILLS_LIB}")/components/track-server.js"; do
    if [ -f "$candidate" ]; then svr="$candidate"; break; fi
  done
  if [ -z "${svr:-}" ]; then
    log::fail "track-server.js not found in components/"
    return 12
  fi

  # Scaffold a tiny project.
  local work
  work="$(memory::root)/track-setup/${project}"
  mkdir -p "$work/api"
  cp "$svr" "$work/api/track.js"
  cat > "$work/package.json" <<JSON
{
  "name": "${project}",
  "private": true,
  "type": "module",
  "dependencies": { "@vercel/kv": "^2.0.0" }
}
JSON
  cat > "$work/vercel.json" <<'JSON'
{ "buildCommand": "", "outputDirectory": ".", "framework": null }
JSON
  cat > "$work/README.md" <<EOF
# ${project}

html-skills tracking endpoint.

One-time setup:
1. \`cd ${work}\`
2. \`vercel link --project ${project}\`
3. In Vercel dashboard: enable **KV** on this project.
4. \`vercel env add HTML_SKILLS_TRACK_KEY production\` and paste: \`${key}\`
5. \`vercel --prod\` — copy the deployed URL + \`/api/track\`
6. Paste that URL when prompted, or run: \`track.sh enable\` after setting endpoint manually.

Local sync requires KV_REST_API_URL and KV_REST_API_TOKEN in your shell
(copy from the project's KV "Quick Start" tab).
EOF

  log::title "Track setup scaffolded"
  log::ok "Project files at: ${work}"
  log::dim "Next steps printed in ${work}/README.md"
  log::dim "Shared key generated: ${key}"
  log::dim "After deploying, run:  track.sh enable    (after you paste the endpoint URL)"

  # Save the partial state — user will fill endpoint after manual deploy.
  track::__set '.kv_project'  "\"${project}\""
  track::__set '.shared_key'  "\"${key}\""
}

# CLI entrypoint.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-status}" in
    status)  shift; track::status  "$@" ;;
    enable)  shift; track::enable  "$@" ;;
    disable) shift; track::disable "$@" ;;
    inject)  shift; track::inject  "$@" ;;
    setup)   shift; track::setup   "$@" ;;
    sync)    shift; track::sync    "$@" ;;
    set-endpoint)
      shift
      url="${1:?endpoint url required}"
      track::__set '.endpoint' "\"${url}\""
      log::ok "Endpoint saved. Run: track.sh enable"
      ;;
    -h|--help|help|*)
      sed -n '2,40p' "${BASH_SOURCE[0]}"
      ;;
  esac
fi

# shellcheck shell=bash
# Sourced by the loops. Builds relay bodies and POSTs them to the
# paseo-result-relay webhook.
#
#   relay_body <kind> <fields...>      print the 5-line body for one loop event
#   relay_post <body-file-or-string>   POST it; 0 only on HTTP 2xx or dry-run
#   relay_fire <state.json> <key> <body>
#                                      POST once per key; the key is saved only
#                                      after relay_post returns 0
#   relay_mode                         print live or dry-run
#   take_lock <file>                   0 when this shell now holds the lock
#
# Env: PASEO_RELAY_URL, PASEO_RELAY_AUTH (one full "Name: value" header line).
# Either one empty, or RELAY_DRY=1, means dry-run: log the body, POST nothing.
# The caller defines log().

relay_mode() {
  if [ "${RELAY_DRY:-}" = 1 ] || [ -z "${PASEO_RELAY_URL:-}" ] || [ -z "${PASEO_RELAY_AUTH:-}" ]; then
    echo dry-run
  else
    echo live
  fi
}

_relay_one_line() {
  local v=${1//$'\r'/ }
  printf '%s' "${v//$'\n'/ }"
}

# The one table from loop event to relay body.
#   mem_free         <host> <reading> <ticket> <lead>
#   mem_held         <host> <reading> <ticket> <lead> <held_min>
#   mem_wait_timeout <host> <hours> <ticket> <lead>
#   mergify_drop     <repo> <pr_number> <head_sha> <reason>
relay_body() {
  local kind=$1 status ticket lead pr head verdict ask url
  shift
  case "$kind" in
    mem_free)
      status=ready ticket=$3 lead=$4 pr=none head=none
      verdict="memwait: $1 memory free ($2), held start can go"
      ask=none ;;
    mem_held)
      status=question ticket=$3 lead=$4 pr=none head=none
      verdict="memwait: $1 start held $5 min ($2)"
      ask="keep waiting or start $3 anyway?" ;;
    mem_wait_timeout)
      status=failed ticket=$3 lead=$4 pr=none head=none
      verdict="memwait: $1 gave up after $2 h held"
      ask="start $3 by hand or drop it?" ;;
    mergify_drop)
      url="https://github.com/$1/pull/$2"
      status=failed ticket=$url lead=none pr=$url head=$3
      verdict="mergify-watch: $1#$2 left the merge queue"
      ask=$(_relay_one_line "$4"); ask=${ask:0:200} ;;
    *) echo "relay_body: unknown kind $kind" >&2; return 1 ;;
  esac
  printf 'status: %s\nticket: %s lead: %s\npr: %s head: %s\nverdict: %s\nask: %s\n' \
    "$status" "$(_relay_one_line "$ticket")" "$(_relay_one_line "$lead")" \
    "$(_relay_one_line "$pr")" "$(_relay_one_line "$head")" \
    "$(_relay_one_line "$verdict")" "$ask"
}

relay_post() {
  local body=$1 code url
  [ -f "$body" ] && body=$(cat "$body")
  if [ "$(relay_mode)" = dry-run ]; then
    log "DRY-RUN ${body//$'\n'/ | }"
    return 0
  fi
  # The URL goes in through a curl config file and the header through a header
  # file, both process substitutions, so neither shows up in curl's argv.
  url=${PASEO_RELAY_URL//\\/\\\\}
  url=${url//\"/\\\"}
  code=$(printf '%s\n' "$body" | curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 20 -X POST \
    -K <(printf 'url = "%s"\n' "$url") \
    -H 'Content-Type: text/plain' \
    -H @<(printf '%s\n' "$PASEO_RELAY_AUTH") \
    --data-binary @- 2>/dev/null) || true
  log "relay http=${code:-000}"
  [[ "$code" == 2?? ]]
}

relay_fire() {
  local state=$1 key=$2 body=$3
  [ -s "$state" ] && jq -e 'type=="object"' "$state" >/dev/null 2>&1 || echo '{}' > "$state"
  if jq -e --arg k "$key" 'has($k)' "$state" >/dev/null; then
    log "already sent: $key"
    return 0
  fi
  relay_post "$body" || return 1
  jq --arg k "$key" --arg t "$(date '+%Y-%m-%dT%H:%M:%S%z')" '.[$k]=$t' "$state" > "$state.tmp" \
    && mv -f "$state.tmp" "$state"
}

# A pid file lock. macOS has no flock, and shlock refuses to replace a lock
# file whose mtime is recent even when its pid is dead. noclobber makes the
# create atomic. A stale file is renamed away first, so only one taker wins it.
take_lock() {
  local f=$1 pid
  ( set -o noclobber; echo $$ > "$f" ) 2>/dev/null && return 0
  pid=$(cat "$f" 2>/dev/null) || pid=
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null && return 1
  mv -f "$f" "$f.stale.$$" 2>/dev/null || return 1
  rm -f "$f.stale.$$"
  ( set -o noclobber; echo $$ > "$f" ) 2>/dev/null
}

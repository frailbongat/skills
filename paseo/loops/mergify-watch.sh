#!/usr/bin/env bash
# How Mergify shows queue state on Project-Lit/litflows (checked 2026-10-28):
#  - Check run "Mergify Merge Queue" on the PR head is IN_PROGRESS or QUEUED
#    while queued, COMPLETED+SUCCESS when merged (#921), COMPLETED+NEUTRAL
#    when dropped (#970).
#  - mergify[bot] posts "Mergify Payload" comments holding JSON:
#    {"state":"merged"|"dequeued"|..., "left_at":..., "dequeue_reason":{"code","message"}}.
#    A PR can carry more than one (#970 and #1085 each have two), so the watcher
#    reads the newest by updated_at. Any "dequeued" counts as a drop, whatever
#    the code (CONFLICT_WITH_BASE_BRANCH, PR_DEQUEUED, CHECKS_FAILED).
set -u

usage() {
  cat >&2 <<'EOF'
usage: mergify-watch.sh [--once]

Watches the Mergify merge queue with read-only gh and fires one failed relay
event per drop. --once runs a single tick.

Env: MW_REPO (Project-Lit/litflows), MW_INTERVAL (300), PASEO_LOOPS_HOME
(~/.paseo/loops), PASEO_RELAY_URL and PASEO_RELAY_AUTH (see relay.sh).
Test hook: MW_FIXTURES=<dir> reads list.json (gh pr list output) and
comments_<n>.json (comments array) from <dir>, and appends one line to
<dir>/calls per gh call.
EOF
  exit "${1:-2}"
}

case "${1:-}" in
  "") ONCE=0 ;;
  --once) ONCE=1 ;;
  -h|--help) usage 0 ;;
  *) usage ;;
esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=paseo/loops/relay.sh
. "$HERE/relay.sh"

D="${PASEO_LOOPS_HOME:-$HOME/.paseo/loops}/mergify-watch"
mkdir -p "$D"
REPO="${MW_REPO:-Project-Lit/litflows}"
INT="${MW_INTERVAL:-300}"
STATE="$D/state.json" SEEN="$D/seen.json" LOG="$D/log" HB="$D/heartbeat"
FIX="${MW_FIXTURES:-}"

log() {
  local sz
  sz=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
  [ "$sz" -gt 262144 ] && mv -f "$LOG" "$LOG.1"
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"
}
beat() { date +%s > "$HB.tmp.$$" && mv -f "$HB.tmp.$$" "$HB"; }

with_timeout() { # seconds cmd...; macOS has no timeout(1), so use gtimeout when brew coreutils has it
  local s=$1
  shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout -k 5 "$s" "$@"; else "$@"; fi
}

take_lock "$D/watch.lock" || { log "another watcher holds watch.lock; exit"; exit 0; }
trap 'release_lock "$D/watch.lock"' EXIT
trap 'exit 143' TERM INT

[ -s "$STATE" ] && jq -e 'type=="object"' "$STATE" >/dev/null 2>&1 || echo '{}' > "$STATE"
[ -s "$SEEN" ] && jq -e 'type=="object"' "$SEEN" >/dev/null 2>&1 || echo '{}' > "$SEEN"

ghlist() {
  if [ -n "$FIX" ]; then echo list >> "$FIX/calls"; cat "$FIX/list.json" 2>/dev/null; return; fi
  with_timeout 90 gh pr list --repo "$REPO" --state open --limit 200 \
    --json number,headRefOid,statusCheckRollup < /dev/null 2>/dev/null
}

ghpayload() {
  local c
  if [ -n "$FIX" ]; then
    echo "comments $1" >> "$FIX/calls"
    c=$(cat "$FIX/comments_$1.json" 2>/dev/null) || return 1
  else
    c=$(with_timeout 60 gh api "repos/$REPO/issues/$1/comments?per_page=100" < /dev/null 2>/dev/null) || return 1
  fi
  jq -ce '[.[]|select(.user.login=="mergify[bot]" and (.body|test("Mergify Payload")))]|sort_by(.updated_at)|last
    |.body|capture("Payload -\\*-\\s*(?<j>\\{.*\\})")|.j|fromjson' <<<"$c" 2>/dev/null
}

seen_del() { jq --arg n "$1" 'del(.[$n])' "$SEEN" > "$SEEN.tmp" && mv -f "$SEEN.tmp" "$SEEN"; }

QQ='[.statusCheckRollup[]?|select(.name=="Mergify Merge Queue")]|sort_by(.startedAt)|last'

tick() {
  local list n v head qs qc p reason left body
  if [ -z "$FIX" ] && ! command -v gh >/dev/null 2>&1; then
    log "gh not found on PATH=$PATH; retry next tick"
    return
  fi
  if ! list=$(ghlist) || ! jq -e 'type=="array"' >/dev/null 2>&1 <<<"$list"; then
    log "gh pr list failed; retry next tick"
    return
  fi
  for n in $(jq -r "[.[]|select(($QQ|.status//\"\")|test(\"^(QUEUED|IN_PROGRESS|PENDING|WAITING|REQUESTED)\$\"))|.number]|.[]" <<<"$list"); do
    jq -e --arg n "$n" 'has($n)' "$SEEN" >/dev/null && continue
    jq --arg n "$n" --arg t "$(date '+%Y-%m-%dT%H:%M:%S%z')" '.[$n]=$t' "$SEEN" > "$SEEN.tmp" && mv -f "$SEEN.tmp" "$SEEN"
    log "pr=$n queued; watching"
  done
  for n in $(jq -r 'keys[]' "$SEEN" | sort -n); do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    v=$(jq -c --argjson n "$n" '.[]|select(.number==$n)' <<<"$list")
    if [ -z "$v" ]; then log "pr=$n not open; stop watching"; seen_del "$n"; continue; fi
    head=$(jq -r .headRefOid <<<"$v")
    read -r qs qc < <(jq -r "$QQ"'|"\(.status//"none") \(.conclusion//"none")"' <<<"$v")
    if [ "$qs" = COMPLETED ] && [ "$qc" = SUCCESS ]; then log "pr=$n queue check SUCCESS; merge listener handles it"; continue; fi
    if [ "$qs" != COMPLETED ] && [ "$qs" != none ]; then log "pr=$n queue check $qs; waiting"; continue; fi
    p=$(ghpayload "$n") || { log "pr=$n queue check $qs/$qc, payload read failed or unclear; retry next tick"; continue; }
    [ "$(jq -r .state <<<"$p")" = dequeued ] || { log "pr=$n payload state $(jq -r .state <<<"$p"); no drop"; continue; }
    reason=$(jq -r '[.dequeue_reason.code, .dequeue_reason.message]|map(select(.!=null))|join(": ")|.[0:200]' <<<"$p")
    [ -n "$reason" ] || reason=dequeued
    left=$(jq -r '.left_at // "none" | tostring' <<<"$p")
    body=$(relay_body mergify_drop "$REPO" "$n" "$head" "$reason")
    if relay_fire "$STATE" "mergify_drop|https://github.com/$REPO/pull/$n|$head|$left|$reason" "$body"; then
      seen_del "$n"
      log "pr=$n drop sent ($(relay_mode)): $reason"
    else
      log "pr=$n POST failed; retry next tick"
    fi
  done
}

log "start pid=$$ repo=$REPO mode=$(relay_mode) once=$ONCE interval=${INT}s"
while :; do
  beat
  tick
  beat
  [ "$ONCE" = 1 ] && exit 0
  sleep "$INT" &
  wait $!
done

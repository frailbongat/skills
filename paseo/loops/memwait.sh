#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=paseo/loops/relay.sh
. "$HERE/relay.sh"

D="${PASEO_LOOPS_HOME:-$HOME/.paseo/loops}/memwait"
mkdir -p "$D"
Q="$D/queue.json" STATE="$D/state.json" LOG="$D/log"
H="${MW_HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}"
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
LABEL=sh.frail.paseo-memwait
: "${MW_INTERVAL:=300}"
: "${MW_FREE_MIN:=25}"
: "${MW_HOLD_NOTE:=1800}"
: "${MW_TIMEOUT:=86400}"
: "${MW_TICKS:=0}"
case $MW_FREE_MIN in
  ''|*[!0-9]*) ok=0 ;;
  *) [ "$MW_FREE_MIN" -ge 1 ] && [ "$MW_FREE_MIN" -le 100 ] && ok=1 || ok=0 ;;
esac
[ "$ok" = 1 ] || { echo "error: MW_FREE_MIN=$MW_FREE_MIN must be a whole percent from 1 to 100, or the gate can never pass" >&2; exit 2; }
unset ok

trap 'release_lock "$D/queue.lock"; release_lock "$D/loop.lock"' EXIT
trap 'exit 143' TERM INT

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$H" "$*" >> "$LOG"; }

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") add <ticket_url> <lead_id> | status | resume

  add <ticket_url> <lead_id>   queue a held start, then start the waiter
  status                       print the queue and the last log lines
  resume                       run the waiter if the queue is not empty
                               (the LaunchAgent runs this at login)

Every MW_INTERVAL seconds ($MW_INTERVAL) the waiter reads \`memory_pressure -Q\`.
At MW_FREE_MIN percent free ($MW_FREE_MIN) it fires one ready event per held
ticket and drops it. A ticket held MW_HOLD_NOTE seconds ($MW_HOLD_NOTE) fires one
question event. A ticket held MW_TIMEOUT seconds ($MW_TIMEOUT) fires one failed
event and leaves the queue.

Env: MW_HOST (scutil LocalHostName), PASEO_LOOPS_HOME (~/.paseo/loops),
PASEO_RELAY_URL and PASEO_RELAY_AUTH (see relay.sh). RELAY_DRY=1 lets add run
with no relay env.
Test hooks: MW_CHECK=<cmd> prints a verdict=ok|held line in place of
memory_pressure. MW_TICKS=<n> exits after n ticks. LAUNCHCTL=<cmd>.
EOF
  exit "${1:-2}"
}

qlock() {
  local i
  for i in $(seq 1 100); do
    take_lock "$D/queue.lock" && return 0
    sleep 0.05
  done
  log "queue lock busy after 5 s (try $i)"
  return 1
}

qedit() {
  qlock || return 1
  [ -s "$Q" ] || echo '[]' > "$Q"
  jq "$@" "$Q" > "$Q.tmp" && mv -f "$Q.tmp" "$Q"
  local rc=$?
  release_lock "$D/queue.lock"
  return $rc
}

qempty() { [ ! -s "$Q" ] || [ "$(jq 'length' "$Q" 2>/dev/null || echo 0)" = 0 ]; }

check() {
  if [ -n "${MW_CHECK:-}" ]; then eval "$MW_CHECK" 2>&1 | tail -n 1; return; fi
  local min=$MW_FREE_MIN pct
  pct=$(memory_pressure -Q 2>/dev/null | sed -n 's/^System-wide memory free percentage: \([0-9][0-9]*\)%.*/\1/p')
  if [ -z "$pct" ]; then echo "verdict=unknown memory_pressure unreadable"
  elif [ "$pct" -ge "$min" ]; then echo "verdict=ok free=$pct% min=$min%"
  else echo "verdict=held free=$pct% min=$min%"; fi
}

qdrop() { qedit --arg t "$1" --argjson s "$2" 'map(select(.ticket!=$t or .since!=$s))'; }

tick() {
  local out reading now t l s noted age body
  out=$(check)
  reading=${out#verdict=* }
  now=$(date +%s)
  if [[ "$out" == *verdict=ok* ]]; then
    while IFS=$'\t' read -r t l s noted; do
      body=$(relay_body mem_free "$H" "$reading" "$t" "$l")
      relay_fire "$STATE" "mem_free|$t|$s|none" "$body" && qdrop "$t" "$s" \
        && log "freed $t: $out"
    done < <(jq -r '.[]|[.ticket,.lead,(.since|tostring),(.noted//false|tostring)]|@tsv' "$Q")
    return
  fi
  log "held: $out"
  while IFS=$'\t' read -r t l s noted; do
    age=$((now - s))
    if [ "$age" -ge "$MW_TIMEOUT" ]; then
      body=$(relay_body mem_wait_timeout "$H" "$((age / 3600))" "$t" "$l")
      relay_fire "$STATE" "mem_wait_timeout|$t|$s|none" "$body" && qdrop "$t" "$s" \
        && log "gave up on $t after $((age / 3600)) h"
    elif [ "$noted" != true ] && [ "$age" -ge "$MW_HOLD_NOTE" ]; then
      body=$(relay_body mem_held "$H" "$reading" "$t" "$l" "$((age / 60))")
      relay_fire "$STATE" "mem_held|$t|$s|none" "$body" \
        && qedit --arg t "$t" --argjson s "$s" 'map(if .ticket==$t and .since==$s then .noted=true else . end)' \
        && log "noted $t held $((age / 60)) min"
    fi
  done < <(jq -r '.[]|[.ticket,.lead,(.since|tostring),(.noted//false|tostring)]|@tsv' "$Q")
}

loop() {
  take_lock "$D/loop.lock" || { log "another waiter holds loop.lock; exit"; exit 0; }
  local ticks=0
  log "waiter start pid=$$ mode=$(relay_mode) interval=${MW_INTERVAL}s"
  while :; do
    qempty && { log "queue empty; exit"; exit 0; }
    tick
    ticks=$((ticks + 1))
    qempty && { log "queue empty; exit"; exit 0; }
    [ "$MW_TICKS" -gt 0 ] && [ "$ticks" -ge "$MW_TICKS" ] && { log "MW_TICKS=$ticks reached; exit"; exit 0; }
    sleep "$MW_INTERVAL" &
    wait $!
  done
}

case "${1:-}" in
  add)
    [ $# -eq 3 ] || usage
    agent=""
    for dom in gui user; do
      if "$LAUNCHCTL" print "$dom/$(id -u)/$LABEL" >/dev/null 2>&1; then agent="$dom/$(id -u)/$LABEL"; break; fi
    done
    if [ -z "$agent" ] && [ "$(relay_mode)" = dry-run ] && [ "${RELAY_DRY:-}" != 1 ]; then
      echo "error: no LaunchAgent and no relay env, so a waiter would drop $2 without telling anyone. Run paseo/loops/install.sh install memwait, or set RELAY_DRY=1 to dry-run." >&2
      exit 1
    fi
    qedit --arg t "$2" --arg l "$3" --argjson s "$(date +%s)" \
      'if any(.[]; .ticket==$t) then . else . + [{ticket:$t, lead:$l, since:$s}] end' || exit 1
    log "queued $2 lead=$3"
    # The LaunchAgent run gets the relay env from ~/.paseo-relay; this shell
    # may not have it. kickstart does nothing when the waiter already runs.
    if [ -n "$agent" ]; then
      "$LAUNCHCTL" kickstart "$agent" >/dev/null 2>&1
      echo "queued $2 on $H; kicked $agent"
    else
      # Not nohup: with no desktop login it exits "can't detach from console".
      # An ignored HUP stays ignored across exec.
      ( trap '' HUP; exec "$0" resume ) >/dev/null 2>&1 < /dev/null &
      echo "queued $2 on $H; waiter started in the background, mode=$(relay_mode)"
    fi ;;
  resume)
    qempty && exit 0
    loop ;;
  status)
    if qempty; then echo "queue empty"
    else jq -r --argjson n "$(date +%s)" '.[]|"\(.ticket) lead=\(.lead) held \((($n-.since)/60)|floor) min\(if .noted then " (noted)" else "" end)"' "$Q"; fi
    tail -n 5 "$LOG" 2>/dev/null ;;
  -h|--help) usage 0 ;;
  *) usage ;;
esac

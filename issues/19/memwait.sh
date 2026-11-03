#!/bin/bash
# Memory-gate waiter. Plain bash, zero model calls. Frail Oct 29 2026: a held start never wakes a bot on a timer.
# usage: memwait.sh add <MAC|REMOTE> <ticket_or_pr_link> <lead_agent_id>   (queue a held start; starts the host's loop if not running)
#        memwait.sh status | resume   (resume: restart loops for non-empty queues; the stop-poller watchdog calls it)
# Loop: every MW_INTERVAL s (default 300) runs memcheck.sh <HOST>. On verdict=ok it POSTs ONE event
#   {"kind":"mem_free","host":..,"held":[{ticket,lead,since}..]} to bellion's paseo-stop-event webhook, clears the queue, exits.
# A start held over 30 min gets ONE {"kind":"mem_held",...} event (bellion tells that lead once). Gives up after 24 h with one mem_wait_timeout.
# Test hooks: MW_CHECK=<cmd> replaces memcheck; MW_DRY=1 logs payloads instead of POSTing.
set -u
D=/workspace/paseo/memwait; B=/workspace/paseo/bin; mkdir -p "$D"
log(){ echo "$(date '+%F %T') [$H] $*" >> "$D/log"; }
post(){ # $1 json
  if [ -n "${MW_DRY:-}" ] || [ -z "${PASEO_EVENT_WEBHOOK_URL:-}" ] || [ -z "${PASEO_EVENT_WEBHOOK_KEY:-}" ]; then log "DRY-RUN $1"; return 0; fi
  local code; code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 -X POST -H 'Content-Type: application/json' \
    -H @<(printf 'Authorization: Bearer %s\nX-Webhook-Key: %s\n' "$PASEO_EVENT_WEBHOOK_KEY" "$PASEO_EVENT_WEBHOOK_KEY") \
    --data-binary "$1" "$PASEO_EVENT_WEBHOOK_URL" 2>/dev/null)
  log "POST http=$code kind=$(jq -r .kind <<<"$1")"; [[ "$code" == 2?? ]]
}
# Agent fallback in memcheck costs a model turn: allow it at most every MW_AGENT_EVERY s (default 900); other ticks run terminal-only.
check(){ if [ -n "${MW_CHECK:-}" ]; then eval "$MW_CHECK"; return; fi
  local f="$D/$H.agent_ts" n=$(date +%s) last; last=$(cat "$f" 2>/dev/null || echo 0)
  if [ $((n-last)) -ge "${MW_AGENT_EVERY:-900}" ]; then echo "$n" > "$f"; "$B/memcheck.sh" "$H"; else MEMCHECK_NO_AGENT=1 "$B/memcheck.sh" "$H"; fi; }
loop(){
  exec 9>"$D/$H.lock"; flock -n 9 || exit 0
  local start=$(date +%s) iv=${MW_INTERVAL:-300} out q now ev
  log "loop start"
  while :; do
    out=$(check 2>&1 | tail -1); now=$(date +%s); q="$D/$H.queue.json"
    [ -s "$q" ] || { log "queue empty; exit"; exit 0; }
    if [[ "$out" == *verdict=ok* ]]; then
      ev=$(jq -c --arg h "$H" --arg r "$out" '{kind:"mem_free",host:$h,reading:$r,held:[.[]|{ticket,lead,since}]}' "$q")
      post "$ev" && { rm -f "$q"; log "freed: $out"; exit 0; }
    else
      log "held: $out"
      for i in $(jq -r --argjson n "$now" 'to_entries[]|select((.value.noted|not) and ($n-.value.since)>1800)|.key' "$q"); do
        ev=$(jq -c --arg h "$H" --arg r "$out" --argjson n "$now" --argjson i "$i" '.[$i]|{kind:"mem_held",host:$h,reading:$r,ticket,lead,held_min:((($n-.since)/60)|floor)}' "$q")
        post "$ev" && jq --argjson i "$i" '.[$i].noted=true' "$q" > "$q.tmp" && mv "$q.tmp" "$q"
      done
    fi
    if [ $((now-start)) -gt 86400 ]; then post "$(jq -c --arg h "$H" '{kind:"mem_wait_timeout",host:$h,held:[.[]|{ticket,lead,since}]}' "$q")"; rm -f "$q"; log "timeout"; exit 0; fi
    sleep "$iv"
  done
}
case "${1:-}" in
  add) H="$2"; q="$D/$H.queue.json"; [ -s "$q" ] || echo '[]' > "$q"
       jq --arg t "$3" --arg l "$4" --argjson s "$(date +%s)" 'if any(.[];.ticket==$t) then . else .+[{ticket:$t,lead:$l,since:$s}] end' "$q" > "$q.tmp" && mv "$q.tmp" "$q"
       log "queued $3"; nohup "$0" _loop "$H" >/dev/null 2>&1 < /dev/null & echo "queued $3 on $H; waiter running";;
  _loop) H="$2"; loop;;
  resume) for f in "$D"/*.queue.json; do [ -s "$f" ] || continue; h=$(basename "$f" .queue.json); nohup "$0" _loop "$h" >/dev/null 2>&1 < /dev/null & done;;
  status) H=-; for f in "$D"/*.queue.json; do [ -e "$f" ] && { echo "$(basename "$f" .queue.json): $(jq -c '[.[]|.ticket]' "$f")"; }; done; tail -n 5 "$D/log" 2>/dev/null;;
  *) echo "usage: memwait.sh add <MAC|REMOTE> <ticket> <lead_id> | status"; exit 1;;
esac

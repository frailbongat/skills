#!/usr/bin/env bash
# Mergify drop watcher for igris's litflows auto-requeue. Plain bash + jq + gh + curl, no model calls.
# Read-only gh only; never comments on or changes a PR. Never logs the webhook URL or key.
#
# How Mergify shows queue state on Project-Lit/litflows (checked 2026-10-28 on real PRs):
#  - Check run "Mergify Merge Queue" on the PR head: IN_PROGRESS/QUEUED while queued;
#    COMPLETED+SUCCESS when merged (e.g. #921); COMPLETED+NEUTRAL when dropped (e.g. #970).
#  - mergify[bot] keeps one edited "Mergify Payload" comment with JSON in an HTML comment:
#    {"state":"merged"|"dequeued"|..., "left_at":..., "dequeue_reason":{"code","label","message"}}
#    #970: state dequeued, code CONFLICT_WITH_BASE_BRANCH ("The pull request conflicts with main").
#    #1085: dequeued PR_DEQUEUED (then requeued and merged). CI failures show other codes
#    (e.g. CHECKS_FAILED); any "dequeued" counts as a drop.
#  - Human text: "### 🚫 Left the queue"; PR mergeStateStatus goes DIRTY on a conflict.
#
# Per tick (rev 2026-10-29, catches self-queued PRs like #994/#1064): 1x `gh pr list` of ALL open
# litflows PRs. Any open PR whose queue check is queued/checking (QUEUED/IN_PROGRESS/PENDING/WAITING):
# its gates.json row (any state but queued) is flipped to "queued" (queued_from=old state, queued_by
# mergify-watch); a PR with no row is remembered in seen.json and watched too. Watched = gates rows
# "queued" + seen.json. Watched PR not open -> nothing (merge listener handles it). Queue check
# COMPLETED+SUCCESS -> nothing. Check COMPLETED non-SUCCESS or missing -> 1x read of the PR's comments
# for the Mergify payload; POST mergify_drop when payload state is "dequeued". Dedup per (pr, head_sha, reason) in state.json; saved only after a 2xx POST (or dry-run),
# so a failed POST retries next tick. gh errors: logged, retried next tick, never POST.
#
# Env: MW_INTERVAL (300) MW_GATES (/workspace/igris/gates.json) MW_STATE MW_LOG MW_HB
#      MW_SEEN  MW_FIXTURES=dir (test: list.json = gh pr list output, comments_<n>.json = comments array;
#      gh calls counted in $MW_FIXTURES/calls). Flag --once = one tick then exit.
# Live if PASEO_EVENT_WEBHOOK_URL and _KEY are set (same env as the stop poller), else dry-run.
set -u
DIR=/workspace/igris/mergify-watch
REPO=Project-Lit/litflows
INT="${MW_INTERVAL:-300}"; GATES="${MW_GATES:-/workspace/igris/gates.json}"
STATE="${MW_STATE:-$DIR/state.json}"; LOG="${MW_LOG:-$DIR/watch.log}"; HB="${MW_HB:-$DIR/heartbeat}"
SEEN="${MW_SEEN:-$DIR/seen.json}"; FIX="${MW_FIXTURES:-}"; ONCE=0; [ "${1:-}" = --once ] && ONCE=1
log() {
  local sz; sz=$(stat -c %s "$LOG" 2>/dev/null || echo 0); [ "$sz" -gt 262144 ] && mv -f "$LOG" "$LOG.1"
  printf '%(%Y-%m-%dT%H:%M:%S%z)T %s\n' -1 "$*" >> "$LOG"
}
beat() { printf '%(%s)T\n' -1 > "$HB.tmp.$$" && mv -f "$HB.tmp.$$" "$HB"; }
if [ $ONCE = 0 ]; then
  exec 9>"$DIR/watch.lock"; flock -n 9 || exit 0
  echo $$ > "$DIR/watch.pid"
fi
if [ -n "${PASEO_EVENT_WEBHOOK_URL:-}" ] && [ -n "${PASEO_EVENT_WEBHOOK_KEY:-}" ]; then MODE=live; else MODE=dry-run; fi
[ -s "$STATE" ] && jq -e 'type=="object"' "$STATE" >/dev/null 2>&1 || echo '{}' > "$STATE"
[ -s "$SEEN" ] && jq -e 'type=="object"' "$SEEN" >/dev/null 2>&1 || echo '{}' > "$SEEN"

ghlist() { # all open PRs, one call
  if [ -n "$FIX" ]; then echo x >> "$FIX/calls"; cat "$FIX/list.json" 2>/dev/null; return; fi
  timeout -k 5 90 gh pr list --repo "$REPO" --state open --limit 200 --json number,headRefOid,statusCheckRollup < /dev/null 2>/dev/null
}
ghpayload() { # $1 pr -> newest Mergify payload JSON
  local c
  if [ -n "$FIX" ]; then echo x >> "$FIX/calls"; c=$(cat "$FIX/comments_$1.json" 2>/dev/null) || return 1
  else c=$(timeout -k 5 60 gh api "repos/$REPO/issues/$1/comments?per_page=100" < /dev/null 2>/dev/null) || return 1; fi
  jq -ce '[.[]|select(.user.login=="mergify[bot]" and (.body|test("Mergify Payload")))]|sort_by(.updated_at)|last
    |.body|capture("Payload -\\*-\\s*(?<j>\\{.*\\})")|.j|fromjson' <<<"$c" 2>/dev/null
}
post() { # $1 payload json
  [ $MODE = live ] || { log "DRY-RUN event payload: $1"; return 0; }
  local code; code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 \
    -X POST -H 'Content-Type: application/json' \
    -H @<(printf 'Authorization: Bearer %s\nX-Webhook-Key: %s\n' "$PASEO_EVENT_WEBHOOK_KEY" "$PASEO_EVENT_WEBHOOK_KEY") \
    --data-binary "$1" "$PASEO_EVENT_WEBHOOK_URL" 2>/dev/null)
  log "POST http=$code kind=mergify_drop pr=$(jq -r .pr <<<"$1")"
  [[ "$code" == 2?? ]]
}
QQ='[.statusCheckRollup[]?|select(.name=="Mergify Merge Queue")]|sort_by(.startedAt)|last'
tick() {
  local list inq flips n v head qs qc p reason key ev watched
  list=$(ghlist) && jq -e 'type=="array"' >/dev/null 2>&1 <<<"$list" || { log "gh pr list failed; retry next tick"; return; }
  # 1) open PRs Mergify shows queued/checking
  inq=$(jq -r "[.[]|select(($QQ|.status//\"\")|test(\"^(QUEUED|IN_PROGRESS|PENDING|WAITING|REQUESTED)\$\"))|.number]|.[]" <<<"$list")
  if [ -n "$inq" ]; then
    local arr; arr=$(jq -cn '[$ARGS.positional[]|tonumber]' --args $inq)
    flips=$(jq -r --arg r "$REPO" --argjson a "$arr" '[.gates[]?|select(.repo==$r and (.number|IN($a[])) and .state!="queued")|"\(.number):\(.state)"]|join(" ")' "$GATES" 2>/dev/null) \
      || { log "gates.json unreadable; skip"; return; }
    if [ -n "$flips" ]; then
      # re-read right before writing, atomic replace, flip only rows still not queued
      jq --arg r "$REPO" --argjson a "$arr" --arg t "$(date -Iseconds)" \
        '.gates|=map(if .repo==$r and (.number|IN($a[])) and .state!="queued" then .queued_from=.state|.state="queued"|.queued_by="mergify-watch"|.updated=$t else . end)' \
        "$GATES" > "$GATES.mw.tmp" && jq -e '.gates|type=="array"' "$GATES.mw.tmp" >/dev/null && mv -f "$GATES.mw.tmp" "$GATES" \
        && log "gates.json flipped to queued: $flips" || { rm -f "$GATES.mw.tmp"; log "gates.json flip failed: $flips"; }
    fi
    for n in $inq; do
      jq -e --arg r "$REPO" --argjson n "$n" 'any(.gates[]?; .repo==$r and .number==$n)' "$GATES" >/dev/null 2>&1 && continue
      jq -e --arg n "$n" 'has($n)' "$SEEN" >/dev/null && continue
      jq --arg n "$n" --arg t "$(date -Iseconds)" '.[$n]=$t' "$SEEN" > "$SEEN.tmp" && mv -f "$SEEN.tmp" "$SEEN"
      log "pr=$n queued with no gates row; watching via seen.json"
    done
  fi
  # 2) drop check on watched PRs
  watched=$( { jq -r --arg r "$REPO" '.gates[]?|select(.state=="queued" and .repo==$r)|.number' "$GATES" 2>/dev/null; jq -r 'keys[]' "$SEEN"; } | sort -un)
  for n in $watched; do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    v=$(jq -c --argjson n "$n" '.[]|select(.number==$n)' <<<"$list")
    if [ -z "$v" ]; then
      log "pr=$n not open; skip"
      jq -e --arg n "$n" 'has($n)' "$SEEN" >/dev/null && { jq --arg n "$n" 'del(.[$n])' "$SEEN" > "$SEEN.tmp" && mv -f "$SEEN.tmp" "$SEEN"; }
      continue
    fi
    head=$(jq -r .headRefOid <<<"$v")
    read -r qs qc < <(jq -r "$QQ"'|"\(.status//"none") \(.conclusion//"none")"' <<<"$v")
    if [ "$qs" = COMPLETED ] && [ "$qc" = SUCCESS ]; then log "pr=$n queue check SUCCESS; merge listener handles it"; continue; fi
    if [ "$qs" != COMPLETED ] && [ "$qs" != none ]; then log "pr=$n queue check $qs; waiting"; continue; fi
    p=$(ghpayload "$n") || { log "pr=$n queue check $qs/$qc, payload read failed/unclear; retry next tick"; continue; }
    [ "$(jq -r .state <<<"$p")" = dequeued ] || { log "pr=$n payload state $(jq -r .state <<<"$p"); no drop"; continue; }
    reason=$(jq -r '[.dequeue_reason.code, .dequeue_reason.message]|map(select(.!=null))|join(": ")|.[0:200]' <<<"$p")
    [ -n "$reason" ] || reason="dequeued"
    key="$n|$head|$reason"
    jq -e --arg k "$key" 'has($k)' "$STATE" >/dev/null && { log "pr=$n drop already posted"; continue; }
    ev=$(jq -cn --arg r "$REPO" --argjson n "$n" --arg h "$head" --arg why "$reason" \
      '{kind:"mergify_drop",repo:$r,pr:$n,pr_url:"https://github.com/\($r)/pull/\($n)",head_sha:$h,reason:$why}')
    if post "$ev"; then
      jq --arg k "$key" --arg t "$(date -Is)" '.[$k]=$t' "$STATE" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
      jq --arg n "$n" 'del(.[$n])' "$SEEN" > "$SEEN.tmp" && mv -f "$SEEN.tmp" "$SEEN"
      log "pr=$n drop posted ($MODE): $reason"
    else log "pr=$n POST failed; retry next tick"; fi
  done
}
log "start pid=$$ mode=$MODE once=$ONCE interval=${INT}s"
while :; do
  beat; tick; beat
  [ $ONCE = 1 ] && exit 0
  sleep "$INT" 9>&- & wait $!
done

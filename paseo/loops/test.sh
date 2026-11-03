#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -d /Volumes/Dock ]; then T=/Volumes/Dock/tmp/relay-loops-test; else T="$HOME/tmp/relay-loops-test"; fi
rm -rf "$T/run"
mkdir -p "$T/run"
R="$T/run"
FAILS=0 PASSES=0

ok() { PASSES=$((PASSES + 1)); echo "ok   $1"; return 0; }
bad() {
  FAILS=$((FAILS + 1))
  echo "FAIL $1"
  if [ $# -gt 1 ]; then printf '%s\n' "$2" | sed 's/^/     /'; fi
  return 0
}
eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$(printf 'expected:\n%s\nactual:\n%s' "$2" "$3")"; fi
}
check() {
  local name=$1 out
  shift
  if out=$("$@" 2>&1); then ok "$name"; else bad "$name" "$out"; fi
}
check_fails() {
  local name=$1 out
  shift
  if out=$("$@" 2>&1); then bad "$name" "$out"; else ok "$name"; fi
}

TEST_PATH=/hook/test-url-token-7f3a
TEST_HEADER_NAME=X-Relay-Key
TEST_HEADER_VALUE=test-header-value-91c2
cat > "$R/fake_relay.py" <<'PY'
import http.server, os, sys
d = sys.argv[1]
want_path, want_name, want_value = sys.argv[2], sys.argv[3], sys.argv[4]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        good = (self.path == want_path and self.headers.get(want_name) == want_value
                and self.headers.get("Content-Type") == "text/plain")
        with open(os.path.join(d, "requests"), "a") as f:
            f.write("auth_ok\n" if good else "auth_bad\n")
        fail = os.path.join(d, "fail_next")
        if os.path.exists(fail):
            os.remove(fail)
            self.send_response(500); self.end_headers(); return
        if not good:
            self.send_response(403); self.end_headers(); return
        n = len([x for x in os.listdir(d) if x.startswith("body_")])
        with open(os.path.join(d, "body_%03d" % n), "wb") as f:
            f.write(body)
        self.send_response(200); self.end_headers()
    def log_message(self, *a):
        pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(os.path.join(d, "port.tmp"), "w") as f:
    f.write(str(s.server_address[1]))
os.rename(os.path.join(d, "port.tmp"), os.path.join(d, "port"))
s.serve_forever()
PY
mkdir -p "$R/relay"
python3 -I "$R/fake_relay.py" "$R/relay" "$TEST_PATH" "$TEST_HEADER_NAME" "$TEST_HEADER_VALUE" &
RELAY_PID=$!
trap 'kill "$RELAY_PID" 2>/dev/null' EXIT
for _ in $(seq 1 50); do [ -s "$R/relay/port" ] && break; sleep 0.1; done
[ -s "$R/relay/port" ] || { echo "FAIL fake relay did not start"; exit 1; }
PASEO_RELAY_URL="http://127.0.0.1:$(cat "$R/relay/port")$TEST_PATH"
export PASEO_RELAY_URL
export PASEO_RELAY_AUTH="$TEST_HEADER_NAME: $TEST_HEADER_VALUE"
export PASEO_LOOPS_HOME="$R/loops"
unset RELAY_DRY MW_CHECK MW_TICKS MW_FIXTURES

nbodies() { find "$R/relay" -name 'body_*' | wc -l | tr -d ' '; }
lastbody() { cat "$(find "$R/relay" -name 'body_*' | sort | tail -n 1)"; }

mkdir -p "$R/stub"
cat > "$R/stub/launchctl" <<'SH'
#!/usr/bin/env bash
d=$(dirname "$0")
echo "$*" >> "$d/calls"
# With $d/headless, there is no gui/<uid> domain, as on a Mac with no desktop login.
case "$1" in
  print)
    case "$2" in
      */*/*) [ -e "$d/loaded_${2%%/*}_${2##*/}" ] ;;
      gui/*) [ ! -e "$d/headless" ] ;;
      user/*) exit 0 ;;
      *) exit 1 ;;
    esac ;;
  bootstrap)
    if [ -e "$d/headless" ] && [ "${2%%/*}" = gui ]; then
      echo "Bootstrap failed: 125: Domain does not support specified action" >&2
      exit 125
    fi
    touch "$d/loaded_${2%%/*}_$(basename "$3" .plist)" ;;
  bootout) rm -f "$d/loaded_${2%%/*}_${2##*/}" ;;
  kickstart) [ -e "$d/loaded_${2%%/*}_${2##*/}" ] ;;
  *) exit 1 ;;
esac
SH
chmod +x "$R/stub/launchctl"
export LAUNCHCTL="$R/stub/launchctl"

log() { echo "$*"; }
# shellcheck source=paseo/loops/relay.sh
. "$HERE/relay.sh"
out=$(relay_body mergify_drop o/r 7 abc "$(printf 'line one\nline two')")
eq "relay_body mergify_drop flattens a multi-line reason" "status: failed
ticket: https://github.com/o/r/pull/7 lead: none
pr: https://github.com/o/r/pull/7 head: abc
verdict: mergify-watch: o/r#7 left the merge queue
ask: line one line two" "$out"
out=$(RELAY_DRY=1 relay_post "$(printf 'a\nb')")
eq "relay_post RELAY_DRY=1 logs DRY-RUN and posts nothing" "DRY-RUN a | b" "$out"
out=$(PASEO_RELAY_AUTH='' relay_post x)
eq "relay_post with empty auth is a dry-run" "DRY-RUN x" "$out"
check_fails "relay_body rejects an unknown kind" relay_body nope
eq "dry-runs reached no relay" 0 "$(nbodies)"

LK="$R/lock"
mkdir -p "$LK"
taker() { exec bash -c '. "$1"; take_lock "$2" || exit 1; echo $$ >> "$3"; exec sleep "$4"' taker "$HERE/relay.sh" "$@"; }
taker "$LK/a.lock" "$LK/a.won" 30 & holder=$!
for _ in $(seq 1 50); do [ -s "$LK/a.won" ] && break; sleep 0.1; done
check "take_lock takes a free lock" test -s "$LK/a.won"
check_fails "take_lock refuses a lock held by a live pid" taker "$LK/a.lock" "$LK/a.won" 0
kill "$holder"; wait "$holder" 2>/dev/null
eq "the lock file still names the dead holder" "$(cat "$LK/a.won")" "$(cat "$LK/a.lock")"
dead=$(cat "$LK/a.won")
wins=""
for _ in $(seq 1 5); do
  echo "$dead" > "$LK/a.lock"
  rm -f "$LK/go" "$LK/b.won"
  pids=""
  for _ in $(seq 1 16); do
    bash -c 'while [ ! -e "$1" ]; do :; done; . "$2"; take_lock "$3" && { echo $$ >> "$4"; sleep 1; }' \
      taker "$LK/go" "$HERE/relay.sh" "$LK/a.lock" "$LK/b.won" & pids="$pids $!"
  done
  sleep 0.3
  touch "$LK/go"
  for p in $pids; do wait "$p"; done
  wins="$wins $(wc -l < "$LK/b.won" | tr -d ' ')"
  [ "$(cat "$LK/b.won")" = "$(cat "$LK/a.lock")" ] || wins="$wins wrong-pid"
done
eq "16 racing takers, 5 rounds: exactly one recovers the stale lock each round" " 1 1 1 1 1" "$wins"
bash -c '. "$1"; echo 1 > "$2"; release_lock "$2"' rel "$HERE/relay.sh" "$LK/c.lock"
check "release_lock keeps a lock this shell does not hold" test -e "$LK/c.lock"
bash -c '. "$1"; take_lock "$2" && release_lock "$2"' rel "$HERE/relay.sh" "$LK/c.lock"
check "release_lock drops a lock this shell holds" test ! -e "$LK/c.lock"

MW="$HERE/memwait.sh"
MWD="$R/loops/memwait"
export MW_HOST=testhost MW_INTERVAL=0
touch "$R/stub/loaded_gui_sh.frail.paseo-memwait"
OKCHK='echo verdict=ok free=50% min=25%'
HELDCHK='echo verdict=held free=10% min=25%'

"$MW" add https://t/A lead-a >/dev/null
"$MW" add https://t/A lead-a >/dev/null
"$MW" add https://t/B lead-b >/dev/null
eq "memwait add keeps one queue entry per ticket" 2 "$(jq length "$MWD/queue.json")"
eq "memwait add kicks the LaunchAgent" 3 "$(grep -c "^kickstart gui/$(id -u)/sh.frail.paseo-memwait$" "$R/stub/calls")"

MW_CHECK=$OKCHK "$MW" resume
eq "memwait sends one ready per held ticket" 2 "$(nbodies)"
eq "memwait ready body for A" "status: ready
ticket: https://t/A lead: lead-a
pr: none head: none
verdict: memwait: testhost memory free (free=50% min=25%), held start can go
ask: none" "$(cat "$R/relay/body_000")"
eq "memwait ready body for B" "status: ready
ticket: https://t/B lead: lead-b
pr: none head: none
verdict: memwait: testhost memory free (free=50% min=25%), held start can go
ask: none" "$(cat "$R/relay/body_001")"
eq "memwait empties the queue after the POSTs" 0 "$(jq length "$MWD/queue.json")"
MW_CHECK=$OKCHK "$MW" resume
eq "memwait restart with an empty queue sends nothing" 2 "$(nbodies)"

"$MW" add https://t/C lead-c >/dev/null
now=$(date +%s)
jq --argjson s $((now - 1900)) 'map(.since=$s)' "$MWD/queue.json" > "$R/q" && mv "$R/q" "$MWD/queue.json"
MW_CHECK=$HELDCHK MW_TICKS=3 "$MW" resume
eq "memwait sends one question after MW_HOLD_NOTE over 3 ticks" 3 "$(nbodies)"
eq "memwait question body" "status: question
ticket: https://t/C lead: lead-c
pr: none head: none
verdict: memwait: testhost start held 31 min (free=10% min=25%)
ask: keep waiting or start https://t/C anyway?" "$(lastbody)"
MW_CHECK=$HELDCHK MW_TICKS=2 "$MW" resume
eq "memwait restart sends no second question" 3 "$(nbodies)"
eq "memwait keeps the held ticket queued" 1 "$(jq length "$MWD/queue.json")"

jq --argjson s $((now - 90000)) 'map(.since=$s)' "$MWD/queue.json" > "$R/q" && mv "$R/q" "$MWD/queue.json"
MW_CHECK=$HELDCHK MW_TICKS=2 "$MW" resume
eq "memwait sends one failed on MW_TIMEOUT" 4 "$(nbodies)"
eq "memwait failed body" "status: failed
ticket: https://t/C lead: lead-c
pr: none head: none
verdict: memwait: testhost gave up after 25 h held
ask: start https://t/C by hand or drop it?" "$(lastbody)"
eq "memwait drops the ticket after the failed POST" 0 "$(jq length "$MWD/queue.json")"

"$MW" add https://t/D lead-d >/dev/null
touch "$R/relay/fail_next"
MW_CHECK=$OKCHK MW_TICKS=1 "$MW" resume
eq "memwait sends nothing new when the relay answers 500" 4 "$(nbodies)"
eq "memwait keeps the ticket after a failed POST" 1 "$(jq length "$MWD/queue.json")"
check "memwait logs http=500" grep -q 'relay http=500' "$MWD/log"
MW_CHECK=$OKCHK MW_TICKS=1 "$MW" resume
eq "memwait retries after the 500" 5 "$(nbodies)"
eq "memwait retry body" "https://t/D" "$(lastbody | sed -n 's/^ticket: \(.*\) lead:.*/\1/p')"

"$MW" add https://t/E lead-e >/dev/null
sleep 30 & live=$!
echo "$live" > "$MWD/loop.lock"
MW_CHECK=$OKCHK MW_TICKS=1 "$MW" resume
eq "memwait exits when a live waiter holds the lock" 5 "$(nbodies)"
kill "$live"; wait "$live" 2>/dev/null
MW_CHECK=$OKCHK MW_TICKS=1 "$MW" resume
eq "memwait takes over a lock left by a dead pid" 6 "$(nbodies)"

rm -f "$R/stub/loaded_gui_sh.frail.paseo-memwait"
q0=$(cat "$MWD/queue.json")
check_fails "memwait add refuses with no LaunchAgent and no relay env" \
  env PASEO_RELAY_URL= PASEO_RELAY_AUTH= "$MW" add https://t/G lead-g
out=$(PASEO_RELAY_URL='' PASEO_RELAY_AUTH='' "$MW" add https://t/G lead-g 2>&1 >/dev/null)
case "$out" in *"error: no LaunchAgent and no relay env"*) ok "memwait add says why on stderr" ;;
  *) bad "memwait add says why on stderr" "$out" ;; esac
eq "memwait add refusal leaves the queue alone" "$q0" "$(cat "$MWD/queue.json")"
out=$(RELAY_DRY=1 MW_CHECK=$OKCHK "$MW" add https://t/F lead-f 2>&1)
case "$out" in *"waiter started in the background, mode=dry-run"*) ok "memwait add starts a waiter when no LaunchAgent is loaded" ;;
  *) bad "memwait add starts a waiter when no LaunchAgent is loaded" "$out" ;; esac
for _ in $(seq 1 50); do grep -q 'freed https://t/F' "$MWD/log" && break; sleep 0.1; done
check "memwait background waiter dry-runs" grep -q 'DRY-RUN status: ready | ticket: https://t/F' "$MWD/log"
eq "memwait background dry-run reached no relay" 6 "$(nbodies)"

for v in 101 0 abc -5; do
  check_fails "memwait refuses MW_FREE_MIN='$v'" env MW_FREE_MIN="$v" "$MW" status
done
check "memwait accepts MW_FREE_MIN=100" env MW_FREE_MIN=100 "$MW" status
eq "memwait bad MW_FREE_MIN sent nothing" 6 "$(nbodies)"

MG="$HERE/mergify-watch.sh"
MGD="$R/loops/mergify-watch"
F="$R/fixtures"
mkdir -p "$F"
export MW_FIXTURES=$F MW_REPO=o/r
pr() {
  jq -cn --argjson n "$1" --arg h "$2" --arg s "$3" --arg c "$4" \
    '{number:$n, headRefOid:$h, statusCheckRollup:[{name:"Mergify Merge Queue", status:$s, conclusion:(if $c=="" then null else $c end), startedAt:"2026-11-01T00:00:00Z"}]}'
}
list() { printf '%s\n' "$@" | jq -s . > "$F/list.json"; }
payload() {
  jq -n --arg st "$2" --arg c "$3" --arg m "$4" --arg l "${5:-2026-11-01T01:00:00Z}" \
    '[{user:{login:"someone"}, body:"hi", updated_at:"2026-11-01T00:00:00Z"},
      {user:{login:"mergify[bot]"}, updated_at:"2026-11-01T01:00:00Z",
       body:("<!-- Mergify Payload -*- " + ({state:$st, left_at:$l, dequeue_reason:{code:$c, message:$m}}|tojson) + " -->")}]' > "$F/comments_$1.json"
}
calls() { wc -l < "$F/calls" | tr -d ' '; }
: > "$F/calls"
base=$(nbodies)

list "$(pr 101 aaa IN_PROGRESS '')" "$(pr 102 bbb QUEUED '')" "$(pr 103 ccc IN_PROGRESS '')" "$(pr 104 ddd COMPLETED SUCCESS)"
"$MG" --once
eq "mergify tick 1: one gh call" 1 "$(calls)"
eq "mergify tick 1: watches the three queued PRs" '["101","102","103"]' "$(jq -c 'keys' "$MGD/seen.json")"
eq "mergify tick 1: sends nothing" "$base" "$(nbodies)"

list "$(pr 101 aaa COMPLETED NEUTRAL)" "$(pr 102 bbb COMPLETED SUCCESS)" "$(pr 103 ccc COMPLETED NEUTRAL)"
payload 101 dequeued CONFLICT_WITH_BASE_BRANCH "The pull request conflicts with main"
payload 103 dequeued CHECKS_FAILED "ci failed"
touch "$R/relay/fail_next"
"$MG" --once
eq "mergify tick 2: list plus two comment reads" 4 "$(calls)"
eq "mergify tick 2: 101 got the 500, 103 sent" $((base + 1)) "$(nbodies)"
eq "mergify drop body for 103" "status: failed
ticket: https://github.com/o/r/pull/103 lead: none
pr: https://github.com/o/r/pull/103 head: ccc
verdict: mergify-watch: o/r#103 left the merge queue
ask: CHECKS_FAILED: ci failed" "$(lastbody)"
eq "mergify tick 2: 101 stays watched for retry" '["101","102"]' "$(jq -c 'keys' "$MGD/seen.json")"

"$MG" --once
eq "mergify tick 3: list plus one comment read" 6 "$(calls)"
eq "mergify tick 3: retry sends 101" $((base + 2)) "$(nbodies)"
eq "mergify drop body for 101" "status: failed
ticket: https://github.com/o/r/pull/101 lead: none
pr: https://github.com/o/r/pull/101 head: aaa
verdict: mergify-watch: o/r#101 left the merge queue
ask: CONFLICT_WITH_BASE_BRANCH: The pull request conflicts with main" "$(lastbody)"

"$MG" --once
"$MG" --once
eq "mergify ticks 4-5: one gh call each" 8 "$(calls)"
eq "mergify ticks 4-5: repeats send nothing" $((base + 2)) "$(nbodies)"

jq '. + {"101":"x"}' "$MGD/seen.json" > "$R/s" && mv "$R/s" "$MGD/seen.json"
"$MG" --once
eq "mergify: a re-watched PR with a sent key sends nothing" $((base + 2)) "$(nbodies)"
check "mergify logs the dedup hit" grep -q 'already sent: mergify_drop|https://github.com/o/r/pull/101|aaa|' "$MGD/log"

list "$(pr 101 eee IN_PROGRESS '')" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
list "$(pr 101 eee COMPLETED NEUTRAL)" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
eq "mergify: a new head on the same PR sends again" $((base + 3)) "$(nbodies)"

payload 101 dequeued CHECKS_FAILED "ci failed" 2026-11-02T01:00:00Z
list "$(pr 101 eee IN_PROGRESS '')" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
list "$(pr 101 eee COMPLETED NEUTRAL)" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
payload 101 dequeued CHECKS_FAILED "ci failed" 2026-11-02T02:00:00Z
list "$(pr 101 eee IN_PROGRESS '')" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
list "$(pr 101 eee COMPLETED NEUTRAL)" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
eq "mergify: two drops at one head and reason, new left_at, send twice" $((base + 5)) "$(nbodies)"
list "$(pr 101 eee IN_PROGRESS '')" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
list "$(pr 101 eee COMPLETED NEUTRAL)" "$(pr 102 bbb COMPLETED SUCCESS)"
"$MG" --once
eq "mergify: an exact repeat drop sends nothing" $((base + 5)) "$(nbodies)"

list "$(pr 103 ccc COMPLETED NEUTRAL)"
"$MG" --once
eq "mergify: closed PRs leave seen.json" '{}' "$(jq -c . "$MGD/seen.json")"

echo broken > "$F/list.json"
c0=$(nbodies)
"$MG" --once
check "mergify logs a gh failure" grep -q 'gh pr list failed; retry next tick' "$MGD/log"
eq "mergify: a gh failure sends nothing" "$c0" "$(nbodies)"
check "mergify writes a heartbeat" test -s "$MGD/heartbeat"
NOGH="$R/nogh"
mkdir -p "$NOGH"
ln -sf "$(command -v jq)" "$NOGH/jq"
env -u MW_FIXTURES PATH="$NOGH:/usr/bin:/bin:/usr/sbin:/sbin" "$MG" --once
check "mergify logs that gh is missing and the PATH it searched" grep -q "gh not found on PATH=$NOGH:/usr/bin:" "$MGD/log"
unset MW_FIXTURES MW_REPO

IH="$T/home"
rm -rf "$IH"
mkdir -p "$IH/.paseo-relay"
printf '%s' "$PASEO_RELAY_URL" > "$IH/.paseo-relay/url"
printf '%s' "$PASEO_RELAY_AUTH" > "$IH/.paseo-relay/auth"
: > "$R/stub/calls"
rm -f "$R/stub"/loaded_*
inst() { HOME="$IH" PASEO_LOOPS_HOME="$IH/.paseo/loops" "$HERE/install.sh" "$@"; }
check "install memwait" inst install memwait
check "install mergify-watch" inst install mergify-watch
MP="$IH/Library/LaunchAgents/sh.frail.paseo-memwait.plist"
GP="$IH/Library/LaunchAgents/sh.frail.paseo-mergify-watch.plist"
check "plists pass plutil -lint" plutil -lint -s "$MP" "$GP"
# Older macOS plutil has no "raw" format for -extract, so go through JSON.
pget() { plutil -convert json -o - "$1" | jq -r "$2"; }
eq "memwait plist runs resume with no KeepAlive" "false" "$(pget "$MP" '.KeepAlive // false')"
eq "mergify-watch plist has KeepAlive" "true" "$(pget "$GP" .KeepAlive)"
case "$(pget "$MP" '.ProgramArguments[2]')" in
  *'PASEO_RELAY_URL="$(cat "$HOME/.paseo-relay/url")"'*"exec '$HERE/memwait.sh' resume") ok "memwait plist reads the relay files at start" ;;
  *) bad "memwait plist reads the relay files at start" "$(pget "$MP" '.ProgramArguments[2]')" ;;
esac
eq "launchctl got two bootstraps" 2 "$(grep -c "^bootstrap gui/$(id -u) $IH/Library/LaunchAgents/sh.frail.paseo-" "$R/stub/calls")"
inst install mergify-watch >/dev/null
eq "reinstall boots out first" 1 "$(grep -c "^bootout gui/$(id -u)/sh.frail.paseo-mergify-watch$" "$R/stub/calls")"
out=$(inst status)
case "$out" in *"memwait: plist present, loaded"*"mergify-watch: plist present, loaded"*) ok "status shows both loaded" ;; *) bad "status shows both loaded" "$out" ;; esac
inst uninstall memwait >/dev/null
check "uninstall removes the plist" test ! -e "$MP"
mkdir -p "$R/tools"
printf '#!/bin/sh\nexit 1\n' > "$R/tools/gh"
chmod +x "$R/tools/gh"
PATH="$R/tools:$PATH" inst install mergify-watch >/dev/null
eq "the plist PATH starts with the dir of the gh install found" "$R/tools" "$(pget "$GP" .EnvironmentVariables.PATH | cut -d: -f1)"
eq "the plist PATH lists each dir once" "" "$(pget "$GP" .EnvironmentVariables.PATH | tr : '\n' | sort | uniq -d)"
out=$(PATH="$NOGH:/usr/bin:/bin:/usr/sbin:/sbin" inst install mergify-watch 2>&1)
eq "install refuses when gh is missing" "error: mergify-watch needs gh, and it is not on PATH=$NOGH:/usr/bin:/bin:/usr/sbin:/sbin" "$out"
rm "$IH/.paseo-relay/auth"
check_fails "install refuses without ~/.paseo-relay/auth" inst install memwait
check_fails "no --force passed to launchctl" grep -q -- '--force' "$R/stub/calls"

U=$(id -u)
printf '%s' "$PASEO_RELAY_AUTH" > "$IH/.paseo-relay/auth"
rm -f "$R/stub"/loaded_*
touch "$R/stub/headless"
: > "$R/stub/calls"
check "headless install memwait" inst install memwait
eq "headless install bootstraps user/<uid>" 1 "$(grep -c "^bootstrap user/$U $MP$" "$R/stub/calls")"
inst install memwait >/dev/null
eq "headless reinstall boots out of user/<uid>" 1 "$(grep -c "^bootout user/$U/sh.frail.paseo-memwait$" "$R/stub/calls")"
case "$(inst status)" in *"memwait: plist present, loaded in user/$U"*) ok "status prints the user domain" ;;
  *) bad "status prints the user domain" "$(inst status)" ;; esac
"$MW" add https://t/H lead-h >/dev/null
eq "headless memwait add kickstarts user/<uid>" 1 "$(grep -c "^kickstart user/$U/sh.frail.paseo-memwait$" "$R/stub/calls")"
inst uninstall memwait >/dev/null
eq "headless uninstall boots out of user/<uid>" 2 "$(grep -c "^bootout user/$U/sh.frail.paseo-memwait$" "$R/stub/calls")"
rm -f "$R/stub/headless"

eq "every request carried the auth header, path, and text/plain" "" "$(grep -v '^auth_ok$' "$R/relay/requests")"
leaks=$(grep -rlE "test-url-token-7f3a|$TEST_HEADER_VALUE" "$R/loops" "$IH/Library" "$IH/.paseo" 2>/dev/null)
eq "no log, state, or plist holds the test URL or header value" "" "$leaks"

echo
echo "$PASSES passed, $FAILS failed"
[ "$FAILS" = 0 ]

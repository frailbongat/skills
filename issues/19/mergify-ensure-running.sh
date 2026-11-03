#!/usr/bin/env bash
# Ensure one mergify watcher runs (heartbeat < 2*interval+120s). Prints ok / started.
set -u
DIR=/workspace/igris/mergify-watch; cd "$DIR" || exit 1
pid=$(cat watch.pid 2>/dev/null); hb=$(cat heartbeat 2>/dev/null || echo 0); now=$(date +%s)
if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && [ $((now-hb)) -lt $(( ${MW_INTERVAL:-300}*2+120 )) ]; then echo ok; exit 0; fi
pkill -TERM -f "$DIR/[w]atch.sh" 2>/dev/null; sleep 1
setsid nohup bash -lc "exec $DIR/watch.sh" >> "$DIR/nohup.out" 2>&1 < /dev/null &
sleep 1; echo "started pid=$(cat watch.pid 2>/dev/null)"

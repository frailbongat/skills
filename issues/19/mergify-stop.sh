#!/usr/bin/env bash
DIR=/workspace/igris/mergify-watch
pkill -TERM -f "$DIR/[w]atch.sh"; rm -f "$DIR/watch.pid"; echo stopped

#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
LOOPS_HOME="${PASEO_LOOPS_HOME:-$HOME/.paseo/loops}"
AGENTS="$HOME/Library/LaunchAgents"
U=$(id -u)
LOOPS="memwait mergify-watch"
BASE_PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") install <loop> | uninstall <loop> | status   (loop: memwait, mergify-watch)

  install <loop>     write ~/Library/LaunchAgents/sh.frail.paseo-<loop>.plist
                     and bootstrap it into gui/<uid>, or into user/<uid> when
                     gui/<uid> does not exist (a Mac with no desktop login).
                     A user/<uid> plist gets LimitLoadToSessionType Background,
                     because user/<uid> refuses a plist without it, and
                     gui/<uid> refuses a plist with it.
  uninstall <loop>   boot it out and delete the plist
  status             print each loop's plist, launchd domain, and last log lines

launchctl(1) says a user/<uid> domain "may exist independently of a logged-in
user", but it does not say that domain loads ~/Library/LaunchAgents at boot.
On a Mac with no desktop login, rerun install after a reboot.

memwait runs \`memwait.sh resume\` once at login, and \`memwait.sh add\` kicks it
again. mergify-watch runs at login, and launchd restarts it when it exits.

Run install mergify-watch on one host only. It writes the owner marker
$LOOPS_HOME/mergify-watch/owner, and a watcher with no marker sends nothing,
because each host keeps its own sent-drop state. To move off two watchers,
rerun install mergify-watch on the owner and run uninstall mergify-watch on
the other host.
install resolves each tool the loop calls (memwait: jq, curl; mergify-watch:
gh, jq, curl) on the current PATH and puts its dir at the front of the plist
PATH, so run install from a shell where those tools work. It refuses when one
is missing.

The plist command reads ~/.paseo-relay/url and ~/.paseo-relay/auth at start,
so the secrets stay out of the plist, this repo, and the loop's argv.

Env: PASEO_LOOPS_HOME (~/.paseo/loops) for state and logs. LAUNCHCTL=<cmd>
replaces launchctl in tests.
EOF
  exit "${1:-2}"
}

OWNER="$LOOPS_HOME/mergify-watch/owner"

label() { echo "sh.frail.paseo-$1"; }
plist() { echo "$AGENTS/$(label "$1").plist"; }
domain() { if "$LAUNCHCTL" print "gui/$U" >/dev/null 2>&1; then echo "gui/$U"; else echo "user/$U"; fi; }
# Prints each domain that holds the loop's agent.
loaded_in() {
  local d
  for d in "gui/$U" "user/$U"; do
    if "$LAUNCHCTL" print "$d/$(label "$1")" >/dev/null 2>&1; then echo "$d"; fi
  done
}
bootout_all() {
  local d
  for d in $(loaded_in "$1"); do "$LAUNCHCTL" bootout "$d/$(label "$1")"; done
}

check_loop() {
  case "${1:-}" in memwait|mergify-watch) ;; *) usage ;; esac
}

tools() { case $1 in memwait) echo "jq curl" ;; mergify-watch) echo "gh jq curl" ;; esac; }

plist_path() {
  local p=$BASE_PATH t bin dir
  for t in $(tools "$1"); do
    bin=$(command -v "$t") || { echo "error: $1 needs $t, and it is not on PATH=$PATH" >&2; return 1; }
    dir=$(dirname "$bin")
    case ":$p:" in *":$dir:"*) ;; *) p="$dir:$p" ;; esac
  done
  echo "$p"
}

xml_escape() {
  local s=${1//&/&amp;}
  s=${s//</&lt;}
  printf '%s' "${s//>/&gt;}"
}

write_plist() {
  local loop=$1 path=$2 domain=$3 script args keepalive session="" cmd
  script="$HERE/$loop.sh"
  case "$script$LOOPS_HOME" in *\'*) echo "error: a path holds a single quote: $script or $LOOPS_HOME" >&2; exit 1 ;; esac
  if [ "$loop" = memwait ]; then
    args=" resume"
    keepalive=""
  else
    args=""
    keepalive="
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>60</integer>"
  fi
  case "$domain" in user/*) session="
  <key>LimitLoadToSessionType</key>
  <string>Background</string>" ;; esac
  cmd="test -s \"\$HOME/.paseo-relay/url\" && test -s \"\$HOME/.paseo-relay/auth\" || { echo 'missing ~/.paseo-relay/url or auth' >&2; exit 78; }
export PASEO_RELAY_URL=\"\$(cat \"\$HOME/.paseo-relay/url\")\" PASEO_RELAY_AUTH=\"\$(cat \"\$HOME/.paseo-relay/auth\")\"
exec '$script'$args"
  mkdir -p "$AGENTS" "$LOOPS_HOME/$loop"
  cat > "$(plist "$loop")" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(label "$loop")</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-c</string>
    <string>$(xml_escape "$cmd")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(xml_escape "$path")</string>
    <key>PASEO_LOOPS_HOME</key>
    <string>$(xml_escape "$LOOPS_HOME")</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>$keepalive$session
  <key>StandardOutPath</key>
  <string>$(xml_escape "$LOOPS_HOME/$loop/launchd.log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$LOOPS_HOME/$loop/launchd.log")</string>
</dict>
</plist>
EOF
}

case "${1:-}" in
  install)
    check_loop "${2:-}"
    if ! { test -s "$HOME/.paseo-relay/url" && test -s "$HOME/.paseo-relay/auth"; }; then
      echo "error: ~/.paseo-relay/url and ~/.paseo-relay/auth must both exist and be non-empty" >&2
      exit 1
    fi
    path=$(plist_path "$2") || exit 1
    bootout_all "$2"
    d=$(domain)
    write_plist "$2" "$path" "$d"
    plutil -lint -s "$(plist "$2")"
    if [ "$2" = mergify-watch ]; then date '+%Y-%m-%dT%H:%M:%S%z' > "$OWNER"; fi
    "$LAUNCHCTL" bootstrap "$d" "$(plist "$2")"
    echo "installed $(label "$2") in $d, logs in $LOOPS_HOME/$2/" ;;
  uninstall)
    check_loop "${2:-}"
    bootout_all "$2"
    rm -f "$(plist "$2")"
    if [ "$2" = mergify-watch ]; then rm -f "$OWNER"; fi
    echo "uninstalled $(label "$2")" ;;
  status)
    for loop in $LOOPS; do
      if [ -f "$(plist "$loop")" ]; then p=present; else p=absent; fi
      l=$(loaded_in "$loop" | paste -sd ' ' -)
      if [ -n "$l" ]; then l="loaded in $l"; else l="not loaded"; fi
      o=""
      if [ "$loop" = mergify-watch ]; then
        if [ -e "$OWNER" ]; then o=", owner"; else o=", standby"; fi
      fi
      echo "$loop: plist $p, $l$o"
      tail -n 3 "$LOOPS_HOME/$loop/log" 2>/dev/null | sed 's/^/  /' || true
    done ;;
  -h|--help) usage 0 ;;
  *) usage ;;
esac

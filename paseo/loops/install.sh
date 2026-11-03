#!/usr/bin/env bash
# Run a loop as a LaunchAgent on this Mac.
#
#   install memwait|mergify-watch     write ~/Library/LaunchAgents/sh.frail.paseo-<loop>.plist
#                                     and bootstrap it into gui/<uid>
#   uninstall memwait|mergify-watch   boot it out and delete the plist
#   status                            print each loop's plist, launchd state, and last log lines
#
# memwait runs `memwait.sh resume` once at login, and `memwait.sh add` kicks it
# again. mergify-watch runs at login and launchd restarts it when it exits.
# The plist command reads ~/.paseo-relay/url and ~/.paseo-relay/auth at start,
# so the secrets stay out of the plist, this repo, and the loop's argv.
#
# Env: PASEO_LOOPS_HOME (~/.paseo/loops) for state and logs. LAUNCHCTL=<cmd>
# replaces launchctl in tests.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
LOOPS_HOME="${PASEO_LOOPS_HOME:-$HOME/.paseo/loops}"
AGENTS="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"
LOOPS="memwait mergify-watch"

usage() {
  echo "usage: $(basename "$0") install <loop> | uninstall <loop> | status   (loop: memwait, mergify-watch)" >&2
  exit 2
}

label() { echo "sh.frail.paseo-$1"; }
plist() { echo "$AGENTS/$(label "$1").plist"; }
loaded() { "$LAUNCHCTL" print "$DOMAIN/$(label "$1")" >/dev/null 2>&1; }

check_loop() {
  case "${1:-}" in memwait|mergify-watch) ;; *) usage ;; esac
}

xml_escape() {
  local s=${1//&/&amp;}
  s=${s//</&lt;}
  printf '%s' "${s//>/&gt;}"
}

write_plist() { # loop
  local loop=$1 script args keepalive cmd
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
  # zsh expands the $(cat ...) when launchd starts the job, so the plist holds
  # only the file paths.
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
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>PASEO_LOOPS_HOME</key>
    <string>$(xml_escape "$LOOPS_HOME")</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>$keepalive
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
    if loaded "$2"; then "$LAUNCHCTL" bootout "$DOMAIN/$(label "$2")"; fi
    write_plist "$2"
    plutil -lint -s "$(plist "$2")"
    "$LAUNCHCTL" bootstrap "$DOMAIN" "$(plist "$2")"
    echo "installed $(label "$2"), logs in $LOOPS_HOME/$2/" ;;
  uninstall)
    check_loop "${2:-}"
    if loaded "$2"; then "$LAUNCHCTL" bootout "$DOMAIN/$(label "$2")"; fi
    rm -f "$(plist "$2")"
    echo "uninstalled $(label "$2")" ;;
  status)
    for loop in $LOOPS; do
      if [ -f "$(plist "$loop")" ]; then p=present; else p=absent; fi
      if loaded "$loop"; then l=loaded; else l="not loaded"; fi
      echo "$loop: plist $p, $l"
      tail -n 3 "$LOOPS_HOME/$loop/log" 2>/dev/null | sed 's/^/  /' || true
    done ;;
  *) usage ;;
esac

#!/usr/bin/env bash
# Keep the portable part of the Paseo setup in this repo.
#
#   export          copy the agent and terminal profiles from the live
#                   config.json into profiles.json, with the home directory
#                   written as {{HOME}} so the file works for any username
#   check           diff profiles.json against the live config. Exits 0 when
#                   they match and 1 when they differ.
#   apply [--force] new machine: write profiles.json into config.json and
#                   symlink agent-roles/ into the Paseo home. It backs up
#                   config.json first and only replaces
#                   daemon.agentProfiles and daemon.terminalProfiles.
#                   --force moves a real agent-roles folder aside instead of
#                   skipping it.
#
# Set PASEO_HOME to point at another Paseo home. It defaults to ~/.paseo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES="$SCRIPT_DIR/profiles.json"
ROLES_SRC="$SCRIPT_DIR/agent-roles"

PASEO_HOME="${PASEO_HOME:-$HOME/.paseo}"
CONFIG="$PASEO_HOME/config.json"
ROLES_DEST="$PASEO_HOME/agent-roles"

usage() {
  echo "usage: $(basename "$0") export | check | apply [--force]" >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found. Install it with \`brew install jq\`." >&2
  exit 1
fi

if [[ -z "${HOME:-}" ]]; then
  echo "error: HOME is not set, so there is no path to swap for {{HOME}}." >&2
  exit 1
fi

require_config() {
  if [[ ! -f "$CONFIG" ]]; then
    echo "error: $CONFIG not found. Open Paseo once first, so it writes its config." >&2
    exit 1
  fi
}

# The two tracked keys from the live config, with $HOME written as {{HOME}}.
# -S sorts object keys, so the output does not change when the app reorders
# them. Array order, the order profiles show in the app, stays as it is.
live_profiles() {
  jq -S --arg home "$HOME" '
    {
      agentProfiles: (.daemon.agentProfiles // []),
      terminalProfiles: (.daemon.terminalProfiles // [])
    }
    | walk(if type == "string" then split($home) | join("{{HOME}}") else . end)
  ' "$CONFIG"
}

# profiles.json with {{HOME}} turned back into this machine's $HOME.
repo_profiles_for_this_home() {
  jq --arg home "$HOME" '
    walk(if type == "string" then split("{{HOME}}") | join($home) else . end)
  ' "$PROFILES"
}

cmd_export() {
  require_config
  local tmp
  tmp="$(mktemp "$PROFILES.tmp.XXXXXX")"
  # mktemp makes the file 0600. profiles.json holds no secrets, so give it
  # the same mode as the rest of the repo.
  chmod 644 "$tmp"
  live_profiles > "$tmp"
  mv "$tmp" "$PROFILES"
  echo "write  $PROFILES"
}

cmd_check() {
  require_config
  if [[ ! -f "$PROFILES" ]]; then
    echo "error: $PROFILES not found. Run \`$(basename "$0") export\` first." >&2
    exit 1
  fi
  if diff -u --label "repo  $PROFILES" --label "live  $CONFIG" \
      <(jq -S . "$PROFILES") <(live_profiles); then
    echo "match  profiles.json and $CONFIG agree"
  else
    echo
    echo "differ  run export to take the live profiles, or apply to push the repo ones"
    exit 1
  fi
}

# The running daemon re-reads config.json before each save and only writes the
# keys that changed. Profiles are the exception here: a profile edit in the app
# sends the whole list the daemon holds in memory, which would replace the list
# apply just wrote until Paseo reloads it.
warn_if_running() {
  local pid
  pid="$(jq -r '.pid // empty' "$PASEO_HOME/paseo.pid" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
    echo "warn  Paseo is running (pid $pid). Quit it first to be safe. If you edit"
    echo "      a profile in the app before you reopen it, the app writes its old"
    echo "      profile list back over the one apply wrote."
  fi
}

link_roles() {
  local force="$1" epoch="$2"
  if [[ -L "$ROLES_DEST" ]]; then
    rm "$ROLES_DEST"
  elif [[ -e "$ROLES_DEST" ]]; then
    if [[ $force -eq 1 ]]; then
      mv "$ROLES_DEST" "$ROLES_DEST.bak-$epoch"
      echo "move  $ROLES_DEST to $ROLES_DEST.bak-$epoch"
    else
      echo "skip  $ROLES_DEST is a real folder, not a link. Use --force to move it aside."
      return
    fi
  fi
  ln -s "$ROLES_SRC" "$ROLES_DEST"
  echo "link  $ROLES_DEST"
}

cmd_apply() {
  local force=0
  case "${1:-}" in
    "") ;;
    --force) force=1 ;;
    *) usage ;;
  esac

  require_config
  if [[ ! -f "$PROFILES" ]]; then
    echo "error: $PROFILES not found." >&2
    exit 1
  fi

  warn_if_running

  # Two runs in the same second would share an epoch, so the second backup
  # would overwrite the first and the second mv would nest the old folder
  # inside the first one. Wait for a second nobody has used.
  local epoch backup tmp
  epoch="$(date +%s)"
  while [[ -e "$CONFIG.bak-paseo-sh-$epoch" || -e "$ROLES_DEST.bak-$epoch" ]]; do
    sleep 1
    epoch="$(date +%s)"
  done
  backup="$CONFIG.bak-paseo-sh-$epoch"
  cp -p "$CONFIG" "$backup"
  echo "backup  $backup"

  # mktemp creates the file 0600 in the same directory, so the mv is atomic
  # and config.json keeps owner-only permissions.
  tmp="$(mktemp "$CONFIG.tmp.XXXXXX")"
  if ! jq --argjson profiles "$(repo_profiles_for_this_home)" '
      .daemon.agentProfiles = $profiles.agentProfiles
      | .daemon.terminalProfiles = $profiles.terminalProfiles
    ' "$CONFIG" > "$tmp"; then
    rm -f "$tmp"
    echo "error: jq failed, $CONFIG is unchanged." >&2
    exit 1
  fi
  mv "$tmp" "$CONFIG"
  echo "write  $CONFIG (daemon.agentProfiles, daemon.terminalProfiles)"

  link_roles "$force" "$epoch"

  echo
  echo "Quit and reopen Paseo to load the profiles."
}

case "${1:-}" in
  export) [[ $# -eq 1 ]] || usage; cmd_export ;;
  check) [[ $# -eq 1 ]] || usage; cmd_check ;;
  apply) shift; [[ $# -le 1 ]] || usage; cmd_apply "$@" ;;
  *) usage ;;
esac

#!/usr/bin/env bash
# Reinstall every skill this machine should have, then link them into each agent.
#
#   1. reads reference-skill-lock.json and reinstalls those skills with the Skills CLI
#   2. runs install.sh to symlink the skills written in this repo
#
# Safe to re-run. Pass --skip-managed to only run step 2.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="$REPO_DIR/reference-skill-lock.json"

SKIP_MANAGED=0
[[ "${1:-}" == "--skip-managed" ]] && SKIP_MANAGED=1

read_packages() {
  # Prints one "owner/repo@skill-name" per line.
  if command -v jq >/dev/null 2>&1; then
    jq -r '.skills | to_entries[] | "\(.value.source)@\(.key)"' "$LOCK_FILE"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
lock = json.load(open(sys.argv[1]))
for name, entry in lock["skills"].items():
    print(entry["source"] + "@" + name)
' "$LOCK_FILE"
  else
    echo "error: need jq or python3 to read $LOCK_FILE" >&2
    exit 1
  fi
}

if [[ $SKIP_MANAGED -eq 0 ]]; then
  if ! command -v npx >/dev/null 2>&1; then
    echo "error: npx not found. Install Node.js, or re-run with --skip-managed." >&2
    exit 1
  fi

  while read -r pkg; do
    [[ -z "$pkg" ]] && continue
    echo "install  $pkg"
    npx skills add "$pkg" -g -y
  done < <(read_packages)
  echo
fi

"$REPO_DIR/install.sh"

cat <<'EOF'

Two sets of skills this script cannot install:

  - Paseo skills: the Paseo app writes them when you run it.
  - impeccable: run `npx impeccable`, which writes one copy per agent.
EOF

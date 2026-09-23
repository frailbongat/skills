#!/usr/bin/env bash
# Put every skill this machine should have back in place.
#
#   1. installs the third-party skills recorded in reference-skill-lock.json,
#      the same set listed in the README table
#   2. runs install.sh to symlink the skills written in this repo
#   3. runs hide-skills.sh to hide the skills in hidden-skills.txt from the
#      system prompt, so a fresh machine gets the same trimmed context
#
# Safe to re-run. Pass --skip-managed to only run steps 2 and 3.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="$REPO_DIR/reference-skill-lock.json"

# shellcheck source=lockfile.sh
source "$REPO_DIR/lockfile.sh"

SKIP_MANAGED=0
[[ "${1:-}" == "--skip-managed" ]] && SKIP_MANAGED=1

if [[ $SKIP_MANAGED -eq 0 ]]; then
  if ! command -v npx >/dev/null 2>&1; then
    echo "error: npx not found. Install Node.js, or re-run with --skip-managed." >&2
    exit 1
  fi

  while IFS=$'\t' read -r name source source_type source_url _; do
    [[ -z "$name" ]] && continue
    # install_args returns one word for GitHub skills and three for URL skills,
    # so it stays unquoted here on purpose.
    args="$(install_args "$name" "$source" "$source_type" "$source_url")"
    echo "install  $name  ($args)"
    # shellcheck disable=SC2086
    # </dev/null keeps the Skills CLI from swallowing the loop's input.
    npx skills add $args -g -y </dev/null
  done < <(lock_rows "$LOCK_FILE")
  echo
fi

"$REPO_DIR/install.sh"

echo
"$REPO_DIR/hide-skills.sh"

cat <<'EOF'

Two sets of skills this script cannot install:

  - Paseo skills: the Paseo app writes them when you run it.
  - impeccable: run `npx impeccable`, which writes one copy per agent.

After either of those, re-run ./hide-skills.sh. It is the only thing that
keeps the hidden set hidden, and any skill install or update undoes it.
EOF

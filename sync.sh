#!/usr/bin/env bash
# Copy this machine's live skill lock file into the repo, so a commit records
# which third-party skills are installed.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE="$HOME/.agents/.skill-lock.json"
COPY="$REPO_DIR/reference-skill-lock.json"

if [[ ! -f "$LIVE" ]]; then
  echo "error: no lock file at $LIVE. Nothing to sync." >&2
  exit 1
fi

cp "$LIVE" "$COPY"
echo "copied $LIVE -> $COPY"
git -C "$REPO_DIR" --no-pager diff --stat -- "$COPY"

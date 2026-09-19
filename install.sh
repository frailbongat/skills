#!/usr/bin/env bash
# Link every skill in this repo into each agent's skills directory.
# Safe to re-run. It replaces its own symlinks and never deletes a real folder.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/skills"

TARGETS=(
  "$HOME/.agents/skills"
  "$HOME/.pi/agent/skills"
  "$HOME/.claude/skills"
  "$HOME/.config/crush/skills"
  "$HOME/.config/devin/skills"
)

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

linked=0
skipped=0

for target in "${TARGETS[@]}"; do
  # Only install into agents that are already set up on this machine.
  parent="$(dirname "$target")"
  if [[ ! -d "$parent" ]]; then
    echo "skip  $target (no $parent)"
    continue
  fi
  mkdir -p "$target"

  for src in "$SRC_DIR"/*/; do
    name="$(basename "$src")"
    dest="$target/$name"

    if [[ -L "$dest" ]]; then
      rm "$dest"
    elif [[ -e "$dest" ]]; then
      if [[ $FORCE -eq 1 ]]; then
        rm -rf "$dest"
      else
        echo "skip  $dest is a real folder, not a link. Use --force to replace it."
        skipped=$((skipped + 1))
        continue
      fi
    fi

    ln -s "$SRC_DIR/$name" "$dest"
    echo "link  $dest"
    linked=$((linked + 1))
  done
done

echo
echo "linked $linked, skipped $skipped"

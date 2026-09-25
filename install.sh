#!/usr/bin/env bash
# Link every skill in this repo into each agent's skills directory. That is
# each folder in skills/, the ones I wrote, and in vendor/, the third-party
# ones I patched.
# Safe to re-run. It replaces its own symlinks and never deletes a real folder.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIRS=(
  "$REPO_DIR/skills"
  "$REPO_DIR/vendor"
)

TARGETS=(
  "$HOME/.agents/skills"
  "$HOME/.pi/agent/skills"
  "$HOME/.claude/skills"
  "$HOME/.config/crush/skills"
  "$HOME/.config/devin/skills"
)

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# Every skill folder, one path per line. Both directories share one namespace
# in each target, so a name in both would have one link silently replace the
# other. Refuse to run instead.
SOURCES="$(for dir in "${SRC_DIRS[@]}"; do
  for src in "$dir"/*/; do
    if [[ -d "$src" ]]; then echo "${src%/}"; fi
  done
done)"

dupes="$(while read -r src; do basename "$src"; done <<< "$SOURCES" | sort | uniq -d)"
if [[ -n "$dupes" ]]; then
  echo "error: these names are in both skills/ and vendor/: $dupes" >&2
  exit 1
fi

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

  while read -r src; do
    [[ -z "$src" ]] && continue
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

    ln -s "$src" "$dest"
    echo "link  $dest"
    linked=$((linked + 1))
  done <<< "$SOURCES"
done

echo
echo "linked $linked, skipped $skipped"

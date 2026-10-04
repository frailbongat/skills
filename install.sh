#!/usr/bin/env bash
# Link every skill in this repo into each agent's skills directory. That is
# each folder in skills/, the ones I wrote, and in vendor/, the third-party
# ones I patched. Folders in claude-only/ go into ~/.claude/skills alone,
# because another agent has its own version, like pi's /ship extension, or the
# skill uses Claude Code frontmatter, like /sync's ${CLAUDE_SKILL_DIR}.
# Safe to re-run. It replaces its own symlinks and never deletes a real folder.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIRS=(
  "$REPO_DIR/skills"
  "$REPO_DIR/vendor"
)

CLAUDE_ONLY_DIR="$REPO_DIR/claude-only"
CLAUDE_TARGET="$HOME/.claude/skills"

TARGETS=(
  "$HOME/.agents/skills"
  "$HOME/.pi/agent/skills"
  "$CLAUDE_TARGET"
  "$HOME/.config/crush/skills"
  "$HOME/.config/devin/skills"
)

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# Every skill folder, one path per line. skills/, vendor/, and claude-only/
# share one namespace in ~/.claude/skills, so a name in two of them would have
# one link silently replace the other. Refuse to run instead.
list_sources() {
  for dir in "$@"; do
    for src in "$dir"/*/; do
      if [[ -d "$src" ]]; then echo "${src%/}"; fi
    done
  done
}
SOURCES="$(list_sources "${SRC_DIRS[@]}")"
CLAUDE_ONLY_SOURCES="$(list_sources "$CLAUDE_ONLY_DIR")"

dupes="$(while read -r src; do if [[ -n "$src" ]]; then basename "$src"; fi; done <<< "$SOURCES"$'\n'"$CLAUDE_ONLY_SOURCES" | sort | uniq -d)"
if [[ -n "$dupes" ]]; then
  echo "error: these names are in more than one of skills/, vendor/, and claude-only/: $dupes" >&2
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

  target_sources="$SOURCES"
  if [[ "$target" == "$CLAUDE_TARGET" ]]; then
    target_sources="$SOURCES"$'\n'"$CLAUDE_ONLY_SOURCES"
  fi

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
  done <<< "$target_sources"
done

echo
echo "linked $linked, skipped $skipped"

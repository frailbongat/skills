#!/usr/bin/env bash
# Hide the skills listed in hidden-skills.txt from the agent's system prompt.
#
# It stamps `disable-model-invocation: true` into each skill's front matter.
# The skill stays installed and stays usable through `/skill:<name>`, it just
# stops costing tokens in every session.
#
# Run it after bootstrap.sh, and again after `npx skills update`, because the
# Skills CLI rewrites SKILL.md from the source repo and drops the stamp.
#
# Safe to re-run. Skips skills already stamped and skills not installed.
#   ./hide-skills.sh            hide everything in the list
#   ./hide-skills.sh --undo     unhide everything in the list
#   ./hide-skills.sh --check    report only, change nothing
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_FILE="$REPO_DIR/hidden-skills.txt"
SKILLS_DIR="$HOME/.agents/skills"
FIELD="disable-model-invocation: true"

MODE="hide"
case "${1:-}" in
  --undo)  MODE="undo" ;;
  --check) MODE="check" ;;
  "")      ;;
  *)       echo "usage: $0 [--undo|--check]" >&2; exit 2 ;;
esac

[[ -f "$LIST_FILE" ]] || { echo "error: no list at $LIST_FILE" >&2; exit 1; }
[[ -d "$SKILLS_DIR" ]] || { echo "error: no skills at $SKILLS_DIR" >&2; exit 1; }

changed=0
already=0
missing=0

while read -r name; do
  # Drop comments and blank lines.
  name="${name%%#*}"
  name="$(echo "$name" | tr -d '[:space:]')"
  [[ -z "$name" ]] && continue

  file="$SKILLS_DIR/$name/SKILL.md"
  if [[ ! -f "$file" ]]; then
    echo "miss  $name (not installed)"
    missing=$((missing + 1))
    continue
  fi

  # Look for the field in the front matter only, which is everything up to the
  # second `---`. A body line that merely mentions it must not count.
  #
  # `exit` inside an awk rule still runs END, so an END that exits would
  # clobber the status. Hence the flags and the single exit in END.
  has_field=0
  awk 'NR == 1 && $0 != "---" { bad = 1; exit }
       NR > 1 && $0 == "---" { exit }
       NR > 1 && $0 ~ /^disable-model-invocation:[[:space:]]*true/ { found = 1; exit }
       END { exit (found && !bad) ? 0 : 1 }' "$file" && has_field=1

  case "$MODE" in
    check)
      [[ $has_field -eq 1 ]] && echo "hidden   $name" || echo "VISIBLE  $name"
      [[ $has_field -eq 1 ]] && already=$((already + 1)) || changed=$((changed + 1))
      ;;
    hide)
      if [[ $has_field -eq 1 ]]; then
        already=$((already + 1))
        continue
      fi
      # Drop any existing copies of the field from the front matter, then put
      # exactly one back before its closing `---`. Rewriting instead of
      # inserting means a half-stamped file lands in the same state as a clean
      # one, so a re-run can never stack the field up.
      awk -v field="$FIELD" '
        NR == 1 { print; next }
        !done && $0 ~ /^disable-model-invocation:/ { next }
        !done && $0 == "---" { print field; print; done = 1; next }
        { print }
      ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      echo "hide  $name"
      changed=$((changed + 1))
      ;;
    undo)
      if [[ $has_field -eq 0 ]]; then
        already=$((already + 1))
        continue
      fi
      awk '
        NR == 1 { print; next }
        !done && $0 == "---" { done = 1; print; next }
        !done && $0 ~ /^disable-model-invocation:/ { next }
        { print }
      ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      echo "show  $name"
      changed=$((changed + 1))
      ;;
  esac
done < "$LIST_FILE"

echo
case "$MODE" in
  check) echo "$already hidden, $changed still visible, $missing not installed" ;;
  hide)  echo "hid $changed, already hidden $already, not installed $missing" ;;
  undo)  echo "unhid $changed, already visible $already, not installed $missing" ;;
esac

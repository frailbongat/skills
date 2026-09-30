#!/usr/bin/env bash
# Print every skill /route can pick from, one per line: its folder, then its
# description. Global skills come from ~/.claude/skills, project skills from
# .claude/skills and .agents/skills in the current directory. Hidden skills
# are included, since those are the ones I forget. Each name prints once:
# many repos keep the same skill in both .claude/skills and .agents/skills,
# and a project copy wins over a global skill of the same name.
set -euo pipefail

# find exits 1 when a repo lacks .claude/skills or .agents/skills, which most do.
for root in .claude/skills .agents/skills "$HOME/.claude/skills"; do
  find -L "$root" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sort || true
done | awk -F/ '!seen[$(NF - 1)]++' | while read -r file; do
  awk -v dir="${file%/SKILL.md}" '
    # A folded description (`description: >`) continues on indented lines.
    function flush() { if (folded) print dir ": " desc; folded = 0 }
    /^---$/ { flush(); if (++fences == 2) exit; next }
    folded && /^([[:space:]]|$)/ { sub(/^[[:space:]]+/, ""); if ($0 != "") desc = desc (desc ? " " : "") $0; next }
    { flush() }
    /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      if ($0 ~ /^[>|][-+]?$/) { folded = 1; desc = ""; next }
      print dir ": " $0
    }
  ' "$file"
done

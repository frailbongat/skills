#!/usr/bin/env bash
# Shared reader for reference-skill-lock.json. Source this, then call lock_rows.
#
# lock_rows <lock-file> prints one tab-separated row per skill:
#   name  source  sourceType  sourceUrl
# Sorted by name.

lock_rows() {
  local lock_file="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -r '
      .skills
      | to_entries
      | sort_by(.key)[]
      | [.key, (.value.source // ""), (.value.sourceType // ""), (.value.sourceUrl // "")]
      | @tsv
    ' "$lock_file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
lock = json.load(open(sys.argv[1]))
for name in sorted(lock["skills"]):
    entry = lock["skills"][name]
    fields = [name, entry.get("source", ""), entry.get("sourceType", ""), entry.get("sourceUrl", "")]
    print("\t".join(fields))
' "$lock_file"
  else
    echo "error: need jq or python3 to read $lock_file" >&2
    return 1
  fi
}

# install_args <name> <source> <sourceType> <sourceUrl> prints the arguments to
# pass to `npx skills add`. GitHub skills use the short owner/repo@skill form;
# anything else falls back to the clone URL plus --skill.
install_args() {
  local name="$1" source="$2" source_type="$3" source_url="$4"

  if [[ "$source_type" == "github" && "$source" == */* ]]; then
    echo "$source@$name"
  elif [[ -n "$source_url" ]]; then
    echo "$source_url --skill $name"
  else
    echo "error: skill $name has no source in the lock file" >&2
    return 1
  fi
}

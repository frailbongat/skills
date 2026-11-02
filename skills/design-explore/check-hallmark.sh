#!/usr/bin/env bash
# Exits 0 only when /design-explore can find Hallmark at the pin and score with it.
# Compares the lock, not SKILL.md bytes, because hide-skills.sh stamps SKILL.md.
set -uo pipefail

PIN="4f6a46c6dc325d40ab268c93e25c7b96676ebccd"
FOLDER_HASH="4d374666c460b7b4bdfd591301976c15a2f2c19b"
SKILL_DIR="$HOME/.agents/skills/hallmark"
LOCK="$HOME/.agents/.skill-lock.json"
LINT="$SKILL_DIR/scripts/sloplint.mjs"

failed=0
pass() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; failed=1; }

echo "mac   $(hostname -s)"

if ! command -v node >/dev/null 2>&1; then
  fail "node not found"
  echo "FAIL"
  exit 1
fi

major="$(node -p 'process.versions.node.split(".")[0]')"
if [[ "$major" -ge 18 ]]; then pass "node $major"; else fail "node $major, need 18 or newer"; fi

if [[ -z "${TOGETHER_API_KEY:-}" ]]; then pass "TOGETHER_API_KEY unset"; else fail "TOGETHER_API_KEY is set, unset it"; fi

if [[ -f "$SKILL_DIR/SKILL.md" ]]; then pass "$SKILL_DIR/SKILL.md"; else fail "no $SKILL_DIR/SKILL.md"; fi
if [[ -f "$HOME/.claude/skills/hallmark/SKILL.md" ]]; then pass "~/.claude/skills/hallmark resolves"; else fail "~/.claude/skills/hallmark does not resolve"; fi

lock_field() {
  node -e 'const l=JSON.parse(require("fs").readFileSync(process.argv[1]));console.log((l.skills.hallmark||{})[process.argv[2]]||"")' "$LOCK" "$1" 2>/dev/null
}
ref="$(lock_field ref)"
hash="$(lock_field skillFolderHash)"
if [[ "$ref" == "$PIN" ]]; then pass "lock ref is the pin"; else fail "lock ref is '${ref}', want $PIN"; fi
if [[ "$hash" == "$FOLDER_HASH" ]]; then pass "lock folder hash matches"; else fail "lock folder hash is '${hash}', want $FOLDER_HASH"; fi

sample="$(mktemp -d)"
trap 'rm -rf "$sample"' EXIT
cat > "$sample/sample.html" <<'HTML'
<!doctype html><html><head><title>Sample</title></head><body><h1>Sample</h1><p>Lorem ipsum</p></body></html>
HTML

(cd "$sample" && node "$LINT" sample.html --render --json > out.json 2> err.txt)
lint_exit=$?
if [[ "$lint_exit" -le 1 && -s "$sample/out.json" ]]; then
  summary="$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1])).summary;console.log(s.fails+"\t"+s.warns+"\t"+s.render)' "$sample/out.json")"
  IFS=$'\t' read -r fails warns render <<< "$summary"
  if [[ "$fails" -ge 1 ]]; then pass "sloplint flags a bad sample: $fails FAIL, $warns WARN"; else fail "sloplint found nothing wrong in a bad sample"; fi
  if [[ "$render" == "ran" ]]; then pass "sloplint rendered in a browser"; else fail "sloplint render: $render"; fi
else
  fail "sloplint exited $lint_exit"
fi

if [[ "$failed" -eq 0 ]]; then echo "PASS"; else echo "FAIL"; fi
exit "$failed"

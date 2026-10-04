#!/usr/bin/env bash
# The helper behind the /sync skill. It brings the current branch up to the
# latest trunk with the user's work on top, so the app runs their changes
# against the newest code:
#
#   sync.sh
#
# A branch that was never pushed, the trunk itself, and a detached HEAD are
# rebased onto origin/<trunk>. A pushed branch merges origin/<trunk> instead,
# because /ship rebases a pushed branch onto origin/<branch> and never force
# pushes, so rewriting its pushed commits would break the next /ship. Both
# carry uncommitted edits across with --autostash.
#
# The first line of stdout is always "status: <word>", and the exit code says
# what to do next:
#
#   0  status synced or current
#   1  status error, the reason is on stderr
#   2  usage error
#   4  status conflict: a rebase, merge, or autostash conflict is waiting
#
# After a conflict is resolved, rerunning sync.sh finishes the run: it reads
# the HEAD from before the sync out of a state file, so the report and the
# lockfile check still cover the whole sync.
#
# Written for the bash 3.2 that ships with macOS: no associative arrays, no
# mapfile, no ${var,,}.
set -o pipefail

TRUNK_CANDIDATES="main master trunk develop"
CONFLICT_SKILL="$HOME/.agents/skills/resolving-merge-conflicts/SKILL.md"
GIT_OPERATION_MARKERS="rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG"
# Checked in this order, and only the first changed one installs. A repository
# with two lockfiles uses one package manager, and running both would fight.
LOCKFILES="pnpm-lock.yaml bun.lock bun.lockb package-lock.json yarn.lock"
MAX_OUTPUT_BYTES=2000

# ---------------------------------------------------------------- output

status() {
  echo "status: $1"
}

fail() {
  status error
  echo "$*" >&2
  exit 1
}

bullets() {
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "- $line"
  done <<< "$1"
}

count_lines() {
  if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}

plural() {
  if [[ "$1" -eq 1 ]]; then echo "$1 $2"; else echo "$1 ${2}s"; fi
}

# The tail of a command's output, capped so a noisy install does not flood
# the session. The tail holds the error.
display_output() {
  local text="$1"
  if [[ ${#text} -le $MAX_OUTPUT_BYTES ]]; then
    printf '%s\n' "$text"
  else
    printf '...\n%s\n' "${text: -$MAX_OUTPUT_BYTES}"
  fi
}

list_unmerged() {
  git ls-files --unmerged | cut -f2 | sort -u
}

# kind is "rebase" (paused mid-rebase), "merge" (paused mid-merge), or "index"
# (unmerged entries from an autostash pop, nothing to continue). Never aborts:
# a conflict is a decision, and the resolver needs the state left on disk.
report_conflict() {
  local kind="$1" paths="$2" message="$3"
  status conflict
  echo "kind: $kind"
  echo
  echo "$message"
  if [[ -n "$paths" ]]; then
    echo
    echo "Conflicted files:"
    bullets "$paths"
  fi
  echo
  case "$kind" in
    rebase)
      echo "Resolve it with $CONFLICT_SKILL. Stage each file as you resolve it and run \`GIT_EDITOR=true git rebase --continue\` until no rebase is in progress. Never abort the rebase." ;;
    merge)
      echo "Resolve it with $CONFLICT_SKILL. Stage each file as you resolve it, then run \`GIT_EDITOR=true git merge --continue\` to finish the merge. Never abort the merge." ;;
    index)
      echo "Resolve it with $CONFLICT_SKILL. These are the user's uncommitted edits, so keep their intent and leave them unstaged. Resolve each file, then clear the conflict with \`git reset -q -- <file>\`. There is no rebase or merge to continue or abort. Leave the autostash entry in \`git stash list\` alone." ;;
  esac
  echo
  echo "When every conflict is resolved, run sync.sh again to finish."
  exit 4
}

# ---------------------------------------------------------------- state

state_file() {
  echo "$GIT_DIR_ABS/sync-state"
}

write_state() {
  {
    echo "branch=$BRANCH"
    echo "old_head=$OLD_HEAD"
    echo "trunk_head=$(git rev-parse "origin/$TRUNK")"
  } > "$(state_file)"
}

# Picks up the HEAD from before a sync that stopped on a conflict. Only the
# HEAD is reused: the mode is resolved fresh, because the branch may have been
# pushed since. A state file from another branch is stale, and so is one whose
# trunk commit HEAD lacks: an aborted sync leaves HEAD without it, while a
# finished --continue or a kind: index stop leaves HEAD with it.
read_state() {
  local key value file saved_branch="" saved_head="" saved_trunk=""
  file="$(state_file)"
  [[ -f "$file" ]] || return 1
  while IFS='=' read -r key value; do
    case "$key" in
      branch) saved_branch="$value" ;;
      old_head) saved_head="$value" ;;
      trunk_head) saved_trunk="$value" ;;
    esac
  done < "$file"
  if [[ "$saved_branch" != "$BRANCH" || -z "$saved_trunk" ]] \
    || ! git cat-file -e "$saved_head^{commit}" 2>/dev/null \
    || ! git merge-base --is-ancestor "$saved_trunk" HEAD >/dev/null 2>&1; then
    rm -f "$file"
    return 1
  fi
  OLD_HEAD="$saved_head"
}

# ---------------------------------------------------------------- preflight

preflight() {
  local inside marker running="" unmerged
  inside="$(git rev-parse --is-inside-work-tree 2>/dev/null)"
  [[ "$inside" == "true" ]] || fail "Current directory is not inside a Git working tree."

  GIT_DIR_ABS="$(git rev-parse --absolute-git-dir)"
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  cd "$REPO_ROOT" || fail "Cannot enter $REPO_ROOT."

  unmerged="$(list_unmerged)"

  # A sync that stopped on a conflict and was not finished yet. Without the
  # state file the rebase or merge is the user's own, so it falls through to
  # the refusal below.
  if [[ -f "$(state_file)" ]]; then
    if [[ -e "$GIT_DIR_ABS/rebase-merge" || -e "$GIT_DIR_ABS/rebase-apply" ]]; then
      report_conflict rebase "$unmerged" "A rebase is still in progress, so the sync is not finished."
    fi
    if [[ -e "$GIT_DIR_ABS/MERGE_HEAD" ]]; then
      report_conflict merge "$unmerged" "A merge is still in progress, so the sync is not finished."
    fi
  fi
  for marker in $GIT_OPERATION_MARKERS; do
    [[ -e "$GIT_DIR_ABS/$marker" ]] && running="$running $marker"
  done
  if [[ -n "$running" ]]; then
    fail "Refusing to sync while a git operation is in progress:$running"
  fi

  # An autostash pop that conflicted leaves unmerged entries with no
  # operation in progress.
  if [[ -n "$unmerged" ]]; then
    report_conflict index "$unmerged" \
      "The index has unmerged entries, most likely from reapplying the uncommitted edits (the autostash) after the sync. The pre-sync snapshot of those edits may still be in \`git stash list\` as an autostash entry."
  fi
}

# ---------------------------------------------------------------- trunk

remote_ref_exists() {
  git rev-parse --verify --quiet "refs/remotes/origin/$1" >/dev/null 2>&1
}

current_branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null
}

# The origin branch this branch is published to, if any. An upstream of
# origin/<trunk> does not count: `git switch -c feat origin/main` tracks the
# trunk without publishing anything.
published_upstream() {
  local upstream
  [[ -n "$BRANCH" ]] || return 1
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || return 1
  [[ "$upstream" == origin/* && "$upstream" != "origin/$TRUNK" ]] || return 1
  echo "${upstream#origin/}"
}

# The trunk is read from the remote, never assumed. Same lookup as ship.sh.
resolve_trunk() {
  local head candidate
  head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  head="${head#origin/}"
  if [[ -n "$head" ]]; then
    TRUNK="$head"
    return
  fi

  for candidate in $TRUNK_CANDIDATES; do
    if remote_ref_exists "$candidate"; then
      TRUNK="$candidate"
      return
    fi
  done

  if [[ -z "$(git remote get-url origin 2>/dev/null)" ]]; then
    fail "This repository has no \`origin\` remote, so there is no trunk to sync with. Add one with: git remote add origin <url>"
  fi
  if [[ -z "$(git for-each-ref --count=1 refs/remotes/origin/)" ]]; then
    fail "Nothing has been fetched from origin yet, so the trunk cannot be read. Fix it with: git fetch origin"
  fi
  fail "Cannot tell which branch is the trunk: origin/HEAD is unset and none of main, master, trunk, develop exist on origin. Fix it with: git remote set-head origin --auto"
}

# Merge for a pushed branch, rebase for everything else. A detached HEAD and
# the trunk itself count as never pushed.
resolve_mode() {
  MODE=rebase
  [[ -n "$BRANCH" && "$BRANCH" != "$TRUNK" ]] || return 0
  if published_upstream >/dev/null || remote_ref_exists "$BRANCH"; then
    MODE=merge
  fi
}

# ---------------------------------------------------------------- sync

fetch_trunk() {
  local output
  if ! output="$(git fetch origin "$TRUNK" --quiet 2>&1)"; then
    fail "Fetching origin/$TRUNK failed:
$(display_output "$output")"
  fi
}

is_synced() {
  git merge-base --is-ancestor "origin/$TRUNK" HEAD >/dev/null 2>&1
}

# A command that never started leaves nothing to resolve, so the reason goes
# to the user. Untracked files that collide with incoming ones are the common
# case, because --autostash does not stash untracked files.
explain_start_failure() {
  local verb="$1" output="$2" hint=""
  rm -f "$(state_file)"
  if printf '%s' "$output" | grep -Eiq 'untracked working tree files would be overwritten'; then
    hint="
Untracked files collide with the incoming commits. --autostash does not stash untracked files, so move or delete them, then run /sync again."
  fi
  fail "Could not $verb origin/$TRUNK, so nothing changed:
$(display_output "$output")$hint"
}

run_rebase() {
  local output
  output="$(git rebase --autostash "origin/$TRUNK" 2>&1)" && return 0
  if [[ -e "$GIT_DIR_ABS/rebase-merge" || -e "$GIT_DIR_ABS/rebase-apply" ]]; then
    report_conflict rebase "$(list_unmerged)" \
      "Rebasing onto origin/$TRUNK hit content conflicts. The rebase is paused mid-conflict."
  fi
  explain_start_failure "rebase onto" "$output"
}

# --ff overrides a merge.ff=only setting, which would refuse a real merge.
run_merge() {
  local output
  output="$(git merge --autostash --ff --no-edit "origin/$TRUNK" 2>&1)" && return 0
  if [[ -e "$GIT_DIR_ABS/MERGE_HEAD" ]]; then
    report_conflict merge "$(list_unmerged)" \
      "Merging origin/$TRUNK hit content conflicts. The merge is paused mid-conflict."
  fi
  explain_start_failure "merge" "$output"
}

# --autostash reapplies the uncommitted edits after the rebase or merge, and
# a conflict there is not part of the exit code.
check_autostash() {
  local paths done_step="Rebasing onto"
  [[ "$MODE" == "merge" ]] && done_step="Merging"
  paths="$(list_unmerged)"
  if [[ -n "$paths" ]]; then
    report_conflict index "$paths" \
      "$done_step origin/$TRUNK succeeded, but reapplying the uncommitted edits (the autostash) left conflicts. The pre-sync snapshot of those edits is still in \`git stash list\` as an autostash entry."
  fi
}

# ---------------------------------------------------------------- install

# Sets INSTALL_RESULT to "none", the command that ran, or "failed: <command>".
run_install() {
  local lockfile changed="" cmd tool output
  for lockfile in $LOCKFILES; do
    if ! git diff --quiet "$OLD_HEAD" HEAD -- "$lockfile" 2>/dev/null; then
      changed="$lockfile"
      break
    fi
  done
  INSTALL_RESULT=none INSTALL_OUTPUT=""
  [[ -n "$changed" ]] || return 0

  case "$changed" in
    pnpm-lock.yaml) cmd="pnpm install" ;;
    bun.lock | bun.lockb) cmd="bun install" ;;
    package-lock.json) cmd="npm install" ;;
    yarn.lock) cmd="yarn install" ;;
  esac
  tool="${cmd%% *}"
  if ! command -v "$tool" >/dev/null 2>&1; then
    INSTALL_RESULT="failed: $cmd"
    INSTALL_OUTPUT="$changed changed, but $tool is not installed."
    return 0
  fi
  if output="$($cmd 2>&1)"; then
    INSTALL_RESULT="$cmd"
  else
    INSTALL_RESULT="failed: $cmd"
    INSTALL_OUTPUT="$changed changed, and \`$cmd\` failed:
$(display_output "$output")"
  fi
}

# ---------------------------------------------------------------- main

main() {
  local resumed=0 incoming

  if [[ $# -gt 0 ]]; then
    echo "Usage: /sync (it takes no arguments)" >&2
    exit 2
  fi

  preflight
  resolve_trunk
  BRANCH="$(current_branch)"
  OLD_HEAD="$(git rev-parse --verify --quiet HEAD)" || fail "This repository has no commits yet."
  read_state && resumed=1
  resolve_mode

  fetch_trunk
  if ! is_synced; then
    write_state
    if [[ "$MODE" == "merge" ]]; then run_merge; else run_rebase; fi
    check_autostash
    is_synced || fail "The $MODE onto origin/$TRUNK reported success but HEAD still does not contain origin/$TRUNK. Sort it out by hand."
  elif [[ $resumed -eq 0 ]]; then
    status current
    echo "trunk: $TRUNK"
    echo
    echo "Already up to date: HEAD already contains origin/$TRUNK."
    exit 0
  fi

  rm -f "$(state_file)"
  run_install

  incoming="$(git log --oneline "$OLD_HEAD..origin/$TRUNK")"
  status synced
  echo "mode: $MODE"
  echo "trunk: $TRUNK"
  echo "install: $INSTALL_RESULT"
  echo
  echo "Pulled in $(plural "$(count_lines "$incoming")" "commit") from origin/$TRUNK:"
  bullets "$incoming"
  echo
  if [[ "$MODE" == "merge" ]]; then
    echo "Merged origin/$TRUNK into $BRANCH, because $BRANCH is already pushed. Nothing was pushed."
  else
    echo "Rebased ${BRANCH:-HEAD} onto origin/$TRUNK, with local commits and uncommitted edits on top. Nothing was pushed."
  fi
  if [[ -n "$INSTALL_OUTPUT" ]]; then
    echo
    echo "$INSTALL_OUTPUT"
  fi
}

main "$@"

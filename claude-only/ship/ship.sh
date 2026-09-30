#!/usr/bin/env bash
# The helper behind the /ship skill. It runs in two phases, because Claude
# writes the commit message between them:
#
#   ship.sh prepare [main|branch] [recheck] [verbose] [refs] [issue-number]
#   ship.sh commit --message "<message>"
#
# prepare checks the repository, syncs with the trunk, stages, runs the
# formatters and linters, and prints the staged diff. A clean tree with
# unpushed commits needs no message, so prepare pushes those itself.
# commit validates the message, commits, and pushes.
#
# The first line of stdout is always "status: <word>", and the exit code says
# what to do next:
#
#   0  status ready, shipped, or nothing
#   1  refused or failed, the reason is on stderr
#   2  usage error
#   3  unused, formerly status confirm
#   4  status conflict: a rebase or autostash conflict is waiting
#   5  status rejected: the commit message broke a rule, rewrite it
#
# Written for the bash 3.2 that ships with macOS: no associative arrays, no
# mapfile, no ${var,,}.
set -o pipefail

COMMIT_TYPES="feat fix refactor perf docs test chore build ci style revert"
SUBJECT_LIMIT=72
MAX_DIFF_BYTES=60000
MAX_OUTPUT_BYTES=2000
MAX_CHECK_FILES=200
PUSH_ATTEMPTS=3
TRUNK_CANDIDATES="main master trunk develop"
CONFLICT_SKILL="$HOME/.agents/skills/resolving-merge-conflicts/SKILL.md"
GIT_OPERATION_MARKERS="rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG"
CHECK_LABELS=("prettier" "eslint" "ruff check" "ruff format" "shellcheck" "gofmt" "rustfmt")
USAGE="Usage: /ship [main|branch] [recheck] [verbose] [refs] [issue-number] (example: /ship main refs 174)"

VERBOSE=0
# 1 when only part of the tree is staged. The sync then waits until the
# subset is committed, because an autostash pops without --index and would
# unstage it. prepare decides it and commit reads it from the state file.
SUBSET=0
# 1 when this run fetched and rebased onto the trunk just before committing,
# so the first push attempt can skip the fetch.
PRESYNCED=0
# Lines said along the way, printed under the status line so it stays first.
NOTICES=""
# Set by the commit phase and by a clean-tree push, where a conflict comes
# after the work already exists and rerunning /ship is the wrong fix.
AFTER_RESOLUTION=""
# Set by land_payload, so a failure while pushing says the work is safe
# locally no matter which step of the retry it came from.
LANDING_FAILURE=""
LANDING_SAFETY=""

# ---------------------------------------------------------------- output

notice() {
  NOTICES="$NOTICES$*"$'\n'
}

status() {
  echo "status: $1"
  if [[ -n "$NOTICES" ]]; then
    echo
    printf '%s' "$NOTICES"
    NOTICES=""
  fi
}

fail() {
  status error
  if [[ -n "$LANDING_FAILURE" ]]; then
    {
      echo "$LANDING_FAILURE:"
      echo "$*"
      echo
      echo "$LANDING_SAFETY Fix the cause and run /ship again."
    } >&2
  else
    echo "$*" >&2
  fi
  exit 1
}

progress() {
  if [[ $VERBOSE -eq 1 ]]; then notice "$*"; fi
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Command output, capped so a runaway formatter does not flood the session.
display_output() {
  local text="$1"
  if [[ ${#text} -le $MAX_OUTPUT_BYTES ]]; then
    printf '%s\n' "$text"
  else
    printf '%s\n...\n' "${text:0:$MAX_OUTPUT_BYTES}"
  fi
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

# Fills the global LIST array from a command's NUL-separated output.
nul_list() {
  local item
  LIST=()
  while IFS= read -r -d '' item; do
    [[ -n "$item" ]] && LIST+=("$item")
  done < <("$@")
}

contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Runs a command and keeps its exit code, stdout, and stderr apart, because
# gofmt reports offenders on stdout with a clean exit.
run_capture() {
  local err_file
  err_file="$(mktemp)"
  RUN_OUT="$("$@" 2>"$err_file")"
  RUN_CODE=$?
  RUN_ERR="$(cat "$err_file")"
  rm -f "$err_file"
}

combined_output() {
  printf '%s\n%s' "$RUN_ERR" "$RUN_OUT" | sed '/^[[:space:]]*$/d'
}

# ---------------------------------------------------------------- preflight

preflight() {
  local inside marker running=""
  inside="$(git rev-parse --is-inside-work-tree 2>/dev/null)"
  [[ "$inside" == "true" ]] || fail "Current directory is not inside a Git working tree."

  GIT_DIR_ABS="$(git rev-parse --absolute-git-dir)"
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  cd "$REPO_ROOT" || fail "Cannot enter $REPO_ROOT."

  # Before anything reads a ref, because a half-finished operation makes every
  # answer below it meaningless.
  for marker in $GIT_OPERATION_MARKERS; do
    [[ -e "$GIT_DIR_ABS/$marker" ]] && running="$running $marker"
  done
  if [[ -n "$running" ]]; then
    fail "Refusing to ship while a git operation is in progress:$running"
  fi

  # An autostash pop that conflicted leaves unmerged entries with no operation
  # in progress. `git add -A` would stage the conflict markers as content.
  local unmerged
  unmerged="$(list_unmerged)"
  if [[ -n "$unmerged" ]]; then
    # With a commit waiting to be pushed, these are the edits that were kept
    # out of it, popped back by the autostash after `git rebase --continue`.
    if [[ "$(sed -n 's/^phase=//p' "$(state_file)" 2>/dev/null)" == "pushing" ]]; then
      AFTER_RESOLUTION="A commit from the last /ship is waiting to be pushed, and these files hold the edits that were kept out of it. Keep them unstaged: resolve each one and clear it with \`git reset -q -- <file>\`. Leave git's autostash entry in \`git stash list\` alone. Then run /ship again with the same arguments."
    fi
    # Without one, nothing was committed or held back yet, so the resolved
    # files belong to this ship and the before-commit advice applies.
    report_conflict index preflight "$unmerged" \
      "The index has unmerged entries from an earlier conflict, most likely a rebase autostash that conflicted when it was reapplied, so nothing was staged or pushed. The pre-rebase snapshot may still be in \`git stash list\` as an autostash entry."
  fi
}

list_unmerged() {
  git ls-files --unmerged | cut -f2 | sort -u
}

# kind is "rebase" (paused mid-rebase) or "index" (unmerged entries, nothing
# to continue). Never aborts: a conflict is a decision, and the resolver needs
# the state left on disk.
report_conflict() {
  local kind="$1" land_on="$2" paths="$3" message="$4"
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
  if [[ "$kind" == "rebase" ]]; then
    echo "Resolve it with $CONFLICT_SKILL. Stage each file as you resolve it and continue until no rebase is in progress. Never abort the rebase."
  elif [[ -n "$AFTER_RESOLUTION" ]]; then
    echo "Resolve it with $CONFLICT_SKILL. These are uncommitted edits that were not part of the commit, so keep their intent and leave them unstaged. Resolve each file, then clear the conflict with \`git reset -q -- <file>\`. There is no rebase to continue or abort."
  else
    echo "Resolve it with $CONFLICT_SKILL. One side of each conflict is uncommitted local work, so keep its intent. When every file is resolved, stage the whole tree with \`git add -A\`, because no commit exists yet and nothing was held back from this ship. There is no rebase to continue or abort."
  fi
  if [[ -n "$AFTER_RESOLUTION" ]]; then
    echo
    echo "$AFTER_RESOLUTION"
  elif [[ -n "$land_on" ]]; then
    echo
    echo "When every conflict is resolved, run /ship again with the same arguments. Do not commit or push the shipped changes yourself."
  fi
  exit 4
}

# ---------------------------------------------------------------- destination

remote_ref_exists() {
  git rev-parse --verify --quiet "refs/remotes/origin/$1" >/dev/null 2>&1
}

current_branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null
}

# The origin branch this branch is published to, if any. An upstream of
# origin/<trunk> does not count: `git switch -c feat origin/main` tracks the
# trunk without publishing anything. Any other origin upstream does, whatever
# its name, like `git switch -c mywork origin/release-1`.
published_upstream() {
  local upstream
  [[ -n "$BRANCH" ]] || return 1
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || return 1
  [[ "$upstream" == origin/* && "$upstream" != "origin/$TRUNK" ]] || return 1
  echo "${upstream#origin/}"
}

# The trunk is read from the remote, never assumed. Hardcoding main would
# create a second trunk called main in a repository whose trunk is master.
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

  # Three different states land here, and each needs its own fix.
  if [[ -z "$(git remote get-url origin 2>/dev/null)" ]]; then
    fail "This repository has no \`origin\` remote, so there is nowhere to ship. Add one with: git remote add origin <url>"
  fi
  if [[ -z "$(git for-each-ref --count=1 refs/remotes/origin/)" ]]; then
    fail "Nothing has been fetched from origin yet, so no remote branch is known locally and the trunk cannot be read. Fix it with: git fetch origin"
  fi
  fail "Cannot tell which branch is the trunk: origin/HEAD is unset and none of main, master, trunk, develop exist on origin. Fix it with: git remote set-head origin --auto"
}

# Sets DEST_KIND (trunk or branch), DEST_REF, DEST_HAS_UPSTREAM, DEST_REASON.
#
# A branch that was never pushed is a scratch pad and lands on the trunk. A
# branch with a remote counterpart was published on purpose, possibly with a
# pull request open, so it stays where it is.
resolve_destination() {
  local override="$1" upstream
  resolve_trunk
  BRANCH="$(current_branch)"
  DEST_HAS_UPSTREAM=0

  if [[ "$override" == "trunk" ]]; then
    DEST_KIND=trunk DEST_REF="$TRUNK" DEST_REASON="you asked for the trunk"
    return
  fi
  if [[ "$override" == "branch" ]]; then
    [[ -n "$BRANCH" ]] || fail "A detached HEAD has no branch to push. Check out a branch, or ship to the trunk."
    DEST_KIND=branch DEST_REF="$BRANCH" DEST_REASON="you asked for this branch"
    if upstream="$(published_upstream)"; then DEST_REF="$upstream" DEST_HAS_UPSTREAM=1; fi
    return
  fi

  if [[ -z "$BRANCH" ]]; then
    DEST_KIND=trunk DEST_REF="$TRUNK" DEST_REASON="a detached HEAD has no branch to push"
    return
  fi
  if [[ "$BRANCH" == "$TRUNK" ]]; then
    DEST_KIND=trunk DEST_REF="$TRUNK" DEST_REASON="you are on $TRUNK"
    return
  fi
  if upstream="$(published_upstream)"; then
    DEST_KIND=branch DEST_REF="$upstream" DEST_HAS_UPSTREAM=1
    DEST_REASON="$BRANCH tracks origin/$upstream"
    return
  fi
  if remote_ref_exists "$BRANCH"; then
    DEST_KIND=branch DEST_REF="$BRANCH" DEST_REASON="origin/$BRANCH already exists"
    return
  fi
  DEST_KIND=trunk DEST_REF="$TRUNK"
  DEST_REASON="$BRANCH was never pushed, so it is a local worktree branch"
}

destination_target() {
  if [[ "$DEST_KIND" == "trunk" ]]; then echo "origin/$DEST_REF"; else echo "$DEST_REF"; fi
}

assert_branch_pushable() {
  [[ -n "$(git remote get-url --push origin 2>/dev/null)" ]] || fail "Remote origin has no push URL."
}

# ---------------------------------------------------------------- sync

is_ancestor_of_head() {
  git merge-base --is-ancestor "origin/$1" HEAD >/dev/null 2>&1
}

fetch_origin_ref() {
  run_capture git fetch origin "$1" --quiet
  if [[ $RUN_CODE -ne 0 ]]; then
    fail "Fetching origin/$1 failed:
$(display_output "$(combined_output)")"
  fi
}

# Leaves HEAD a fast-forward of origin/<ref>, rebasing onto it when it moved.
# --autostash carries the uncommitted edits across the rebase: before a
# commit, the tree the ship is about to stage, and after one, the edits a
# subset ship held back from it.
ensure_fast_forward() {
  local ref="$1" behind mine count
  fetch_origin_ref "$ref"
  is_ancestor_of_head "$ref" && return 0

  behind="$(git log --oneline "HEAD..origin/$ref")"
  mine="$(git log --oneline "origin/$ref..HEAD")"
  count="$(count_lines "$behind")"
  notice "origin/$ref has $(plural "$count" "new commit"), so your work goes on top of it:"
  notice "$(bullets "$behind")"
  if [[ -n "$mine" ]]; then
    notice "Your commits:"
    notice "$(bullets "$mine")"
  fi

  rebase_onto "$ref"
  is_ancestor_of_head "$ref" && return 0
  fail "Rebasing onto origin/$ref reported success but HEAD still does not descend from it, so nothing was pushed. Sort it out by hand."
}

rebase_onto() {
  local ref="$1" output code paths hint="" aborted=""
  output="$(git rebase --autostash "origin/$ref" 2>&1)"
  code=$?

  if [[ $code -eq 0 ]]; then
    # --autostash pops after the replay, and the pop is not part of the exit
    # code. Committing now would ship <<<<<<< markers.
    paths="$(list_unmerged)"
    if [[ -n "$paths" ]]; then
      report_conflict index "$ref" "$paths" \
        "Rebasing onto origin/$ref succeeded, but reapplying the uncommitted working-tree changes (the rebase autostash) left conflicts in the index, so nothing was pushed. The pre-rebase snapshot is still in \`git stash list\` as the autostash entry."
    fi
    return 0
  fi

  if printf '%s' "$output" | grep -Eiq 'could not apply|CONFLICT'; then
    report_conflict rebase "$ref" "$(list_unmerged)" \
      "origin/$ref moved and rebasing onto it hit content conflicts, so nothing was pushed. The rebase is paused mid-conflict."
  fi

  # A rebase that never started. The abort then fails too, and that says so.
  if printf '%s' "$output" | grep -Eiq 'untracked working tree files would be overwritten'; then
    hint=" Untracked files collide with the incoming commits. --autostash does not stash untracked files, so move or delete them, then retry."
  elif printf '%s' "$output" | grep -Eiq 'local changes .* would be overwritten|cannot rebase: you have unstaged'; then
    hint=" The working tree could not be stashed. Commit or stash it yourself, then retry."
  fi
  if git rebase --abort >/dev/null 2>&1; then
    aborted=" The rebase was aborted, so the working tree is where it was."
  fi
  fail "origin/$ref moved and rebasing onto it failed, so nothing was pushed:
$(display_output "$output")
Resolve it by hand.$hint$aborted"
}

# A rejection another fetch and rebase would fix, as opposed to one no retry
# will fix: a protected branch, a bad credential, a hook.
is_stale_rejection() {
  local output="$1"
  if printf '%s' "$output" | grep -Eiq 'protected branch|permission denied|pre-receive hook declined|does not match any'; then
    return 1
  fi
  printf '%s' "$output" | grep -Eiq 'non-fast-forward|fetch first|stale info|Updates were rejected|cannot lock ref|failed to lock'
}

# A branch push always names its refspec, so push.default and a stray
# upstream can never send it somewhere else.
push_args() {
  if [[ "$DEST_KIND" == "trunk" ]]; then
    PUSH_ARGS=(origin "HEAD:$DEST_REF")
  elif [[ "$DEST_HAS_UPSTREAM" -eq 1 ]]; then
    PUSH_ARGS=(origin "HEAD:refs/heads/$DEST_REF")
  else
    PUSH_ARGS=(--set-upstream origin "HEAD:refs/heads/$DEST_REF")
  fi
}

# Push, and survive losing a race to a sibling worktree. A trunk synced
# moments ago skips the fetch on its first attempt.
push_with_retry() {
  local attempt presynced="$PRESYNCED"
  push_args

  for ((attempt = 1; attempt <= PUSH_ATTEMPTS; attempt++)); do
    if ! [[ $attempt -eq 1 && $presynced -eq 1 ]] && remote_ref_exists "$DEST_REF"; then
      ensure_fast_forward "$DEST_REF"
    fi

    PUSH_OUTPUT="$(git push "${PUSH_ARGS[@]}" 2>&1)"
    [[ $? -eq 0 ]] && return 0
    if ! is_stale_rejection "$PUSH_OUTPUT" || [[ $attempt -eq $PUSH_ATTEMPTS ]]; then
      return 1
    fi
    notice "The push to $(destination_target) was rejected because origin/$DEST_REF moved again. Re-syncing and retrying ($attempt/$((PUSH_ATTEMPTS - 1)))."
  done
  return 1
}

describe_commit() {
  local subject
  subject="$(git log -1 --format=%s "$1" 2>/dev/null | head -n 1)"
  if [[ -n "$subject" ]]; then echo "${1:0:7} $subject"; else echo "${1:0:7}"; fi
}

worktree_holding() {
  local branch="$1" line path=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch refs/heads/$branch")
        [[ -n "$path" ]] && echo "$path" && return 0
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
  return 1
}

# Pushing HEAD:main from a worktree moves origin/main and nothing local. Catch
# the local trunk up without ever losing work: no checkout gets a guarded
# update-ref, a clean checkout gets merge --ff-only, anything else is left alone.
sync_local_trunk() {
  local trunk="$1" before remote path
  before="$(git rev-parse --verify --quiet "refs/heads/$trunk")" || return 0
  remote="$(git rev-parse --verify --quiet "refs/remotes/origin/$trunk")" || return 0
  [[ "$before" == "$remote" ]] && return 0

  if ! git merge-base --is-ancestor "$before" "$remote" 2>/dev/null; then
    echo "Local $trunk has diverged from origin/$trunk, so it was left alone. Reconcile it when convenient."
    return 0
  fi

  if ! path="$(worktree_holding "$trunk")"; then
    if git update-ref "refs/heads/$trunk" "$remote" "$before" 2>/dev/null; then
      echo "Fast-forwarded local $trunk to $(describe_commit "$remote")."
    fi
    return 0
  fi

  if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
    echo "$path has $trunk checked out with uncommitted changes, so it was left alone. It is behind origin/$trunk, pull it when convenient."
    return 0
  fi
  local merged
  if merged="$(git -C "$path" merge --ff-only "origin/$trunk" 2>&1)"; then
    echo "Fast-forwarded $trunk to $(describe_commit "$remote") in $path."
  else
    echo "$path is behind origin/$trunk and could not be fast-forwarded. Pull it by hand. $merged"
  fi
}

# Pushes whatever HEAD holds and prints the report. $1 is the report headline
# prefix for a failure, $2 the body under the headline.
land_payload() {
  local failure="$1" body="$2" safety="$3" hash pushed notes line notable=""
  hash="$(git rev-parse --short HEAD)"
  refuse_sensitive_outgoing

  LANDING_FAILURE="${failure//\{hash\}/$hash}"
  LANDING_SAFETY="$safety"
  if ! push_with_retry; then
    fail "$(display_output "$PUSH_OUTPUT")

$(printf '%s\n' "$body" | head -n 1)"
  fi
  LANDING_FAILURE=""

  rm -f "$(state_file)"
  # A retry may have rebased, which gives the commit a new hash.
  pushed="$(git rev-parse --short HEAD)"
  if [[ "$DEST_KIND" == "trunk" && "$BRANCH" != "$DEST_REF" ]]; then
    notes="$(sync_local_trunk "$DEST_REF")"
    # The trunk catching up to the commit just reported is not news.
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == *"${pushed:0:7}"* ]] && continue
      notable="$notable$line"$'\n'
    done <<< "$notes"
  fi

  status shipped
  echo
  echo "${SUCCESS_HEADLINE//\{hash\}/$pushed}"
  echo
  printf '%s\n' "$body"
  if [[ $VERBOSE -eq 1 && -n "$CHECK_SUMMARY" ]]; then
    echo
    echo "Checks: $CHECK_SUMMARY"
  fi
  if [[ -n "$notable" ]]; then
    echo
    bullets "$notable"
  fi
}

# ---------------------------------------------------------------- sensitive paths

is_example_secret() {
  [[ "$1" =~ (^|[._-])(example|sample|template)([._-]|$) ]]
}

is_sensitive_path() {
  local normalized name
  normalized="$(lower "${1//\\//}")"
  name="${normalized##*/}"

  is_example_secret "$name" && return 1
  [[ "$name" == ".env" || "$name" == .env.* ]] && return 0
  case "$name" in
    .netrc | .npmrc | .pypirc | credentials.json | auth.json) return 0 ;;
  esac
  [[ "$name" =~ ^(id_rsa|id_dsa|id_ecdsa|id_ed25519)(\.pub)?$ ]] && return 0
  [[ "$name" =~ \.(pem|key|p12|pfx|jks|keystore)$ ]] && return 0
  [[ "$normalized" =~ (^|/)\.aws/credentials$ ]] && return 0
  [[ "$normalized" =~ (^|/)\.ssh/(config|authorized_keys|known_hosts)$ ]] && return 0
  [[ "$normalized" =~ (^|/)(secrets?|credentials?)(\.(json|ya?ml|toml|ini))?$ ]] && return 0
  return 1
}

refuse_sensitive_paths() {
  local verb="$1" path found=""
  shift
  for path in "$@"; do
    if is_sensitive_path "$path"; then found="$found$path"$'\n'; fi
  done
  [[ -z "$found" ]] && return 0

  local count
  count="$(count_lines "${found%$'\n'}")"
  if [[ $count -eq 1 ]]; then
    fail "Refusing to $verb a sensitive path:
$(bullets "$found")"
  fi
  fail "Refusing to $verb sensitive paths:
$(bullets "$found")"
}

# The commits HEAD would send to DEST_REF, as git log range arguments. A
# branch that was never pushed has no counterpart to subtract, so the range
# becomes every commit no origin ref holds.
outgoing_range() {
  if remote_ref_exists "$DEST_REF"; then
    RANGE=("origin/$DEST_REF..HEAD")
  else
    RANGE=(HEAD --not --remotes=origin)
  fi
}

# Every path the outgoing commits added or modified. Per commit rather than
# one endpoint diff, because a secret added in the first commit and deleted in
# the last is still on its way to the remote. Only the trunk and the
# destination are subtracted, so a published trunk file merged into a branch
# is not news, while a secret published on some other branch still is on its
# way to this one. --no-renames reads a `git mv` onto .env as an added .env,
# and -c shows a file a merge commit added itself.
list_outgoing_paths() {
  local not=()
  if remote_ref_exists "$DEST_REF"; then
    not=("origin/$TRUNK" "origin/$DEST_REF")
  else
    not=(--remotes=origin)
  fi
  nul_list sh -c 'git log -c --format= --name-only -z --no-renames --diff-filter=AM HEAD --not "$@" | tr "\n" "\0" | sort -zu' _ "${not[@]}"
}

refuse_sensitive_outgoing() {
  list_outgoing_paths
  refuse_sensitive_paths push ${LIST[@]+"${LIST[@]}"}
}

# ---------------------------------------------------------------- quality checks

# Sets the SPEC_* globals for one check label. Local tools resolve only inside
# node_modules/.bin, never through npx, which would download a formatter the
# repository does not use.
load_spec() {
  SPEC_FAIL_ON_STDOUT=0 SPEC_FIXES=0 SPEC_CACHE=0
  SPEC_ARGS=() SPEC_WRITE=()
  local prettier_exts="js jsx mjs cjs ts tsx mts cts json jsonc css scss less html vue svelte md mdx yaml yml"
  local eslint_exts="js jsx mjs cjs ts tsx mts cts vue svelte"
  case "$1" in
    prettier)
      SPEC_TOOL=prettier SPEC_SOURCE=local SPEC_EXTS="$prettier_exts" SPEC_FIXES=1
      SPEC_ARGS=(--check) SPEC_WRITE=(--write --log-level=warn) ;;
    eslint)
      SPEC_TOOL=eslint SPEC_SOURCE=local SPEC_EXTS="$eslint_exts" SPEC_CACHE=1 ;;
    "ruff check")
      SPEC_TOOL=ruff SPEC_SOURCE=path SPEC_EXTS="py pyi" SPEC_ARGS=(check) ;;
    "ruff format")
      SPEC_TOOL=ruff SPEC_SOURCE=path SPEC_EXTS="py pyi" SPEC_FIXES=1
      SPEC_ARGS=(format --check) SPEC_WRITE=(format) ;;
    shellcheck)
      SPEC_TOOL=shellcheck SPEC_SOURCE=path SPEC_EXTS="sh bash" SPEC_ARGS=(--severity=warning) ;;
    gofmt)
      SPEC_TOOL=gofmt SPEC_SOURCE=path SPEC_EXTS="go" SPEC_FAIL_ON_STDOUT=1 SPEC_FIXES=1
      SPEC_ARGS=(-l) SPEC_WRITE=(-w) ;;
    rustfmt)
      SPEC_TOOL=rustfmt SPEC_SOURCE=path SPEC_EXTS="rs" SPEC_FIXES=1
      SPEC_ARGS=(--check) ;;
  esac
}

resolve_tool() {
  if [[ "$SPEC_SOURCE" == "local" ]]; then
    [[ -x "$REPO_ROOT/node_modules/.bin/$SPEC_TOOL" ]] && echo "$REPO_ROOT/node_modules/.bin/$SPEC_TOOL"
  else
    command -v "$SPEC_TOOL" >/dev/null 2>&1 && echo "$SPEC_TOOL"
  fi
}

# eslint rehashes an edited config on its own, but not a plugin upgraded under
# the same config, so a manifest newer than the cache drops it.
prepare_cache() {
  local cache="$GIT_DIR_ABS/ship-${1// /-}-cache" manifest
  if [[ -e "$cache" ]]; then
    for manifest in package.json pnpm-lock.yaml package-lock.json yarn.lock bun.lock bun.lockb; do
      if [[ "$REPO_ROOT/$manifest" -nt "$cache" ]]; then
        rm -f "$cache"
        break
      fi
    done
  fi
  echo "$cache"
}

matches_exts() {
  local file="$1" ext
  [[ "$file" == *.* ]] || return 1
  ext="$(lower "${file##*.}")"
  [[ " $SPEC_EXTS " == *" $ext "* ]]
}

has_pre_commit_hook() {
  [[ -e "$REPO_ROOT/.husky/pre-commit" || -e "$GIT_DIR_ABS/hooks/pre-commit" ]]
}

# Runs the path-scoped checks and sets CHECK_SUMMARY, or fails. $1 is "staged"
# for the index, or "committed" for commits already made, whose files must not
# be rewritten because the fix would land in the working tree instead.
run_checks() {
  local mode="$1" files=() held_back=() label binary file cached=() fixable=() check_only=() fixed ran=""
  shift

  if has_pre_commit_hook; then
    CHECK_SUMMARY="skipped (a pre-commit hook runs them at commit time)"
    return
  fi

  if [[ "$mode" == "committed" ]]; then
    files=("$@")
    held_back=("$@")
  else
    nul_list git diff --cached --name-only -z --diff-filter=ACM
    files=(${LIST[@]+"${LIST[@]}"})
    nul_list git diff --name-only -z --diff-filter=ACM
    held_back=(${LIST[@]+"${LIST[@]}"})
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    CHECK_SUMMARY=""
    return
  fi
  if [[ ${#files[@]} -gt $MAX_CHECK_FILES ]]; then
    CHECK_SUMMARY="skipped (${#files[@]} files exceeds the $MAX_CHECK_FILES-file limit)"
    return
  fi

  local intact="changes remain staged"
  local held_back_advice="These files have unstaged edits, so ship will not rewrite them. Format them yourself, or stage the rest of the file."
  if [[ "$mode" == "committed" ]]; then
    intact="nothing was pushed"
    held_back_advice="These files are already committed, so ship will not rewrite them. Format them, commit the result, and run /ship again."
  fi

  for label in "${CHECK_LABELS[@]}"; do
    load_spec "$label"
    fixable=() check_only=() cached=() fixed=0
    for file in "${files[@]}"; do
      matches_exts "$file" || continue
      if [[ $SPEC_FIXES -eq 1 ]] && ! contains "$file" ${held_back[@]+"${held_back[@]}"}; then
        fixable+=("$file")
      else
        check_only+=("$file")
      fi
    done
    [[ $((${#fixable[@]} + ${#check_only[@]})) -eq 0 ]] && continue

    binary="$(resolve_tool)"
    [[ -z "$binary" ]] && continue
    if [[ $SPEC_CACHE -eq 1 ]]; then
      cached=(--cache --cache-location "$(prepare_cache "$label")")
    fi

    if [[ ${#fixable[@]} -gt 0 ]]; then
      progress "Running $label on ${#fixable[@]} file(s)."
      run_capture "$binary" ${cached[@]+"${cached[@]}"} ${SPEC_WRITE[@]+"${SPEC_WRITE[@]}"} "${fixable[@]}"
      # A non-zero exit from a write run is a parse error or a crash.
      if [[ $RUN_CODE -ne 0 ]]; then
        fail "$label failed, $intact:
$(display_output "$(combined_output)")"
      fi
      nul_list git diff --name-only -z -- "${fixable[@]}"
      if [[ ${#LIST[@]} -gt 0 ]]; then
        git add -- "${LIST[@]}" || fail "Restaging $label fixes failed, $intact."
        fixed=${#LIST[@]}
      fi
    fi

    if [[ ${#check_only[@]} -gt 0 ]]; then
      progress "Checking $label on ${#check_only[@]} file(s)."
      run_capture "$binary" ${cached[@]+"${cached[@]}"} ${SPEC_ARGS[@]+"${SPEC_ARGS[@]}"} "${check_only[@]}"
      if [[ $RUN_CODE -ne 0 || ($SPEC_FAIL_ON_STDOUT -eq 1 && -n "${RUN_OUT//[[:space:]]/}") ]]; then
        local advice=""
        [[ $SPEC_FIXES -eq 1 ]] && advice=$'\n'"$held_back_advice"
        fail "$label failed, $intact:
$(display_output "$(combined_output)")$advice"
      fi
    fi

    [[ -n "$ran" ]] && ran="$ran, "
    if [[ $fixed -gt 0 ]]; then
      ran="$ran$label (fixed $(plural "$fixed" file))"
    else
      ran="$ran$label"
    fi
  done

  CHECK_SUMMARY="$ran"
}

# ---------------------------------------------------------------- state

state_file() {
  echo "$GIT_DIR_ABS/ship-prepared"
}

write_state() {
  {
    echo "kind=$DEST_KIND"
    echo "ref=$DEST_REF"
    echo "has_upstream=$DEST_HAS_UPSTREAM"
    echo "branch=$BRANCH"
    echo "tree=$1"
    echo "issue=$ISSUE_NUMBER"
    echo "verb=$ISSUE_VERB"
    echo "verbose=$VERBOSE"
    echo "checks=$CHECK_SUMMARY"
    echo "trunk=$TRUNK"
    echo "subset=$SUBSET"
    echo "phase=$2"
    if [[ "$2" == "pushing" ]]; then
      outgoing_identities | sed 's/^/commit=/'
    fi
  } > "$(state_file)"
}

# "<patch-id> <author key>" for one commit. A retry rebase changes the hash
# but keeps the patch-id. Resolving a conflict changes the patch-id too, but
# keeps the author, the author date, and the message, which the key hashes.
commit_identity() {
  local patch key
  patch="$(git show --no-color --format= "$1" | git patch-id --stable | cut -d' ' -f1)"
  key="$(git log -1 --format='%an%x00%ae%x00%ad%x00%B' --date=raw "$1" | git hash-object --stdin)"
  echo "${patch:--} $key"
}

# One identity per outgoing commit, oldest first.
outgoing_identities() {
  local sha
  outgoing_range
  git rev-list --reverse "${RANGE[@]}" | while read -r sha; do
    commit_identity "$sha"
  done
}

read_state() {
  local key value file
  file="$(state_file)"
  [[ -f "$file" ]] || fail "Nothing is prepared. Run \`ship.sh prepare\` first."
  while IFS='=' read -r key value; do
    case "$key" in
      kind) DEST_KIND="$value" ;;
      ref) DEST_REF="$value" ;;
      has_upstream) DEST_HAS_UPSTREAM="$value" ;;
      branch) BRANCH="$value" ;;
      tree) STATE_TREE="$value" ;;
      issue) ISSUE_NUMBER="$value" ;;
      verb) ISSUE_VERB="$value" ;;
      verbose) VERBOSE="$value" ;;
      checks) CHECK_SUMMARY="$value" ;;
      trunk) TRUNK="$value" ;;
      subset) SUBSET="$value" ;;
      phase) STATE_PHASE="$value" ;;
      commit) SAVED_COMMITS="$SAVED_COMMITS$value"$'\n' ;;
    esac
  done < "$file"
}

# ---------------------------------------------------------------- prepare

parse_prepare_args() {
  local token word override=""
  ISSUE_NUMBER="" KEEP_OPEN=0 OVERRIDE=""
  for token in "$@"; do
    word="$(lower "$token")"
    case "$word" in
      # Existing commits always land now, so the old flag changes nothing.
      --land-existing) ;;
      # Checks always run in this port, so recheck is accepted and changes nothing.
      recheck | check | checks) ;;
      verbose | -v | --verbose | loud) VERBOSE=1 ;;
      refs | ref | --refs | open | keep-open | keepopen | no-close | noclose | wip) KEEP_OPEN=1 ;;
      main | trunk | master) override=trunk ;;
      branch | here) override=branch ;;
      *)
        if [[ "$word" =~ ^[0-9]+$ ]]; then
          [[ -n "$ISSUE_NUMBER" ]] && usage_error "Two issue numbers given."
          [[ "$word" =~ ^[1-9][0-9]{0,14}$ ]] || usage_error ""
          ISSUE_NUMBER="$word"
          continue
        fi
        usage_error "Unrecognized argument \"$token\"."
        ;;
    esac
    if [[ -n "$override" ]]; then
      [[ -n "$OVERRIDE" && "$OVERRIDE" != "$override" ]] && usage_error "Two conflicting destinations given."
      OVERRIDE="$override"
      override=""
    fi
  done
  ISSUE_VERB=closes
  [[ $KEEP_OPEN -eq 1 ]] && ISSUE_VERB=refs
}

usage_error() {
  status error
  if [[ -n "$1" ]]; then echo "$1 $USAGE" >&2; else echo "$USAGE" >&2; fi
  exit 2
}

list_staged() {
  git diff --cached --name-only -z --diff-filter=ACDMRTUXB
}

list_working() {
  git ls-files --modified --deleted --others --exclude-standard -z
}

has_changes_outside_index() {
  ! git diff --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

# owner/repo from a GitHub origin URL, read raw so an insteadOf rewrite does
# not hide it.
origin_repository() {
  local url re='^(https?://(www\.)?github\.com/|git@github\.com:|ssh://git@github\.com/)([^/[:space:]]+)/([^/[:space:]]+)/?$'
  url="$(git config --get remote.origin.url)"
  if [[ "$url" =~ $re ]]; then
    local repo="${BASH_REMATCH[4]}"
    echo "${BASH_REMATCH[3]}/${repo%.git}"
  else
    echo "not GitHub ($url)"
  fi
}

# Why a clean tree had nothing to send. A published branch holding work the
# trunk has not got is the case worth spelling out.
explain_nothing_to_ship() {
  local remote unlanded count
  remote="origin/$DEST_REF"
  status nothing
  echo
  echo "Nothing to ship: the working tree is clean and $remote already has every commit here."
  [[ "$DEST_KIND" == "trunk" ]] && return

  unlanded="$(git log --oneline "origin/$TRUNK..HEAD" 2>/dev/null)"
  [[ -z "$unlanded" ]] && return
  count="$(count_lines "$unlanded")"
  echo
  bullets "$unlanded"
  echo
  if [[ $count -eq 1 ]]; then
    echo "1 commit here is on $remote but not on $TRUNK. Run \`/ship main\` to land it on the trunk."
  else
    echo "$count commits here are on $remote but not on $TRUNK. Run \`/ship main\` to land them on the trunk."
  fi
}

# A clean tree with commits an agent already wrote. No message to write, so
# check what was committed, push it, and report it.
# Runs the secret check and the read-only quality checks on what the outgoing
# commits added or modified. The checks read files from disk, so a path whose
# working tree differs from HEAD is skipped: those bytes are held-back edits,
# not what ships.
check_outgoing_commits() {
  local paths=() present=() path skipped=0
  list_outgoing_paths
  paths=(${LIST[@]+"${LIST[@]}"})
  refuse_sensitive_paths push ${paths[@]+"${paths[@]}"}

  for path in ${paths[@]+"${paths[@]}"}; do
    [[ -e "$path" ]] || continue
    if git diff --quiet HEAD -- "$path"; then
      present+=("$path")
    else
      skipped=$((skipped + 1))
    fi
  done
  run_checks committed ${present[@]+"${present[@]}"}
  if [[ $skipped -gt 0 ]]; then
    CHECK_SUMMARY="${CHECK_SUMMARY:+$CHECK_SUMMARY; }$(plural "$skipped" file) not checked because the working tree has uncommitted edits to them"
  fi
}

ship_committed_work() {
  local lines count commits target
  outgoing_range
  lines="$(git log --oneline "${RANGE[@]}")"
  if [[ -z "$lines" ]]; then
    explain_nothing_to_ship
    exit 0
  fi

  count="$(count_lines "$lines")"
  commits="$(plural "$count" commit)"
  target="$(destination_target)"
  progress "Nothing to commit, so pushing $commits already on ${BRANCH:-HEAD}."

  check_outgoing_commits

  AFTER_RESOLUTION="The $commits being shipped already exist and ride the rebase. When the rebase has fully completed, run /ship again with the same arguments. Do not create another commit."
  SUCCESS_HEADLINE="Shipped $commits to $target."
  local safety="The commits are safe locally."
  [[ $count -eq 1 ]] && safety="The commit is safe locally."
  land_payload "$commits are waiting locally and the push to $target failed" "$lines" "$safety"
}

# Whether HEAD still holds exactly the commits an earlier /ship made and failed
# to push: same branch, a destination the new arguments do not contradict,
# and the same outgoing commits, matched one to one by commit_identity.
pending_push_matches() {
  local current saved line i=0
  [[ "$(current_branch)" == "$BRANCH" ]] || return 1
  [[ -z "$OVERRIDE" || "$OVERRIDE" == "$DEST_KIND" ]] || return 1
  [[ -n "$SAVED_COMMITS" ]] || return 1

  current="$(outgoing_identities)"
  [[ "$(count_lines "$current")" -eq "$(count_lines "${SAVED_COMMITS%$'\n'}")" ]] || return 1
  local saved_lines=()
  while IFS= read -r line; do saved_lines+=("$line"); done <<< "${SAVED_COMMITS%$'\n'}"
  while IFS= read -r line; do
    saved="${saved_lines[$i]}"
    i=$((i + 1))
    [[ "${line%% *}" != "-" && "${line%% *}" == "${saved%% *}" ]] && continue
    [[ "${line#* }" == "${saved#* }" ]] && continue
    return 1
  done <<< "$current"
}

# A commit from an earlier /ship whose push stopped on a conflict or an error.
# It ships as it is, and the tree around it, held-back edits included, stays.
push_pending_commit() {
  local lines count commits target safety="The commits are safe locally."
  outgoing_range
  lines="$(git log --oneline "${RANGE[@]}")"
  count="$(count_lines "$lines")"
  commits="$(plural "$count" commit)"
  target="$(destination_target)"
  [[ $count -eq 1 ]] && safety="The commit is safe locally."
  notice "The last /ship committed but did not push, so this run pushes $commits and commits nothing new."
  # The commits may have changed since the checks in prepare, by an amend
  # that kept the author, date, and message, so check them again.
  check_outgoing_commits
  AFTER_RESOLUTION="The $commits being shipped already exist and ride the rebase. When the rebase has fully completed, run /ship again with the same arguments. Do not create another commit."
  SUCCESS_HEADLINE="Shipped $commits to $target."
  land_payload "$commits are waiting locally and the push to $target failed" "$lines" "$safety"
  exit 0
}

cmd_prepare() {
  parse_prepare_args "$@"
  preflight
  if [[ -f "$(state_file)" ]]; then
    local asked_verbose="$VERBOSE"
    read_state
    [[ $asked_verbose -eq 1 ]] && VERBOSE=1
    if [[ "$STATE_PHASE" == "pushing" ]]; then
      pending_push_matches && push_pending_commit
      notice "An earlier /ship left a commit waiting to be pushed, but this checkout no longer holds exactly that work, so this run starts a fresh ship."
    fi
    rm -f "$(state_file)"
    # read_state loaded an old ship's choices. Start over from the arguments.
    VERBOSE=0 SUBSET=0
    parse_prepare_args "$@"
  fi

  resolve_destination "$OVERRIDE"
  progress "Shipping to $(destination_target) ($DEST_REASON)."

  local staged=() working=() committed_only=0 riders count
  nul_list list_staged
  staged=(${LIST[@]+"${LIST[@]}"})
  nul_list list_working
  working=(${LIST[@]+"${LIST[@]}"})
  [[ ${#staged[@]} -eq 0 && ${#working[@]} -eq 0 ]] && committed_only=1

  assert_branch_pushable
  if [[ "$DEST_KIND" == "trunk" ]]; then
    # What ships is decided here, before any rebase. A staged subset with
    # other edits held back is committed first and synced after, in commit,
    # because an autostash pops without --index. With nothing held back, or
    # nothing staged, the whole tree ships either way and syncs now.
    if [[ ${#staged[@]} -gt 0 ]] && has_changes_outside_index; then
      SUBSET=1
      fetch_origin_ref "$DEST_REF"
    else
      ensure_fast_forward "$DEST_REF"
      PRESYNCED=1
      # The autostash brings a fully staged tree back partly unstaged: new
      # files stay staged, edits do not. Nothing was held back, so staging it
      # all again is the same set.
      if [[ ${#staged[@]} -gt 0 ]]; then
        git add -A || fail "Restaging after the sync failed."
      fi
      nul_list list_staged
      staged=(${LIST[@]+"${LIST[@]}"})
    fi
    # Read after the sync, so the note names what will actually land.
    # On a clean tree these commits are the payload, not extras.
    riders="$(git log --oneline "origin/$DEST_REF..HEAD")"
    if [[ -n "$riders" && $committed_only -eq 0 ]]; then
      count="$(count_lines "$riders")"
      notice "Also landing $(plural "$count" "existing commit") on $DEST_REF:"
      notice "$(bullets "$riders")"
    fi
  fi

  if [[ $committed_only -eq 1 ]]; then
    ship_committed_work
    exit 0
  fi

  # Commits already on HEAD ride along with the new one: riders on
  # the trunk, or unpushed commits on a published branch.
  refuse_sensitive_outgoing

  if [[ ${#staged[@]} -eq 0 ]]; then
    # Re-read after the rebase, because the autostash pop put these back.
    nul_list list_working
    working=(${LIST[@]+"${LIST[@]}"})
    if [[ ${#working[@]} -eq 0 ]]; then
      status nothing
      echo
      echo "Nothing to ship."
      exit 0
    fi
    refuse_sensitive_paths commit "${working[@]}"
    # Nothing staged is the normal path. To ship a subset, stage it first.
    progress "Staging $(plural "${#working[@]}" "changed file") with no staged changes present."
    git add -A || fail "Staging current changes failed."
    nul_list list_staged
    staged=(${LIST[@]+"${LIST[@]}"})
  fi

  if [[ ${#staged[@]} -eq 0 ]]; then
    status nothing
    echo
    echo "Nothing to ship after staging."
    exit 0
  fi
  refuse_sensitive_paths commit "${staged[@]}"

  run_checks staged

  local tree
  tree="$(git write-tree)" || fail "Snapshotting staged changes failed."
  write_state "$tree" prepared

  local diff diff_bytes
  diff="$(git diff --cached --no-ext-diff --no-color --unified=3)"
  diff_bytes="$(printf '%s' "$diff" | wc -c | tr -d ' ')"

  status ready
  echo
  echo "destination: $(destination_target) ($DEST_REASON)"
  echo "origin: $(origin_repository)"
  [[ -n "$CHECK_SUMMARY" ]] && echo "checks: $CHECK_SUMMARY"
  if [[ -n "$ISSUE_NUMBER" ]]; then
    echo "issue: end the subject with \" ($ISSUE_VERB #$ISSUE_NUMBER)\""
  else
    echo "issue verb: $ISSUE_VERB (use \" ($ISSUE_VERB #N)\" if the session names a GitHub issue for this repository)"
  fi
  echo
  echo "Recent subjects, for style only:"
  git log -10 --format=%s 2>/dev/null | sed 's/^/  /'
  echo
  echo "Staged files:"
  git diff --cached --name-status --no-renames
  echo
  echo "Staged stat:"
  git diff --cached --stat --no-ext-diff
  echo
  if [[ $diff_bytes -gt $MAX_DIFF_BYTES ]]; then
    echo "Staged diff, truncated to $MAX_DIFF_BYTES of $diff_bytes bytes:"
    printf '%s' "$diff" | head -c "$MAX_DIFF_BYTES"
    echo
  else
    echo "Staged diff:"
    printf '%s\n' "$diff"
  fi
}

# ---------------------------------------------------------------- commit

# Prints the normalized message on success, or the reason on failure. Perl,
# because the limits count characters and the emoji rule needs Unicode
# properties, neither of which bash 3.2 has.
read -r -d '' MESSAGE_RULES <<'PERL'
use strict;
use warnings;
my ($raw, $types, $limit, $issue, $verb) = @ARGV;
sub reject { print "$_[0]\n"; exit 1; }

reject("message contains a NUL byte") if $raw =~ /\0/;
(my $message = $raw) =~ s/\r\n?/\n/g;
$message =~ s/^\s+|\s+$//g;
reject("message is empty") if $message eq "";
reject("message is too long") if length($message) > 4000;

my @lines = split /\n/, $message, -1;
my $subject = $lines[0];
my $type_alt = join "|", split / /, $types;

reject("subject ends with a period") if $subject =~ /\.$/;
reject("subject is not a valid Conventional Commit, write <type>(<scope>): <summary> with type one of: $types")
  unless $subject =~ /^(?:$type_alt)(?:\([A-Za-z0-9._\/-]+\))?!?: .+[^.]$/;
reject("subject is " . length($subject) . " characters, the limit is $limit")
  if length($subject) > $limit;
reject("subject and body must be separated by a blank line")
  if @lines > 1 && $lines[1] ne "";

for my $i (0 .. $#lines) {
  my $n = $i + 1;
  reject("line $n exceeds $limit characters") if length($lines[$i]) > $limit;
  reject("line $n has trailing whitespace") if $lines[$i] =~ /\s$/;
}

reject("message contains emoji") if $message =~ /\p{Extended_Pictographic}/;
if ($message =~ /\b(this commit|generated with|co-authored-by|assisted-by)\b/i) {
  reject("message contains prohibited attribution: \"$1\"");
}
if ($message =~ /(\bI\b|\bwe\b|\bnow\b|\bcurrently\b)/i) {
  reject("message contains narration: \"$1\", describe the change instead");
}
reject("body uses * bullets instead of - bullets")
  if grep { /^\* / } @lines[2 .. $#lines];

my $breaking = $subject =~ /!:/;
my $revert = $subject =~ /^revert/;
reject("breaking commit lacks a BREAKING CHANGE footer")
  if $breaking && $message !~ /^BREAKING CHANGE: .+/m;
reject("revert commit lacks an explanatory body") if $revert && @lines < 3;
reject("a body is only allowed for a breaking change or a revert, keep the subject and drop the body")
  if @lines > 1 && !$breaking && !$revert && $message !~ /^BREAKING CHANGE: /m;

# An issue reference lives only at the end of the subject.
my $suffix = qr/ \((closes|refs) #([1-9]\d*)\)$/;
my ($used_verb, $used_issue) = $subject =~ $suffix;
my $rest = $message;
if (defined $used_verb) {
  (my $bare = $subject) =~ s/$suffix//;
  $rest = join "\n", $bare, @lines[1 .. $#lines];
}
reject("an issue reference goes only at the end of the subject, as \" (closes #N)\" or \" (refs #N)\"")
  if $rest =~ /#\d+/;
if ($issue ne "") {
  reject("the subject must end with \" ($verb #$issue)\"")
    unless defined $used_issue && $used_issue eq $issue && $used_verb eq $verb;
} elsif (defined $used_verb && $used_verb ne $verb) {
  reject("use \" ($verb #$used_issue)\", this ship " . ($verb eq "refs" ? "keeps the issue open" : "closes the issue"));
}

print $message;
PERL

cmd_commit() {
  local message="" has_message=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --message | -m)
        [[ $# -ge 2 ]] || { status error; echo "--message needs a value." >&2; exit 2; }
        message="$2" has_message=1
        shift 2
        ;;
      *)
        status error
        echo "Unrecognized argument \"$1\". Usage: ship.sh commit --message \"<message>\"" >&2
        exit 2
        ;;
    esac
  done
  [[ $has_message -eq 1 ]] || { status error; echo "Usage: ship.sh commit --message \"<message>\"" >&2; exit 2; }

  preflight
  read_state
  [[ "$STATE_PHASE" == "prepared" ]] || fail "The last commit is waiting to be pushed. Run /ship again to push it."
  [[ "$DEST_KIND" == "trunk" && $SUBSET -eq 0 ]] && PRESYNCED=1

  local checked
  if ! checked="$(perl -CSA -e "$MESSAGE_RULES" -- "$message" "$COMMIT_TYPES" "$SUBJECT_LIMIT" "$ISSUE_NUMBER" "$ISSUE_VERB")"; then
    status rejected
    echo "reason: $checked"
    echo
    echo "Nothing was committed. Rewrite the message and run commit again."
    exit 5
  fi

  local tree
  tree="$(git write-tree)" || fail "Rechecking staged changes failed."
  if [[ "$tree" != "$STATE_TREE" ]]; then
    rm -f "$(state_file)"
    fail "The staged changes changed since prepare. Run /ship again."
  fi

  local message_file
  message_file="$(mktemp)"
  printf '%s\n' "$checked" > "$message_file"
  run_capture git commit --file "$message_file"
  rm -f "$message_file"
  if [[ $RUN_CODE -ne 0 ]]; then
    fail "Creating the commit failed, changes remain staged:
$(display_output "$(combined_output)")"
  fi
  # A rerun of prepare pushes this commit instead of starting a new ship.
  write_state "" pushing

  local hash subject target
  hash="$(git rev-parse --short HEAD)"
  subject="$(printf '%s\n' "$checked" | head -n 1)"
  target="$(destination_target)"
  AFTER_RESOLUTION="Commit $hash ($subject) was already created and rides the rebase. When the rebase has fully completed, run /ship again with the same arguments. It pushes this commit and creates no new one."
  SUCCESS_HEADLINE="Shipped {hash} to $target."
  land_payload "Committed {hash} but the push to $target failed" "$checked" "The commit is safe locally."
}

# ---------------------------------------------------------------- main

case "${1:-}" in
  prepare) shift; cmd_prepare "$@" ;;
  commit) shift; cmd_commit "$@" ;;
  *)
    status error
    echo "Usage: ship.sh prepare [main|branch] [recheck] [verbose] [refs] [issue-number]" >&2
    echo "       ship.sh commit --message \"<message>\"" >&2
    exit 2
    ;;
esac

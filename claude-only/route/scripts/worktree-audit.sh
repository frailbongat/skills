#!/usr/bin/env bash
# Ported from pstack (MIT, Lauren Tan, commit d0ef80d). Changes: LAST_CHAT reads
# Claude Code transcripts at ~/.claude/projects/<slug>/*.jsonl in place of Cursor's
# ~/.cursor/projects/<slug>/agent-transcripts, with the slug turning every character
# that is not a letter or digit into "-", as Claude Code does. Claude Code gives
# each worktree's sessions their own slug dir, where Cursor kept one dir per repo,
# so the path match runs over the slug dirs of the main repo and every worktree,
# and the newest chat in the worktree's own slug dir counts too. The path match uses grep -rl in place of rg -l, since rg is a
# zsh function in Claude Code's shell here, not a binary bash can run. A chat counts
# only when a transcript line has a cwd at or under the worktree, or it made an Edit,
# Write, or NotebookEdit call on a file there. A bare path match also counted chats
# that only read, grepped, or discussed the path, which held worktrees from the prune.
# Read-only worktree prune audit. Classifies every git worktree by size, merge
# state, uncommitted work, remote/PR state, and the most recent chat that
# operated in it. Emits a table sorted by size with a suggested bucket. Never
# deletes anything; deletion stays a human-gated step in the playbook.
#
# Usage: worktree-audit.sh [repo-path]   (defaults to the current repo)
set -u

repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$repo" ] && { echo "not in a git repo; pass a repo path" >&2; exit 1; }
cd "$repo" || exit 1

# Main worktree is the first entry; everything else is a candidate.
main_wt=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')

# origin/main drives the merge check. Best-effort; stale is fine for a first pass.
git fetch origin main --quiet 2>/dev/null || echo "warn: could not fetch origin/main; merged column may be stale" >&2

# PR state by branch, fetched once. Empty if gh is unavailable.
prs=$(mktemp)
gh pr list --author "@me" --state all --limit 1000 \
	--json number,state,headRefName 2>/dev/null > "$prs" || echo "[]" > "$prs"

# Transcripts dirs: ~/.claude/projects/<slug>, where <slug> is the session's cwd
# with every character that is not a letter or digit turned into "-". Each worktree's sessions get their own dir.
slug() { printf '%s' "$1" | sed 's#[^a-zA-Z0-9]#-#g'; }
transcripts=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r w; do
	d="$HOME/.claude/projects/$(slug "$w")"; [ -d "$d" ] && printf '%s\n' "$d"; done)
now=$(date +%s)

# True when a transcript line has a cwd at or under $wt, or an Edit, Write, or
# NotebookEdit tool call on a file at or under $wt.
operated='def in_wt: type == "string" and (. == $wt or startswith($wt + "/"));
any(inputs | fromjson? | objects; (.cwd | in_wt) or any(.message.content?[]? | objects
	| select(.type == "tool_use" and (.name | IN("Edit", "Write", "NotebookEdit")));
	(.input.file_path // .input.notebook_path) | in_wt))'

printf "SIZE\tAGE\tMERGED\tDIRTY\tREMOTE\tPR\tLAST_CHAT\tBUCKET\tWORKTREE\n"

git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
	[ "$wt" = "$main_wt" ] && continue

	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}')
	head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
	head_ts=$(git -C "$wt" log -1 --format='%ct' HEAD 2>/dev/null || echo 0)
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of main, so PR state is the
	# real signal; merge-base only catches fast-forward/rebase merges.
	git merge-base --is-ancestor "$head" origin/main 2>/dev/null && merged=YES || merged=no

	# Distinguish real WIP (tracked edits) from disposable untracked scratch.
	porcelain=$(git -C "$wt" status --porcelain 2>/dev/null)
	if [ -z "$porcelain" ]; then dirty=clean
	elif printf '%s\n' "$porcelain" | grep -qv '^??'; then
		dirty="wip:$(printf '%s\n' "$porcelain" | grep -cv '^??')"
	else dirty="scratch:$(printf '%s\n' "$porcelain" | grep -c '^??')"; fi

	branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
	if [ -z "$branch" ]; then remote=detached
	elif git -C "$wt" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		[ "$(git -C "$wt" rev-parse "origin/$branch" 2>/dev/null)" = "$head" ] \
			&& remote=pushed \
			|| remote="ahead$(git -C "$wt" rev-list --count "origin/$branch..HEAD" 2>/dev/null)"
	else remote=no-remote; fi

	pr=$([ -n "$branch" ] && jq -r --arg b "$branch" \
		'.[] | select(.headRefName==$b) | "#\(.number)/\(.state)"' "$prs" 2>/dev/null | head -1)
	[ -z "$pr" ] && pr="-"

	# Most recent chat whose transcript operated in this worktree. grep -F finds
	# transcripts that name the path, then jq keeps those with a cwd or an edited
	# file at the worktree or under it. The exact-or-"/" test keeps glint-482 from
	# matching glint-482-r37. A session started inside the worktree writes to the
	# worktree's own slug dir.
	last="-"; last_ts=0
	own="$HOME/.claude/projects/$(slug "$wt")"
	f=$( { [ -n "$transcripts" ] && printf '%s\n' "$transcripts"; [ -d "$own" ] && printf '%s\n' "$own"; } \
		| sort -u | tr '\n' '\0' | xargs -0 grep -rlF --include='*.jsonl' -e "$wt" 2>/dev/null \
		| while read -r t; do jq -nRe --arg wt "$wt" "$operated" "$t" >/dev/null 2>&1 && printf '%s\n' "$t"; done \
		| tr '\n' '\0' | xargs -0 stat -f '%m %N' 2>/dev/null | sort -rn | head -1)
	if [ -n "$f" ]; then last_ts=$(echo "$f" | awk '{print $1}')
		last=$(date -r "$last_ts" '+%Y-%m-%d' 2>/dev/null); fi
	recent=$([ "$last_ts" -gt 0 ] 2>/dev/null && [ $(( (now - last_ts) / 86400 )) -le 4 ] && echo yes || echo no)

	case "$dirty" in wip:*) bucket=hold-wip ;; *)
		case "$pr" in *OPEN*) bucket=hold-open-pr ;; *)
			if [ "$recent" = yes ]; then bucket=verify-recent-chat
			elif [ "$merged" = YES ] || [ "$pr" != "-" ]; then bucket=safe
			else bucket=review; fi ;;
		esac ;;
	esac

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$remote" "$pr" "$last" "$bucket" "$wt"
done | sort -t$'\t' -k1,1 -rh

rm -f "$prs"

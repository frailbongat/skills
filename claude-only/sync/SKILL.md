---
name: sync
description: Bring the current branch up to the latest trunk, with your work on top.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/sync.sh *), Bash(${CLAUDE_SKILL_DIR}/sync.sh)
---

# Sync

`/sync` updates the current branch to the latest trunk before the user starts the app. `sync.sh` does all the git work: it fetches the trunk, rebases a branch that was never pushed or merges the trunk into a pushed one, carries uncommitted edits across, and runs the package install when the lockfile changed. It never pushes.

## Steps

1. Run `${CLAUDE_SKILL_DIR}/sync.sh`. The first line of output is `status: <word>`:
   - `synced`: go to [Report](#report).
   - `current`: tell the user the branch already has the latest trunk and stop.
   - `conflict`: go to [Conflicts](#conflicts).
   - `error`: show the user the reason and stop.

## Conflicts

The script leaves every conflict on disk for you to resolve. The user's `/sync` authorizes the resolution.

1. Read `~/.agents/skills/resolving-merge-conflicts/SKILL.md` and follow its steps 1 to 4 for the files the output lists. Skip its step 5, because step 2 below finishes the operation instead.
2. Finish the git operation the `kind:` line names, keeping it going to the end:
   - `kind: rebase`: stage each resolved file and run `GIT_EDITOR=true git rebase --continue` until no rebase is in progress.
   - `kind: merge`: stage each resolved file and run `GIT_EDITOR=true git merge --continue`.
   - `kind: index`: these are the user's uncommitted edits, which git reapplied after the rebase or merge. Resolve each file and clear it with `git reset -q -- <file>`, so it stays uncommitted and unstaged. Leave the autostash entry in `git stash list` alone.
3. Rerun step 1. Git reapplies the uncommitted edits after a rebase or merge ends, so the rerun can report `kind: index`. Handle it the same way.

After three conflicts in one `/sync`, stop and tell the user which files are still conflicted.

## Report

From the `synced` output, tell the user:

1. How many trunk commits came in, with the one-line list the script printed.
2. Whether the branch was rebased or merged, from the `mode:` line.
3. The `install:` line. `none` means no lockfile changed. `failed: <command>` means the user runs that command by hand, so show the reason under it.
4. That they restart the app to pick up the new code.

When a `kind: index` conflict came up during this run, add that the autostash entry in `git stash list` holds the pre-sync copy of their edits, and they can drop it once the resolved files look right.

---
name: pr-review-gate
description: "Review gate for a PR a /route playbook opened. The top session runs it before its final reply."
disable-model-invocation: true
---

After a playbook opens a PR, get it a fresh review before your final reply. Only the top session does this. A subagent that opens a PR names `/no-comments`, `interrogate`, and the reviewer it needs in its report and hands back.

Skip this in Autopilot-full and Autopilot-stack, which verify each PR with their own swarm.

Add the review as the last task in the playbook todo list, then run these steps in order.

1. Run `/no-comments`, then `interrogate`, and fix their findings, so the fresh `reviewer` is the last gate.
2. Launch a new Paseo `reviewer` on the PR. Its brief asks it to answer 4 questions with yes, no, or n/a, each with a link or a quote as proof:
   - Does the failing test commit come before the fix commit?
   - Does each number the PR claims match its source?
   - Does the last line follow the `Closes` or `Refs` rule in `~/.claude/skills/ship-or-refs/SKILL.md`?
   - Does the Scope section name what the PR leaves out?

   A question is n/a when the PR has nothing it applies to, such as no fix, no numbers, or no issue, or when the PR states why a playbook step skipped it. A no counts as a P1.
3. Send the reviewer's P0 and P1 findings to a fresh `worker` in a worktree on the PR's branch, which pushes there. Then launch a new reviewer on the new head. In a stack, rebase each child onto the fixed tip before its review. Stop after 2 fix rounds and name what is still open.
4. Post the last verdict as a comment on the PR, so I can see it on GitHub. The comment starts with `Review verdict:` and the reviewer's BLOCK, OK, or OK with notes. It lists the 4 questions with their answers and proof, then any P0 or P1 still open.
5. Run `~/.claude/skills/route/scripts/watch-pr/watch-pr --status-only --pretty --owner <owner> --repo <repo> --pr <number>`. In a stack, run it on the bottom PR with `--stack`. When CI is pending, run the same command without `--status-only` and with `--timeout 1800`, in the background with a Bash `timeout` of 1900000, then read its last line.
6. Write the `### Next` sentence. When the table shows a failing check or an unresolved thread, or the background run ends on any line but `READY`, the sentence is `babysit PR <number>` and names the problem. Otherwise the sentence names the PR to merge, the bottom one first in a stack, or what blocks it. When it names a PR to merge, it tells me to watch the PR's video or screenshots, or to read the diff when it has none, and to merge if the change does what I asked. It also names any ticket I must close by hand and any work still open on it. Either sentence replaces `/ship` and the ship-or-refs sentence.

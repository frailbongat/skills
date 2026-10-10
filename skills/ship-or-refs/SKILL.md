---
name: ship-or-refs
description: "Decide between closing a ticket and `/ship refs` in the `### Next` sentence, and between `Closes` and `Refs` in a PR description. Use when a Linear key, GitHub issue, or pasted plan is in the session."
---

## Finding the ticket

Look for a ticket in the session only. A Linear or Jira key like `ABC-123`, a GitHub issue like `#42` or its URL, or a ticket file or plan I pasted or attached. Judge it from what is already in the session. Do not go fetch the tracker. No ticket in the session means no ticket in the sentence. Never guess an id.

## Before you say "close"

Only say close when the ticket is genuinely ready to close. All of this has to be true:

- Every ask in the ticket is done, not just the part I scoped out loud.
- You verified it in this session. Tests pass, the command ran, the behavior changed.
- Nothing is left but my review and the commit.

All true, and a ticket is ready to close, say it as one sentence:

```
### Next

Ship and close #42.
```

## When the work is already committed

Some agents commit as they go. Run `git status --porcelain`: when it prints nothing and `git log --oneline @{push}..HEAD` (or `origin/main..HEAD`) prints commits, `/ship` pushes those commits and writes no commit message at all. Neither `refs` nor `closes` has a subject to land on, so the ticket will not shut by itself.

Say `/ship` on its own then, and name the ticket as mine to close:

```
### Next

/ship, then close #42 yourself, the work is already committed so ship writes no closing reference.
```

If the ticket is not ready, the sentence is the same minus the close, with what is still open named.

## When it is not ready

If any of the three fails, do not say close. Say `/ship refs`, which references the issue without closing it, and name what is still open in the same sentence:

```
### Next

/ship refs, #42 stays open until the retry path has a test.
```

When I only scoped part of the ticket, say so and name the rest:

```
### Next

/ship refs, then #42 still wants the rate-limit headers and the 429 retry.
```

## Closes or Refs in a PR description

When the task came from a GitHub issue and the PR finishes it by the three checks above, end the PR description with `Closes #<number>`, so the merge closes the issue. Otherwise end it with `Refs #<number>`. GitHub ignores `Closes` on a PR whose base is not the default branch.

In a stack, run `gh api repos/<owner>/<repo> --jq .delete_branch_on_merge`. When it prints `true`, each PR that finishes its own issue carries `Closes`, because GitHub retargets the next PR to the default branch when it deletes the merged branch. Otherwise only the root PR carries `Closes`.

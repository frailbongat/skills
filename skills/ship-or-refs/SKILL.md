---
name: ship-or-refs
description: "Decide between closing a ticket and `/ship refs` in the `### Next` sentence. Use when a Linear key, GitHub issue, or pasted plan is in the session."
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

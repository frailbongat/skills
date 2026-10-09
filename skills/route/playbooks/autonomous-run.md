### Autonomous run

<!-- Ported from pstack (MIT, Lauren Tan, commit d0ef80d). Changes: Cursor's `/loop` became Claude Code's background Bash and `Monitor` tools, so the watcher subagent became a watcher command, and the time-based and fixed-interval heartbeats became background `sleep` commands. `AskQuestion` became `AskUserQuestion`, and poteto-mode became route. -->

**You own the exit condition. Define done, then drive to it without stopping.**

1. State the exit condition as a checkable predicate before the first iteration (tests green, repro fixed, all N PRs merged, pixel-diff zero).
2. Pick the wake mechanism using Claude Code's background tools. A Bash command run with `run_in_background: true` wakes you once, when it exits, and times out after 2 hours at most. The `Monitor` tool wakes you on each line a script prints, and expires after 30 minutes at most. Re-arm either one when it times out. An event to watch (CI, a merge, a ref advancing) gets a watcher command that exits on the event, with a long background `sleep` as fallback. No event gets a background `sleep` sized to when the result is worth re-checking.
3. Each iteration makes the smallest change the evidence justifies, verifies it against the predicate, commits if it advanced, discards changes that didn't help. Belt-and-suspenders that "might help" gets reverted, not left to ride.
   Sequence the work via the **sequence-verifiable-units** principle skill, verifying each unit before the next instead of batching checks at the end.
4. Mid-run discoveries are yours. Address broken skills, related bugs, flaky verifiers, review noise, tooling failures, orphaned follow-ups, and fixable drift yourself via route. Put out-of-band fixes in their own PR. Do not park reversible work for the human or use `AskUserQuestion`. Surface only irreversible actions, genuine product or preference calls no experiment can settle, or a real dead end. Keep the predicate as the main drive, and return to it after each side fix.
5. Checkpoint every iteration via the **show-me-your-work** skill, a row for what changed and whether the predicate moved.
6. Stop when the predicate is met. A plateau is not a stop, so keep going and pivot your approach to push past it. Surface a genuine dead end rather than spinning, and never relax the predicate to declare victory.

**Reply:** the exit condition, iterations run, what landed, what was discarded, final predicate state.

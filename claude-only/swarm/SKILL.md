---
name: swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration."
disable-model-invocation: true
---

# Swarm

Ported from pstack's `swarm` (MIT, Lauren Tan, commit d0ef80d) for Claude Code. Changes: the intro and Phase A step 3 say "workers" and "concurrency limit" in place of "cloud workers" and "cloud concurrency limit", Phase B drops `environment: "cloud"` and the `environment: "local"` rule, and a worker that needs a non-default pushed branch gets it named in its brief and starts from it in its own git worktree in place of `cloud_base_branch`, since Paseo agents run on this machine and have no cloud environment. Phase A step 4 reads `~/.claude/rules/pstack-models.md` in place of `~/.cursor/rules/pstack-models.mdc`, since that is the always-applied rule `setup-pstack` writes for Claude Code. Its default is `claude-fable-5-1` at xhigh thinking in place of `grok-4.7-xhigh-fast`, since a Paseo subagent sets the thinking level in its own field, not in the slug, per the `setup-pstack` port. Step 4 says "subagent launcher" in place of "Task tool", and Phase B drops `subagent_type: generalPurpose`, since `~/.claude/CLAUDE.md` runs subagents as Paseo agents. Phase B spawns workers in the background with notify on finish in place of `run_in_background: true`, since that is a Cursor `Task` parameter that the Claude Code Agent tool shares, `~/.claude/settings.json` denies that tool, and subagents run as Paseo agents.

Fan out N parallel workers. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare `first pass`, `rank all`, or `best-of` before spawning.
3. Set N from the user or derive it from the shape. N is total workers, not the concurrency limit.
4. Pick the worker model from the `swarm workers` line in `~/.claude/rules/pstack-models.md`. If the rule or that line is missing, use `claude-fable-5-1` at xhigh thinking. For `auto` or `inherit-parent`, omit `model` so the workers run on the parent model. If the subagent launcher rejects a slug, use the default and say so. If it rejects the default, use the closest valid slug of the same family from its error message. For a model race, name each arm's model up front.
5. Give each worker its own writable output when it writes. When workers verify or measure commits, each brief names the exact SHAs. A measurement brief also names the method (sample count, what one sample is, order). The worker records both in its result.

## Phase B: Fan out

Spawn all N workers in one message, in the background with notify on finish, and with the step 4 model, left unset for `auto` or `inherit-parent`.

When a worker must start from a non-default pushed branch, name that branch in its brief and have the worker start from it in its own git worktree.

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence. A worker that can prove a defect reports `ISSUES` and lists every issue it can prove, not only the first.

If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read the terminal results. Drop a result that does not record the SHAs and method its brief names, and respawn that worker once. After a second miss, record a gap. A gap does not count as a pass. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.

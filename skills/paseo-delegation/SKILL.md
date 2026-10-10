---
name: paseo-delegation
description: Route a task to the right Paseo subagent profile. Use before starting work yourself, when choosing among scout, researcher, worker, reviewer, and oracle, when running agents in parallel, or when briefing one.
---

Read the **paseo** skill for the tool details. The profiles are already set up, so call `list_profiles` and materialize the one that fits into `create_agent`.

## Which profile

- Recon in code you have not read yet goes to `scout`.
- Docs, APIs, versions, and anything about the outside world goes to `researcher`.
- Checking whether a research brief's claims hold up goes to `evidence-auditor`, never the agent that wrote the brief.
- Implementation goes to `worker`. One writer per task.
- Every diff, plan, or PR gets a fresh `reviewer` before I see it.
- A decision that feels risky gets `oracle` before you act on it.
- Security audits, vulnerability hunts, and pen-test requests go to `security-auditor`.
- Anything else that is well specified goes to `delegate`.

## Where the work lands

The work lands in my session: its directory and the branch I am on. Create every agent without `workspaceId`, so it runs in this workspace and a worker commits on this branch.

When the task belongs to another repo, create a worktree workspace in that repo with `create_workspace`, branched off `origin/main`. Pass its `workspaceId` to every worker and reviewer on the task.

Use a worktree workspace only when two writers run at the same time. Branch it from my current branch. When its work passes review, bring it home: from my session's directory, fast-forward or merge the worktree branch into my branch, then archive the workspace, which deletes the worktree. Paseo keeps the branch, but the repo's `paseo.json` teardown script runs on archive and may delete it with `git branch -D`. The task is done only once its commits sit on my branch.

## Fresh agents

Start a fresh agent for every task and every fix round, so each agent's context stays under 150k tokens. Brief it with file paths, commit hashes, and the findings to fix, and leave out the conversation that led there. Send a follow-up to a running agent only to answer a question it asked mid-task.

## Only the top session launches agents

When your prompt starts with "Follow the role brief in ~/.paseo/agent-roles/...", you are a subagent. Do your task, then hand back to the agent that launched you. End your report by naming the reviewer or follow-up agent the work needs, and let that agent launch it. This covers skills that launch agents, such as the `/code-review` step at the end of `implement`.

The reason: Paseo tells a parent only that its child's turn ended. A subagent that launches its own agents ends its turn to wait for them, so the parent hears about that pause. The subagent's final report then reaches nobody.

## Running them

Run agents in parallel when their tasks do not depend on each other. Launch several reviewers at once for correctness, tests, and unnecessary complexity.

Each agent starts with zero context, so make the briefing self-contained. Name files by path and let the agent read them instead of pasting their contents. Name a finished agent's report as "the last activity of Paseo agent <id>". The agent reads it with `get_agent_activity` and `limit: 1`, which returns the full final report.

Leave `notifyOnFinish` on and keep working. Do not poll `list_agents` to check on a running agent.

Name the agents you launched and what each one is for, one line each.

## Schedules

1. Before `create_schedule`, run `list_schedules` and `inspect_schedule` on one result. Copy the user's repo, cwd, isolation, and prompt-file layout.
2. A schedule prompt that deletes or sends gets a fresh `reviewer` before `create_schedule`, like any diff. The reviewer checks that each rule in the prompt is safe to run unattended.
3. Dry-run the exact prompt from the cwd and isolation the schedule will use. Turn deletes off and leave every other step on, including commit, land, and teardown.
4. Create the schedule, then keep it paused with `pause_schedule` until its prompt file is on the branch its worktree starts from.

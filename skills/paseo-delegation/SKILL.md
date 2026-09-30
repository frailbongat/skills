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

Use a worktree workspace only when two writers run at the same time. Branch it from my current branch. When its work passes review, bring it home: from my session's directory, fast-forward or merge the worktree branch into my branch, then archive the workspace, which deletes the worktree and its branch. The task is done only once its commits sit on my branch.

## Fresh agents

Start a fresh agent for every task and every fix round, so each agent's context stays under 150k tokens. Brief it with file paths, commit hashes, and the findings to fix, and leave out the conversation that led there. Send a follow-up to a running agent only to answer a question it asked mid-task.

## Running them

Run agents in parallel when their tasks do not depend on each other. Launch several reviewers at once for correctness, tests, and unnecessary complexity.

Each agent starts with zero context, so make the briefing self-contained. Name files by path and let the agent read them instead of pasting their contents.

Leave `notifyOnFinish` on and keep working. Do not poll `list_agents` to check on a running agent.

Name the agents you launched and what each one is for, one line each.

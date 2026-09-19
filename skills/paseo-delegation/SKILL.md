---
name: paseo-delegation
description: Route a task to the right Paseo subagent profile. Use before starting work yourself, when choosing among scout, researcher, worker, reviewer, and oracle, when running agents in parallel, or when briefing one.
---

Read the **paseo** skill for the tool details. The profiles are already set up, so call `list_profiles` and materialize the one that fits into `create_agent`.

## Which profile

- Recon in code you have not read yet goes to `scout`.
- Docs, APIs, versions, and anything about the outside world goes to `researcher`.
- Checking whether a research brief's claims hold up goes to `evidence-auditor`, never the agent that wrote the brief.
- Implementation goes to `worker`. One writer per task, in a worktree workspace when tasks run side by side.
- Every diff, plan, or PR gets a fresh `reviewer` before I see it.
- A decision that feels risky gets `oracle` before you act on it.
- Anything else that is well specified goes to `delegate`.

## Running them

Run agents in parallel when their tasks do not depend on each other. Launch several reviewers at once for correctness, tests, and unnecessary complexity.

Each agent starts with zero context, so make the briefing self-contained. Name files by path and let the agent read them instead of pasting their contents.

Leave `notifyOnFinish` on and keep working. Do not poll `list_agents` to check on a running agent.

Name the agents you launched and what each one is for, one line each.

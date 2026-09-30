---
name: route
description: Pick the skill that fits a task, write its prompt, and run it.
disable-model-invocation: true
argument-hint: "[issue-url|pr-url|#42|prompt]"
---

# Route

`/route` picks the lead skill that fits my task and up to 2 helpers, writes the prompt, and runs it in this session, so I never have to remember which skill does what.

## Steps

1. Read the **task** from the arguments.
   - For a GitHub issue URL or `#42`, run `gh issue view <it> --comments`. The issue is the task.
   - For a GitHub PR URL, run `gh pr view <it> --comments`. The PR is the task.
   - Any other text is the task as I wrote it.
   - With no arguments, the task is whatever this session has been working toward.

   This step is done when you can state the task in one sentence.

2. Run [`list-skills.sh`](list-skills.sh), next to this file, from the repo root. It prints one **candidate** per line: the skill's folder, then its description. Skip `route`, `ship`, `ship-or-refs`, and `ask-matt`. I run `ship` myself, `ship-or-refs` only runs inside other replies, and `ask-matt` is the map you read in step 3, never a pick. Name only candidates in every later step, because `ask-matt` and `FLOWS.md` mention skills that may not be installed.

3. Pick one **lead** skill and up to 2 **helpers**. Read `~/.claude/skills/ask-matt/SKILL.md` for the order of Matt's skills, and [`FLOWS.md`](FLOWS.md), next to this file, for my flows, the tie-breaks, and the helper rules. Where `FLOWS.md` and `ask-matt` differ, `FLOWS.md` wins. Then check the task against every candidate's description. The lead is the skill for the first step of the work. For example, a task that still needs a spec starts at `to-spec`, not `implement`. If a project skill (a folder under the repo's `.claude/skills/` or `.agents/skills/`) fits as well as a global one, pick the project skill, because it wraps the global one for this repo.
   - Route an issue by its state. Check its labels, its author against `gh api user --jq .login`, and its body. The label names below are the defaults, and the repo's `docs/agents/triage-labels.md` maps them to other names when it exists.
     - An agent-ready ticket has the `ready-for-agent` label, or I opened it and it has the `to-tickets` sections `What to build`, `Acceptance criteria`, and `Blocked by`. It goes to `implement`.
     - An issue labeled `needs-triage` or `needs-info`, or a raw issue someone else opened, goes to `triage`.
     - A bug I opened goes to `diagnosing-bugs`.
     - An issue labeled `ready-for-human` needs a person. Tell me that and stop.
     - A huge, foggy goal, too big for one session, goes to `wayfinder`.
   - If two skills fit about equally as the lead, name each in one line and ask me to pick. Wait for my answer.
   - If none fits, say so in one line and do the task as a plain prompt. That ends the route.

4. Read the lead's `SKILL.md`, then write the **prompt**: the arguments the lead expects, filled in from the task. Include the goal, the issue or PR number, file paths, and every constraint from the ticket and my words. Name each helper by the folder `list-skills.sh` printed, with the part it covers, for example "for the UI parts, read and follow `~/.claude/skills/impeccable/SKILL.md`". Before your next tool call, send me a message with one line naming the lead, the helpers, and why they fit, then the whole prompt in a code block. I read it while the lead runs and stop the run if the prompt is wrong, so show it every time and keep going without waiting for me. Step 5 uses this exact prompt, word for word.

5. Run the lead right away. Where it runs depends on whether it talks to me.
   - When the task is a GitHub issue, first run `gh issue edit <it> --add-assignee @me`, whatever the lead. The assignee marks the ticket as taken, and most leads never assign it.
   - A lead that asks me questions partway through, such as `grill-with-docs`, `triage`, `wayfinder`, or `design-explore`, runs in this session. Use the Skill tool when the lead is in your skill list. If it isn't, read the `SKILL.md` in the folder `list-skills.sh` printed and follow it with the prompt as its arguments.
   - Every other lead, such as `implement`, `code-review`, or `security-audit`, runs as a Paseo agent. Read `~/.claude/skills/paseo-delegation/SKILL.md` and launch the profile it names for that work, such as `worker` for `implement`. The brief is the prompt from step 4, plus the path of the lead's `SKILL.md` and each helper's `SKILL.md` for the agent to follow. Name the agent you launched and what it is for, then wait for its report.

6. When the lead or its agent finishes, name the skill most likely to come next in the reply's next-action line, such as `to-spec` after `grill-with-docs`.

---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Ported from pstack's `reflect` (MIT, Lauren Tan, commit d0ef80d) for Claude Code. Changes: step 1 finds the transcript under `~/.claude/projects/<workspace-slug>/` in place of Cursor's `agent-transcripts/`, with Claude Code's two layouts, `$CLAUDE_CODE_SESSION_ID.jsonl` for this session, and the opening prompt read from the first `user` line, since Claude Code's system prompt names no transcript folder and its first lines are queue records. Steps 2 and 3 launch subagents in place of `Task` calls with `subagent_type: generalPurpose`, say the subagent launcher rejects a slug in place of the Task tool, have reviewers return findings in their final report in place of the `Task` response body, read `~/.claude/rules/pstack-models.md` in place of `pstack-models.mdc`, and default to `claude-opus-5-5` and `claude-fable-5-1` at xhigh thinking, per the `setup-pstack` port. Step 5 hands substantive edits and new skills to route's Authoring a skill playbook and description tuning to the **writing-for-agents** skill, in place of Cursor's built-in `create-skill`, so the routing label `new skill via create-skill:` became `new skill via authoring-a-skill:` here and in `references/synthesizer.md`. The reviewer templates in `references/` look for skill reads under `.claude/skills/`, `~/.claude/skills/`, and `~/.claude/plugins/`, add `Skill` tool calls, name subagent prompts in place of `Task` prompts, and say Bash in place of Shell. They carry no attribution line, since each is passed to a subagent verbatim. Step 1's `ls` starts with `setopt nullglob`, since zsh aborts the command with "no matches found" when no `subagents/` folder exists. Steps 2 and 3 drop agent mode (`readonly: false`) and "Readonly strips MCPs", and keep why each subagent needs MCP, since `readonly` was a Cursor `Task` parameter, Paseo agents keep MCP in every mode, and read-only now comes from the brief.

Mine the current conversation for durable learnings, then route them into skill edits.

## When to invoke

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## Process

### 1. Locate the active transcript

The parent finds its own transcript file before fanning out. The active workspace's transcripts live in `~/.claude/projects/<workspace-slug>/`, where `<workspace-slug>` is the session's working directory with every character that is not a letter or digit turned into `-`. Use that path. Do not glob across `~/.claude/projects/*/`. That crosses workspace boundaries and reads private chats from unrelated projects.

```bash
setopt nullglob 2>/dev/null; ls -t <transcripts>/*.jsonl <transcripts>/*/subagents/*.jsonl 2>/dev/null | head -10
```

Two transcript layouts: session (`<session-id>.jsonl`, and this session's is `$CLAUDE_CODE_SESSION_ID.jsonl`) and subagent (`<session-id>/subagents/agent-<id>.jsonl`).

For each candidate, read the first JSONL line whose `type` is `user` and check that `message.content[0].text` contains the conversation's opening user prompt. Take the matching path. If no path resolves, write a tight digest of the session and pass that instead.

### 2. Spawn three reviewers in parallel

One message, three subagents, with `model` set as below. Reviewers need MCP access for context lookups (tickets, chat threads, observability traces referenced in the transcript).

Each reviewer and the synthesizer name a role line in the `~/.claude/rules/pstack-models.md` rule and a default. Set `model` to that line's value, or to the default if the rule or the line is missing. Leave `model` unset when the value is `auto` or `inherit-parent`. If the subagent launcher rejects a slug, use the default and say so. If it rejects the default, use the closest valid slug of the same family from its error message.

| Lens | Role line | Default `model` | Prompt template |
|---|---|---|---|
| Judgment | `reflect judgment, divergent, synthesizer` | `claude-opus-5-5` at xhigh thinking | `references/judgment-reviewer.md` |
| Tooling | `reflect tooling` | `claude-fable-5-1` at xhigh thinking | `references/tooling-reviewer.md` |
| Divergent | `reflect judgment, divergent, synthesizer` | `claude-opus-5-5` at xhigh thinking | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in their final report.

### 3. Synthesize

One subagent, with `model` from the `reflect judgment, divergent, synthesizer` line (default `claude-opus-5-5` at xhigh thinking). The synthesizer's quality check includes spot-verifying citations, which can require MCP access. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. The synthesizer returns a structured Accepted / Rejected / Backlog list.

### 4. Structural enforcement check

Sanity-check the synthesizer's Accepted list. For any item that would be enforced more reliably by a lint rule, script, metadata flag, or runtime check, move it from Accepted to Backlog. See the **encode-lessons-in-structure** principle skill.

### 5. Apply

Before applying any Accepted edit, present the synthesizer's full Accepted/Rejected/Backlog output to the user and wait for explicit approval. The user picks which subset to apply and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

Backlog items file to whatever devex / backlog tracker your team uses automatically. Only the Accepted list waits for approval.

For each approved Accepted item, follow the Routing field exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): parent does directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to route's Authoring a skill playbook (`~/.claude/skills/route/playbooks/authoring-a-skill.md`) and run its write / validate / test steps.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to the **writing-for-agents** skill and rework the description per its Context pointers section.
- `new skill via authoring-a-skill: <kebab-name>`: hand creation to the Authoring a skill playbook. Do not invent the shape ad hoc.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done. Skip this step if it doesn't.

### 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.

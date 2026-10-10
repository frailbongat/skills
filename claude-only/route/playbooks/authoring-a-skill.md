### Authoring or modifying a skill

<!-- Ported from pstack (MIT, Lauren Tan, commit d0ef80d). Changes: step 1 names the **writing-for-agents** skill in place of Cursor's built-in **create-skill**. Step 2 also checks that every agent a step starts is a Paseo subagent started from the top session, since Paseo tells a parent only that its child's turn ended, so a report from an agent a subagent starts reaches nobody. -->

**You own the skill's voice.**

1. Use the **writing-for-agents** skill.
2. Validate the skill: frontmatter has `name` and `description`, referenced files exist, cross-skill links resolve, and every step that starts an agent, directly or through a skill it calls, starts a Paseo subagent and runs only in the top session (the **paseo-delegation** skill).
3. Test cases if structural. Skip if subjective.
4. Run **Opening a PR**.

When in doubt, delete. Keep only prose that changes a decision. Tell it to do the thing and skip the reason. Explain only when the rule is confusing without one. Match tone to scope. Point at structural sources (types, READMEs, config) per the **encode-lessons-in-structure** principle skill. Delegate to other skills by path. Don't restate. A workflow you keep hitting but isn't captured → propose a new skill.

**Reply:** summary of the skill, key design decisions, validation notes.

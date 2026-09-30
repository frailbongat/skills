# Flows

My flows, tie-breaks, and helper rules.

## My flows

- **Design.** `impeccable` is the entry point for design work on one UI: build, critique, audit, or polish it. When I want to compare looks, `design-explore` builds variants of one screen or component in the running app with a dev-only switcher. Once I pick a winner, `/design-explore lock <variant-id>` keeps it and deletes the rest, most often in a fresh session.
- **Stuck.** When the work keeps looping or I want an outside take, `paseo-advisor` asks one agent for a judgment and leaves the work with me. `paseo-committee` puts two agents from different providers on root cause analysis and a plan. Pick the committee when the work is stuck, the advisor when I only want a second opinion.
- **Security.** A full `security-audit` runs as a Paseo agent on the `security-auditor` profile, which launches its own subagents and returns the path to `REPORT.md`. Launch it as `~/.claude/skills/paseo-delegation/SKILL.md` says, with the task as its prompt.
- **Handoff.** `handoff` writes a handoff document to the temp directory for a session I open myself, in a new harness or directory. `paseo-handoff` gives the task to a Paseo agent that starts on it now.

## Tie-breaks

- **Grilling.** Inside a repo, `grill-with-docs` beats `grilling` and `grill-me`. Outside a repo, `grill-me` wins.
- **Design.** Design work starts at `impeccable` or `design-explore`. Pick these only when I name them:
  - the near-duplicate design skills `design-taste-frontend-v1`, `high-end-visual-design`, `gpt-taste`, `stitch-design-taste`, `industrial-brutalist-ui`, `minimalist-ui`, and `redesign-existing-projects`
  - the image-generation skills `brandkit`, `image-to-code`, `imagegen-frontend-web`, and `imagegen-frontend-mobile`
- **Motion.** `animate` covers web, and `animate-expo` covers Expo and React Native.
- **Build.** `implement` is the lead only for a ticket or a spec. A concrete task with no spec starts at the specialist skill that matches it, such as `animate-expo` for a swipe-to-dismiss sheet in Expo, with no grilling first.

## Helpers

A **helper** is a skill the lead skill loads for one part of the task. The lead gets up to 2 helpers, and only when the task clearly needs them:

| The task has | Helper |
| --- | --- |
| UI work | `impeccable` |
| motion | `animate` for web, `animate-expo` for Expo |
| a frontend library to pick | `pick-ui-library` |

The cap is 2 because each helper loads its whole `SKILL.md` into the lead's session. When more than 2 fit, keep the 2 that cover the most of the task.

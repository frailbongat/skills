---
name: create-verification-skill
description: "Generate a project-local verification skill that drives your app the way a user does, for any language, framework, or platform. Use for /create-verification-skill, \"make a verify skill for this repo\", or when a project has no scripted way to prove UI, CLI, or service behavior."
disable-model-invocation: true
---

# Create a verification skill

Ported from pstack's `create-verification-skill` (MIT, Lauren Tan, commit d0ef80d) for Claude Code.

Every project needs a scripted way to drive the real app and prove behavior. The skill launches the app, uses one feature the way a user would, and captures evidence. This skill generates that as a project-local skill at `.claude/skills/verify-<app>/`, tailored to the repo. Write it for the next agent, not for a human. An agent that has never seen the app will read it cold, mid-task.

## 1. Interview the repo, not the user

Answer these 5 questions from the codebase. Ask the user only what you cannot observe. If the brief already answers a question, check that answer against the repo and say where it was wrong.

- **Surface.** What does a user touch? A web UI, a CLI or TUI, a desktop app, an API, a mobile app, a library? A repo can have several. Pick the primary one and note the rest.
- **Run.** How does the app start locally? Prefer the repo's own dev command from package scripts, `paseo.json`, a Makefile, or the README. Note ports, env vars, seed data, and auth.
- **Drive.** How can an agent use it from code? Look for existing harnesses first: Playwright or Cypress specs, expect scripts, PTY helpers, curl-able endpoints, a debug port. Only then pick a generic recipe: browser or CDP for web and Electron, tmux or a PTY for CLI and TUI, plain HTTP for services, `axe` and `xcrun simctl` for the iOS simulator.
- **Observe.** What evidence can it capture? Screenshots, video, terminal transcripts, response bodies, logs, exit codes, database rows.
- **Isolate.** Can 2 instances run side by side, with separate ports, data dirs, profiles, or simulators? If not, say so in the generated skill. Refusing to drive a shared instance beats corrupting the user's session.

If the checkout doesn't build or start as-is, fix that first or report it precisely before generating. A skill written against a broken base teaches wrong steps. When an irrelevant missing asset blocks startup, such as a static dir the API never serves or a sample config, the generated skill may create it. Mark it as verification scaffolding and remove it in cleanup.

## 2. Generate the skill

Write `.claude/skills/verify-<app>/SKILL.md` with YAML frontmatter. It needs `name: verify-<app>` and a `description` that names the app, the surface, and when to use it. Without frontmatter the skill never registers. Write these sections, each grounded in what the interview found, with no placeholders left:

- **Launch.** The exact command that starts the app for verification, and how to tell it's ready: a log line, a port answering, a prompt, an element on screen. Include teardown. A short-lived CLI or TUI has no server to keep alive. There, launch means build the binary or install deps once, then start each drive in its own isolated PTY or tmux session.
- **Doctor.** One read-only check that answers "is this instance worth driving?": process up, right build, port owned by this run, auth valid. An agent runs this first whenever anything looks off.
- **Drive.** The harness recipe with real selectors and commands from this repo, not examples. Prefer stable handles like accessibility labels, test IDs, data attributes, prompt strings, and route paths over coordinates and tab order.
- **Evidence.** What to capture for a proof and where it goes. State the proof standards. Use the real user path, not internal setters or test-only endpoints. Capture the action and the resulting state, not just the final screen. Check side effects like files written, rows inserted, and messages sent alongside what's visible. Use mocks only where a production boundary already isolates the external system. When the safe path is a dry run or test mode, observe what it skips through files, network, and git refs rather than trusting its name. Some dry runs still touch the network or open a browser.
- **Cleanup.** How to tear down what the run created. Never kill by process name. Kill what you started. Cleanup removes instances and scratch state, never the evidence. Proof artifacts survive teardown in a location the skill names.
- **Helpers.** Every script the skill ships is executable, lives in the skill folder, and has its command shown in the skill body. A helper the reader has to reverse-engineer is not a helper.

## 3. Seed the feature map

Create `.claude/skills/verify-<app>/features/README.md` plus one file per user-facing feature you can identify. Aim for the top 3 to 5 to start, found from routes, commands, menus, or docs. Follow the shape in [`references/feature-map-example/`](references/feature-map-example/): a README index and one file per feature. Each file answers, from the user's point of view, what the feature is, how to reach it, how to drive it with the harness, and what observable end state proves it works. Use exactly these 4 H2s: `Sub-features`, `How to get to it (user POV)`, `Driving it with <harness>`, and `Gotchas`. The map is the repo's maintained verification source. A proof that drives one convenient entry point is incomplete when the map lists others.

## 4. Prove the generated skill before handing it over

Run its own instructions end to end once: launch, doctor, drive ONE mapped feature, capture evidence, clean up. One feature is enough, since the map exists so later runs can cover the rest. After cleanup, confirm the evidence still exists at the named location. A cleanup that deletes the proof fails this step. Fix what fails, and run the generated cleanup after every failed attempt too, so broken attempts don't strand processes, ports, or simulators. A generated skill that was never executed is a draft, not a deliverable.

## 5. Hand back and offer the maintenance loop

Report the branch, the commit, and the evidence paths from step 4. Point the user at `/maintain-verification-skill` for keeping the map honest as the app changes. Suggest a cadence only if they ask.

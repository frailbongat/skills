# Explore briefs

Fill every `<...>` before sending, with absolute paths. `<skill-dir>` is `~/.pi/agent/skills/design-explore`. `<Name>` is the view's component name without `View`, such as `Profile`.

## Scout brief

```
Scout a design exploration of <target> in <repo-path>. Write one file, brief.md, and report back. Every other file stays as it is.

1. Platform. From package.json, the platform is `expo` when expo-router is a dependency, `next` when next is a dependency and the project has an `app/` or `src/app/` folder, and `vite` for plain React on Vite. For anything else, stop and report what you found.
2. Placement. Find the file that renders <target> today, or report that the target is new. Read the "Where files go" and "Switcher" sections of <skill-dir>/WEB.md for next or vite, or <skill-dir>/EXPO.md for expo. Following them, name the owner file, the view file, the target's `_variants/` folder, the source root, and the root layout file. Find the typecheck and lint commands in package.json.
3. Brief. Write `brief.md` in the target's `_variants/` folder with these five sections:
   - `## Target` says what it is, where it renders, what it must show and do, and the data it gets today.
   - `## Brand lock` lists every color, font, logo file, and spacing, radius, and motion token, each with its value and the file it lives in.
   - `## Current look` names 2 or 3 existing screens and says what they share in layout, density, type scale, and motion.
   - `## Assets` lists the images and icons the project already has, with paths.
   - `## UI stack` names the styling system, animation libraries, and icon set in package.json.
   When DESIGN.md exists at the repo root, build Brand lock and Current look from it and PRODUCT.md, and skip the screen scan. DESIGN.md and PRODUCT.md stay as they are, and when they are missing they stay missing.

Done when brief.md has all five sections, each filled from files you read.

Report: platform, owner file (or "new"), view file, target `_variants/` folder, source root, root layout file, typecheck command, lint command.
```

## Variant brief

Send one per skill. `<ids>` is `<skill>-1 and <skill>-2`, or `<skill>-1` alone with per-skill 1. Keep the bold `<skill>-2` line only when `<ids>` holds a `-2`.

```
Build <ids>, design variants of <target> in <repo-path>, with the <skill> design skill. Other workers build other variants in this checkout at the same time, so write only the files named below.

Read first:
- <variants-dir>/brief.md. It holds all the design context. Take every answer from it, because the user is not available for questions.
- <skill-md-path>. Bring its taste and craft rules. Where it conflicts with this brief, this brief wins.
- <view-file>, for the props contract `<Name>ViewProps` and, when the view already has UI, the incumbent design.
- The "Variants on this platform" section of <skill-dir>/<WEB.md or EXPO.md>.

What to build:
- `<skill>-1` is safe. It stays close to the current screens in the brief, with better craft.
- `<skill>-2` is bold. It pushes layout, hierarchy, and motion as far as the skill's taste goes.
- Each variant is one file, `<variants-dir>/<variant-id>.tsx`, with a default export that takes `<Name>ViewProps`. Helper parts go in the same file or in files named `<variant-id>.<part>.tsx`.
- The scope is the target alone. A component variant is that component, not a page around it.

Rules:
- Keep the brand lock. Use only the colors, fonts, logo, and tokens in the brief. Layout, hierarchy, spacing, and motion are yours.
- Stay look-only. Take the props as they are, fetch no data, keep only local UI state, import only dependencies already in package.json, and use only assets already in the project.
- When the skill calls for a library the project lacks, get the same effect with what the project has.
- Your checks are the ones below, in place of the design skill's build, screenshot, and handoff steps.

Done when every file for <ids> exists, `<typecheck-command>` shows no errors in your files, and your files import only React, the platform, existing project modules, and existing dependencies.

Report: each variant id, its direction in one line, and what it changes from the incumbent.
```

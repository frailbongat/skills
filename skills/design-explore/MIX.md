# Mix

Mix builds one new variant from the parts of other variants that the user's notes name, and makes the parts work as one design. One `worker` builds it. The words target, view, variant, mix, brand lock, look-only, pick, steals, and `<ext>` mean what [SKILL.md](SKILL.md) says. Launch the subagent as the `paseo-delegation` skill says.

## Steps

### 1. Find the exploration

Run `git status --porcelain`. If it prints anything, ask the user how to handle those changes and wait, so the mix commit holds only the mix.

Take the exploration this session explored. In a fresh session, find `state.json` with `git ls-files '*_variants/state.json'` and take the exploration whose `variantIds` hold the ids the notes name. When `variantIds` already holds `mix`, this run revises the mix in place, and the notes may name `mix` itself as a source.

Done when the tree is clean and you hold one exploration entry.

### 2. Write the mix list

Turn the notes into a **mix list**, one item per part. Each item names the part, the variant id it comes from, and any change the user asked for. A note that leaves a choice to you, such as "not sure between A and B", becomes a **decide** item naming both candidates and what the user wants the choice to fit with. A note that approves your steals becomes one item per steal from step 7. In a fresh session with no step 7 to draw on, ask the user which steals they mean.

```
- Close button: from impeccable-2.
- Flow after the amount: from impeccable-2, amount then category then account. Change: no default account.
- Account list: from impeccable-1. Change: show the bank icons from taste-2.
- Category field: decide between impeccable-1 and emil-2. It sits above the impeccable-1 numpad, which has no background.
```

Then choose the design skill for the build. Take the skill whose variants supply the most items, since the mix builds on their structure, and break a tie toward the variant that supplies the screen's overall layout.

Done when every note maps to an item, every item names ids that are in `variantIds`, and you hold one skill key from the table in SKILL.md.

### 3. Build the mix

Launch one `worker` with the mix brief below, in the current workspace, since the mix lands in the checkout the app runs from.

Done when the worker reports back and its screenshot of the mix exists.

### 4. Check and commit

1. Run the typecheck. Send the mix's errors back to the worker with `send_agent_prompt` and wait for the fix.
2. Confirm that `index.<ext>` imports the mix and lists it last, and that `variantIds` in `state.json` ends with `mix`.
3. Make the one mix commit with `git add -A && git commit -m "explore: <slug> mix"`.

Done when the typecheck exits 0 and `git status --porcelain` prints nothing.

### 5. Hand over

Open the worker's final screenshot with `read`. Then give the user:

- how to open the mix, using the platform file's switching section,
- each decide item's choice and the worker's reason in one line,
- any item that did not fit, and why,
- the skill the build used,
- the lock command, `/skill:design-explore lock mix`, and that more notes revise the mix.

Done when the user has every part of that list.

## Mix brief

Fill every `<...>` before sending, with absolute paths. `<skill-dir>` is `~/.pi/agent/skills/design-explore`. `<platform-file>` is WEB.md, EXPO.md, or ASTRO.md, the one for this project. `<Name>` is the view's component name without `View`.

```
Build the `mix` variant of <target> in <repo-path>, with the <skill> design skill. A mix takes the parts named in the mix list below from existing variants and makes them one design, as if one designer drew the whole screen.

Mix list:
<the mix list>

Read first:
- <variants-dir>/brief.md. It holds all the design context. Take every answer from it, because the user is not available for questions.
- <skill-md-path>. Bring its taste and craft rules. Where it conflicts with this brief, this brief wins.
- <view-file>, for the props contract `<Name>ViewProps`.
- <variants-dir>/<variant-id>.<ext> and its `<variant-id>.*` helper files, for every variant the mix list names.
- The "Capturing a variant" and "Variants on this platform" sections of <skill-dir>/<platform-file>.

Steps:
1. Decide. For each decide item, capture both candidates as the platform file says, open the screenshots with read, and choose the one that sits better with the rest of the list. Save screenshots in /tmp/design-explore/<slug>/.
2. Build. Write `<variants-dir>/mix.<ext>` with a default-exported component whose props are `<Name>ViewProps`. When it already exists, revise it, keeping every part the list leaves alone. Helper parts go in the same file or in files named `mix.<part>.<ext>`. Port each part from its source variant, with the change its item asks. Then make the parts fit: one spacing scale, one type scale, one radius, and one motion style across the screen. Restyle a borrowed part where it clashes, and keep the quality the user named in each note, such as a numpad with no background.
3. Wire. When <variants-dir>/index.<ext> does not list the mix yet, import it and add it last, the way the other variants are listed, and add `mix` to the end of `variantIds` for <slug> in <state-json>.
4. Look. Capture the mix and open the screenshot with read. Compare each part with its source screenshot, fix every clash, overflow, and misalignment in one batch, then capture and look once more.

Rules:
- Keep the brand lock. Use only the colors, fonts, logo, and tokens in brief.md.
- Stay look-only. Take the props as they are, fetch no data, keep only local UI state, import only dependencies already in package.json, and use only assets already in the project.
- Write only the `mix` files, index.<ext>, and state.json. Every other variant stays as it is.

Done when every item is in the mix or reported as not fitting, `<typecheck-command>` shows no errors in your files, index.<ext> and state.json list `mix` last, and you opened the final screenshot.

Report: for each item, where it landed or why it did not fit, each decide item's choice with a one-line reason, and the path of the final screenshot.
```

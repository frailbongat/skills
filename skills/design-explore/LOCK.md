# Lock

Lock keeps one variant as the view, deletes the exploration, and makes one cleanup commit on the current branch. It usually runs in a fresh session, so every fact comes from `state.json`. The words owner, view, variant, look-only, and shared folder mean what [SKILL.md](SKILL.md) says. Launch subagents as the `paseo-delegation` skill says.

## Steps

### 1. Find the exploration

Run `git status --porcelain`. If it prints anything, ask the user how to handle those changes and wait, so the lock commit holds only the cleanup.

Find the file with `git ls-files '*_variants/state.json'`. Take the exploration whose `variantIds` holds `<variant-id>`, and when several do, ask the user which. Its explore commit is the first commit after its `parentCommit`, printed by `git rev-list --reverse --ancestry-path <parentCommit>..HEAD | head -n 1`. When that prints nothing, because a rebase rewrote the history, find it by message with `git log -1 --format=%H --grep='^explore: <slug> variants$'`, and use `<explore-commit>^` in place of every `parentCommit`.

Done when the tree is clean and you hold one exploration entry and its explore commit sha.

### 2. Promote and clean up

Launch one `worker` with the lock brief below.

Done when the worker reports all three checks passing and your own run of its grep agrees.

### 3. Review and commit

Launch a fresh `reviewer` with the review brief below. Send its findings to the lock worker with `send_agent_prompt`. Then make the one lock commit with `git add -A && git commit -m "explore: lock <slug> as <variant-id>"`.

Done when every finding is fixed or the user accepted it, and `git status --porcelain` prints nothing.

### 4. Hand over

Tell the user the lock commit's sha, and how to read any losing variant, the mix included, from the commit before it: `git show <lock-commit>^:<variantsDir>/<variant-id>.tsx`.

Done when the user has that command with the real sha and path filled in.

## Lock brief

Fill every `<...>` before sending, with absolute paths.

```
Lock the design exploration <slug> in <repo-path>. The winner is <variant-id>. Steal notes: <notes, or "none">.

Exploration entry from state.json:
<the entry JSON>
Shared folder: <sharedDir>. Root layout: <rootLayout.file>, with the lines <rootLayout.lines>, added on top of <rootLayout.parentCommit>. Other explorations still in state.json: <their targets, or "none">.

1. Promote. Rewrite <viewFile> to render the UI from <variantsDir>/<variant-id>.tsx and any `<variant-id>.*` helper files it imports. The view's export name and `<Name>ViewProps` stay as they are. When the winner is `current`, the view stays as it is.
2. Steal. For each steal note, read the variant file it names and port that piece into the view. Report a note you cannot map to code instead of guessing.
3. Unwire. Make <ownerFile> render `<Name>View` where it renders `<Name>Explore`, importing it from the view file. Delete <variantsDir>. Remove this exploration from state.json. When no exploration is left, delete <sharedDir>, remove the root layout lines, and run `git diff <rootLayout.parentCommit> -- <rootLayout.file>`. Undo any exploration change it still shows, such as a fragment added around the navigator.
4. Check. Run the typecheck and, when package.json has one, the lint script. From the repo root, run `rg -n '\b_variants\b|ExploreSwitcher|useExploreVariant'`.

Leave the changes uncommitted.

Done when the typecheck and lint pass, the grep prints nothing, and, when no exploration is left, the root layout diff is empty. While other explorations remain, the grep may print only lines inside their files, the shared folder, and the root layout lines.

Report: what the view took from the winner, where each steal note landed, and the output of all three checks.
```

## Review brief

```
Review the uncommitted lock of design exploration <slug> in <repo-path>. Read `git status` and `git diff HEAD`. The winner is <variant-id>, and `git show HEAD:<variantsDir>/<variant-id>.tsx` prints it as it was. Steal notes: <notes, or "none">.

Check that:
- <viewFile> renders the winner's UI, and `<Name>ViewProps` is unchanged.
- Each steal note landed as asked.
- <ownerFile> renders `<Name>View` and keeps its data, hooks, and navigation.
- The promoted code is look-only: no new data fetching, no state beyond local UI state, no new dependency.
- No exploration file, import, or switcher line is left, apart from what other running explorations own.

Report findings most severe first, each with file and line.
```

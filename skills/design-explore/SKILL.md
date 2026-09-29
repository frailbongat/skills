---
name: design-explore
description: Build design variants of one screen or component in the running app, then lock in the winner.
disable-model-invocation: true
---

# Design explore

An **exploration** builds several **variants** of one **target**, a screen or a component, and renders them in the target's real spot in the app. A dev-only switcher flips between them. Production builds made before lock bundle every variant but render only the first. Mix mode builds one more variant, `mix`, from parts of the others. Lock mode later keeps the winner and deletes the rest. Every mode works on the branch that is checked out, and each makes one commit.

The first argument picks the mode:

- `/design-explore <target and options, in plain English>` explores. Follow the steps below. The target is any screen or component, for example `the account screen` or `the pricing card on the home page`. Read two options from the user's words: **per-skill**, 1 or 2 variants per skill (a total sets it as total divided by the number of skills, so "4 variants" with all four skills means 1), and **skills**, which design skills run ("skip awwwards" drops it). When the words leave the count unclear, such as a total that is not 1 or 2 times the number of skills, ask before step 2.
- `/design-explore mix <notes>` mixes, and so do notes the user sends after step 7 on what they like in each variant. Read [MIX.md](MIX.md) and follow it instead.
- `/design-explore lock <variant-id> [steal notes]` locks, for example `lock taste-2 use the header motion from emil-1`. Read [LOCK.md](LOCK.md) and follow it instead.

## Words

- **Target.** The one screen or component. Its kebab-case slug names the exploration in the switcher and in commit messages.
- **Owner.** The file that renders the target. It keeps the data, hooks, and navigation.
- **View.** Pure UI in its own file, props in and UI out. Its exported props type, `<Name>ViewProps`, is the **props contract** every variant implements. The owner and view stay split after lock.
- **Incumbent.** The view as it looks today, listed first in the switcher as `current`. A new target has none.
- **Variant.** One design of the view, with id `<skill>-1` or `<skill>-2`. `-1` is **safe**, close to the current screens. `-2` is **bold**, pushing layout, hierarchy, and motion further. With per-skill 1, each skill builds only its `-1`. The **mix** is the variant with id `mix`, built from the parts of other variants that the user's notes name.
- **Brand lock.** Every variant keeps the project's colors, fonts, logo, and tokens. Layout, hierarchy, spacing, and motion are free.
- **Look-only.** A variant takes the props contract as it is, fetches no data, holds only local UI state, and adds no dependency.
- **`<ext>`.** The file extension of the view, every variant, and the index file: `astro` on Astro, `tsx` everywhere else.
- **`_variants/`.** The one folder name for every exploration file, so cleanup greps for one name. The **shared folder** at the source root holds the switcher and `state.json`. Each target has its own `_variants/` beside its view.

The design skills, keyed by the names the user may say. The default runs all four with per-skill 2, 8 variants.

| Key | SKILL.md |
| --- | --- |
| `impeccable` | `~/.claude/skills/impeccable/SKILL.md` |
| `taste` | `~/.agents/skills/design-taste-frontend/SKILL.md` |
| `emil` | `~/.agents/skills/emil-design-eng/SKILL.md` |
| `awwwards` | `~/.agents/skills/build-awwwards-quality-sites/SKILL.md` |

## Explore

Platform details live in [WEB.md](WEB.md) for Next.js App Router and plain React on Vite, in [EXPO.md](EXPO.md) for Expo Router, and in [ASTRO.md](ASTRO.md) for Astro. Read the one for this project as soon as step 2 names the platform. The subagent briefs are in [BRIEFS.md](BRIEFS.md). Launch subagents as the `paseo-delegation` skill says.

### 1. Clean tree

Run `git status --porcelain`. If it prints anything, ask the user how to handle those changes and wait, so the explore commit in step 6 holds only exploration files.

Done when `git status --porcelain` prints nothing.

### 2. Scout

Launch one `scout` with the scout brief. It detects the platform, finds the target, and writes `brief.md` into the target's `_variants/` folder. An unsupported platform ends the run; tell the user what the scout found.

Done when `brief.md` has all five sections the scout brief asks for, and the scout's report names the platform, owner file, view file, target `_variants/` folder, source root, root layout file, and typecheck command.

### 3. Split owner and view

For an existing target, move its JSX into the view file the scout named. Everything the JSX reads or calls comes in through `<Name>ViewProps`. The owner keeps its data, hooks, and navigation, and renders `<Name>View`.

For a new target, create the owner, and write the view file holding only the exported `<Name>ViewProps`, built from what the target must show and do. The variants supply the UI.

Done when the view file imports no data fetching, store, or navigation code, its props type is exported, and the typecheck passes.

### 4. Wire the switcher

1. When the shared folder does not exist yet, copy the templates into it and mount `<ExploreSwitcher />` in the root layout, both as the platform file says.
2. Write `index.<ext>` in the target's `_variants/` folder. `current` comes first when there is an incumbent. Step 6 adds the variants. Import the switcher, here and in the root layout, through the project's alias for the source root, or a relative path when it has none. On React platforms the file looks like this, and ASTRO.md shows the Astro form.

   ```tsx
   "use client"; // web only

   import { useExploreVariant } from "@/_variants/switcher";
   import { ProfileView, type ProfileViewProps } from "../ProfileView";

   const variants = {
     current: ProfileView,
   };

   export function ProfileExplore(props: ProfileViewProps) {
     const Variant = useExploreVariant("profile", variants);
     return <Variant {...props} />;
   }
   ```

3. Make the owner render `<Name>Explore` where it rendered `<Name>View`.
4. Create `state.json` in the shared folder, or add this exploration to it. Every path is relative to the repo root. `parentCommit` is the output of `git rev-parse HEAD`, the commit the explore commit will sit on. `rootLayout` records the lines the first exploration added and that exploration's `parentCommit`.

   ```json
   {
     "platform": "expo",
     "sharedDir": "src/_variants",
     "rootLayout": {
       "file": "src/app/_layout.tsx",
       "lines": ["import { ExploreSwitcher } from \"@/_variants/switcher\";", "<ExploreSwitcher />"],
       "parentCommit": "3f9c2ab"
     },
     "explorations": [
       {
         "target": "profile",
         "parentCommit": "3f9c2ab",
         "ownerFile": "src/app/(tabs)/profile.tsx",
         "viewFile": "src/features/profile/ProfileView.tsx",
         "variantsDir": "src/features/profile/_variants",
         "variantIds": ["current", "impeccable-1", "impeccable-2", "taste-1", "taste-2", "emil-1", "emil-2", "awwwards-1", "awwwards-2"]
       }
     ]
   }
   ```

Done when `state.json` holds this exploration with every field filled, and the root layout renders exactly one `<ExploreSwitcher />`.

### 5. Build the variants

Launch one `worker` per chosen skill, all at once, each with the variant brief. Launch them in the current workspace, since the variants have to land in the checkout the app runs from and each worker writes only files named after its own variant ids.

Done when every worker has reported back and every planned variant file exists.

### 6. Check and commit

1. Import every finished variant into `index.<ext>` and add it after `current`, in the table's skill order. Bring `variantIds` in `state.json` up to date.
2. Run the typecheck. Fix wiring errors yourself. Send a variant's errors back to its worker with `send_agent_prompt` and wait for the fix.
3. Make the one explore commit on the current branch with `git add -A && git commit -m "explore: <slug> variants"`.

Done when the typecheck exits 0 and `git status --porcelain` prints nothing.

### 7. Pick and hand over

The user chooses the winner, and your **pick** is the recommendation they read first. Base it on the rendered UI, since code hides the spacing, hierarchy, and overflow a screenshot shows.

1. Screenshot `current` and every variant as the platform file's "Capturing a variant" section says. Save the files in `/tmp/design-explore/<slug>/`, outside the repo, and open every one with `read`. When the app will not run, ask the user to start it and wait.
2. Read each variant's motion code, since a screenshot shows no motion.
3. Pick the variant that best does what the `## Target` section of `brief.md` asks, inside the brand lock. Then list the **steals**, specific parts of other variants worth moving into the pick, such as a header, an empty state, or an entrance animation, each named with its variant id.
4. Tell the user how to switch, using the platform file's section for it. Then give the pick with a reason of two lines or fewer, the steals, and the lock command with both filled in, such as `/design-explore lock taste-2 use the header motion from emil-1`. Add that they can reply with what they like in each variant to get a mix.

Done when you have opened a screenshot of every id in `variantIds`, `git status --porcelain` prints nothing, and the user has the switch instructions, the pick, the steals, and the filled lock command.

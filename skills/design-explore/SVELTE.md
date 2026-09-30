# SvelteKit

SvelteKit apps on Svelte 5, where the view and every variant are `.svelte` components in runes mode, so `<ext>` is `svelte`. The typecheck is `svelte-check`, usually the `check` script in the app's package.json. For Svelte 4, or SvelteKit before 2.12, which lacks `$app/state`, stop and ask the user.

Run `npx @sveltejs/mcp svelte-autofixer <file> --svelte-version 5` on every `.svelte` file you write or edit in steps 3 and 4, and fix every issue it lists before the typecheck. Its suggestions are optional.

## Where files go

- The source root is the SvelteKit app's `src/`. In a monorepo, the app is the workspace package that depends on `@sveltejs/kit` and renders the target, such as `apps/web/`. Every path in `state.json` stays relative to the repo root, so there it starts with the package folder, such as `apps/web/src/lib/_variants`.
- The shared folder is `src/lib/_variants/`, so every file imports it through `$lib/_variants/`, the alias every SvelteKit app has.
- For a component `Foo.svelte`, `Foo.svelte` stays the owner. The view is `FooView.svelte` beside it, and `_variants/` sits beside both. When the project names component files in kebab-case, such as `foo.svelte`, the view is `foo-view.svelte`. The props type is `FooViewProps` either way.
- For a route, `src/routes/<route>/+page.svelte` stays the owner, or `+layout.svelte` when the target is layout chrome. It keeps its `data` prop, its load files, and its navigation. The view goes outside `src/routes/`, in the folder where the project keeps that feature's or section's components, such as `src/lib/components/<slug>/<Name>View.svelte`, with `_variants/` beside it.
- A `+layout.svelte` owner whose view renders the page passes its `children` snippet to `<Name>Explore`, such as `<ShellExplore {children} />`. Each switch then mounts the page again, and the page loses its local state, such as form input. When the target sits beside the page, such as a sidebar, the owner keeps `{@render children()}` and the page stays mounted.
- The root layout is `src/routes/+layout.svelte`, which wraps every page.

## Props and snippets

- The view exports its props type from `<script module lang="ts">` and types its own `$props()` with it:

  ```svelte
  <script module lang="ts">
  	import type { Snippet } from 'svelte';

  	export type ProfileViewProps = {
  		name: string;
  		onSave: () => void;
  		actions?: Snippet<[{ disabled: boolean }]>;
  	};
  </script>

  <script lang="ts">
  	const { name, onSave, actions }: ProfileViewProps = $props();
  </script>
  ```

  Other files import it with `import type { ProfileViewProps } from './ProfileView.svelte';`.
- Snippets are part of the props contract. Every snippet the owner passes, `children` included, is a `Snippet` prop in `<Name>ViewProps` under the name the component used before the split, and the view renders it with `{@render actions?.({ disabled })}`. When the owner passes `slot="..."` content or listens with `on:save`, turn it into a `{#snippet}` or a callback prop such as `onSave` in the same edit.
- A prop the owner binds with `bind:`, such as `bind:open`, stays `$bindable()` in the view and in every variant, with the fallback it had before the split, such as `open = $bindable(false)`. The owner binds it on `<Name>Explore`, and the index file forwards the binding as "The index file" shows.

## Switcher

- Copy `templates/explore.svelte.ts` and `templates/ExploreSwitcher.svelte` into `<source-root>/lib/_variants/`.
- Run the project's lint and formatter on the shared folder, with the commands the scout named, and fix what they report. The templates pass the recommended rules of `eslint-plugin-svelte`, and the project's own rules and format may add more.
- In the root layout, render `<ExploreSwitcher />` right after `{@render children()}`. The `rootLayout.lines` in `state.json` are `import ExploreSwitcher from '$lib/_variants/ExploreSwitcher.svelte';` and `<ExploreSwitcher />`, in the project's quote style.

## The index file

This is the Svelte form of the React `index.tsx` that SKILL.md step 4 shows. `useExploreVariant` returns a function for `$derived.by`, and the one spread passes every prop to the variant, snippets included.

```svelte
<script lang="ts">
	import { useExploreVariant } from '$lib/_variants/explore.svelte';
	import ProfileView, { type ProfileViewProps } from '../ProfileView.svelte';

	const props: ProfileViewProps = $props();
	const Variant = $derived.by(
		useExploreVariant('profile', {
			current: ProfileView
		})
	);
</script>

<Variant {...props} />
```

Adding a variant in step 6 means one import, such as `import Taste1 from './taste-1.svelte';`, and one key, `'taste-1': Taste1`. The owner imports this file as `<Name>Explore` and renders it with the props and snippets it gave the view:

```svelte
<script lang="ts">
	import ProfileExplore from './_variants/index.svelte';
</script>

<ProfileExplore name={user.name} onSave={save}>
	{#snippet actions({ disabled })}
		<Button {disabled}>Share</Button>
	{/snippet}
</ProfileExplore>
```

A spread passes values and drops bindings. When the owner binds a prop, such as `<ProfileExplore bind:open ...>`, the index file takes that prop out of the spread and binds it on the variant, with the view's fallback:

```svelte
<script lang="ts">
	// imports and `Variant` as above
	let { open = $bindable(false), ...props }: ProfileViewProps = $props();
</script>

<Variant bind:open {...props} />
```

In dev, `useExploreVariant` reads the pick from `page.url` first, then from the picks made in this browser tab. The server sees only `page.url`, so the dev server renders the picked variant on the first request and hydration keeps it. A production build renders only the first key and never reads the query string, so prerendered pages still build.

## Telling the user how to switch

Run the dev server as usual, open the page, then click a variant in the switcher bar. The bar sits at the bottom center, or runs down the bottom right when the window is too narrow for a row. `[` and `]` step to the previous and next variant. The URL carries the pick as `?variant=taste-2`, so a link or a second tab opens the same variant. A link click inside the app drops `?variant=` from the URL, and the pick holds until the tab reloads. Click the variant again to put it back in the URL. A pick swaps the variant in place, and state the owner holds, such as form input, carries over. With two explorations on one page, each gets its own `?variant=<slug>:<variant-id>`. Production builds show `current`, or the first variant for a new target.

## Capturing a variant

Start the dev server in the background when none is running, from the app's package in a monorepo, such as `pnpm --filter <package> dev`. Open the page that renders the target with `?variant=<slug>:<variant-id>`, and screenshot it at a desktop and a mobile width. Use the harness's browser tool when it has one, or `npx playwright screenshot --viewport-size "1440, 900" --wait-for-timeout 1500 --full-page <url> <file>` and again with `"390, 844"`. The wait lets entrance motion settle before the capture. When the target sits behind a login, the Playwright CLI captures the login page, so use the harness's browser tool with a signed-in session, or ask the user to sign in once in that browser.

## Variants on this platform

- A variant is a `.svelte` component in runes mode. It types `$props()` with `<Name>ViewProps`, imported as a type from the view, declares every bound prop with `$bindable()` and the view's fallback, and renders the view's snippets by the same names.
- Only the picked variant mounts, so styles go in the component's scoped `<style>` or the project's utility classes.
- Motion uses `svelte/transition`, `svelte/animate`, `svelte/motion`, CSS, or the animation libraries already in package.json. It honors reduced motion through `prefersReducedMotion` from `svelte/motion` or the `prefers-reduced-motion` media query.
- After writing each file, run `npx @sveltejs/mcp svelte-autofixer <file> --svelte-version 5` on it and fix every issue it lists. Its suggestions are optional.

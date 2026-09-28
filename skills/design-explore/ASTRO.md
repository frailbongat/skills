# Astro

Astro sites, where the view and every variant are `.astro` components, so `<ext>` is `astro`. The typecheck is `astro check`, usually the `check` script in package.json.

## Where files go

- The source root is `src/`. The shared folder is `src/_variants/`.
- For a component `Foo.astro`, `Foo.astro` stays the owner. The view is `FooView.astro` beside it, and `_variants/` sits beside both.
- For a page, `src/pages/<route>.astro` stays the owner. It keeps its layout wrapper, its data, and any `getStaticPaths`, and the view is the page body inside the layout. Astro makes every `.astro` file under `src/pages/` a route unless its name or a parent folder starts with `_`, so the view goes outside `src/pages/`. Give it a folder named after the slug, inside the folder where the project keeps its section components, such as `src/components/about/AboutView.astro`, with `_variants/` beside it.
- The root layout is the layout component that renders `<body>` for the target's page, such as `src/layouts/BaseLayout.astro`.

## Props and slots

- The view exports its props type from its frontmatter and uses it as its own props:

  ```astro
  ---
  export type HeroViewProps = { title: string; subtext?: string };
  type Props = HeroViewProps;
  ---
  ```

  Other files import it with `import type { HeroViewProps } from "./HeroView.astro";`.
- Slots are part of the props contract. The view reads the same slots the component read before the split, by the same names. Every component between the page and the variant forwards each slot with `<slot name="actions" slot="actions" />`, and `<slot />` for the default slot.

## Switcher

- Copy `templates/Explore.astro` and `templates/ExploreSwitcher.astro` into `<source-root>/_variants/`.
- In the root layout, render `<ExploreSwitcher />` as the last child of `<body>`. It lists the explorations it finds on the page when it runs, so it comes after all of them. The `rootLayout.lines` in `state.json` are `import ExploreSwitcher from "@/_variants/ExploreSwitcher.astro";` and `<ExploreSwitcher />`.

## The index file

This is the Astro form of the React `index.tsx` that SKILL.md step 4 shows. `index.astro` passes each variant to `Explore` in a slot named after its id, with the same props and forwarded slots. `ids` lists the same ids in the same order, and the first one is the default.

```astro
---
import Explore from "@/_variants/Explore.astro";
import HeroView, { type HeroViewProps } from "../HeroView.astro";
import Taste1 from "./taste-1.astro";

type Props = HeroViewProps;
---

<Explore target="hero" ids={["current", "taste-1"]}>
  <HeroView slot="current" {...Astro.props}><slot name="actions" slot="actions" /></HeroView>
  <Taste1 slot="taste-1" {...Astro.props}><slot name="actions" slot="actions" /></Taste1>
</Explore>
```

Adding a variant in step 6 means one import, one id in `ids`, and one slotted line. The owner imports this file as `<Name>Explore` and renders it with the props and slots it gave the view:

```astro
<HeroExplore {...Astro.props}><slot name="actions" slot="actions" /></HeroExplore>
```

Astro drops the query string on prerendered pages, so the dev server renders every variant and an inline script in `Explore` hides all but the pick before the page paints. A production build renders only the first slot, so no other variant's markup, styles, or scripts ship.

## Telling the user how to switch

Run the dev server as usual, open the page, then use the pill at the bottom right to pick a variant. A pick reloads the page with `?variant=taste-2` in the URL, so the variant's entrance motion plays as on a first visit, and a link or a second tab opens the same variant. With two explorations on one page, each gets its own `?variant=<slug>:<variant-id>`. A page on a layout without the switcher still takes the `?variant=` param. Production builds show `current`, or the first variant for a new target.

## Capturing a variant

Start the dev server in the background when none is running. Open the page that renders the target with `?variant=<slug>:<variant-id>`, and screenshot it at a desktop and a mobile width. Use the harness's browser tool when it has one, or `npx playwright screenshot --viewport-size "1440, 900" --wait-for-timeout 1500 --full-page <url> <file>` and again with `"390, 844"`. The wait lets entrance motion settle before the capture.

## Variants on this platform

- A variant is an `.astro` component whose `type Props` is `<Name>ViewProps`, imported as a type from the view. It reads the view's slots by the same names.
- In dev, every variant sits on the page at once and all but the pick are hidden. So each variant keeps to its own markup:
  - Styles go in the component's scoped `<style>`. When the project writes `is:global` styles, every class the variant adds starts with its variant id, such as `.taste-2_hero`.
  - Every `id` attribute is unique to the variant. Use the project's id helper when it has one, or start the id with the variant id.
  - A `<script>` runs on every load, also while its variant is hidden. It selects only elements marked with the variant id, such as `[data-taste-2-hero]`, and returns when it finds none.
- Motion uses CSS or the animation libraries already in package.json, and honors `prefers-reduced-motion`.

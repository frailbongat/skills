# Web

Next.js App Router, or plain React on Vite. For anything else, such as the Next.js Pages Router, stop and ask the user.

## Where files go

- The source root is `src/` when it exists, else the project root. The shared folder is `_variants/` inside it.
- For a component `Foo.tsx`, `Foo.tsx` stays the owner. The view is `FooView.tsx` beside it, and `_variants/` sits beside both.
- For a Next.js page, `app/<route>/page.tsx` stays the owner. The view goes beside it, or in the folder the project already uses for that route's components. Variants go in `app/<route>/_variants/`, since Next.js keeps `_`-prefixed folders out of routing.
- A Vite screen is a component and follows the component rule.

## Switcher

- Copy `templates/switcher-web.tsx` to `<source-root>/_variants/switcher.tsx`. On Vite, replace its `IS_DEV` line with `const IS_DEV = import.meta.env.DEV;`.
- On Next.js, render `<ExploreSwitcher />` in `app/layout.tsx`, inside `<body>`, right after `{children}`.
- On Vite, render `<ExploreSwitcher />` beside the app's root element in the file that calls `createRoot(...).render(...)`, usually `src/main.tsx`.

## Next.js server and client line

The target's `_variants/index.tsx` starts with `"use client"`, so every variant runs as a client component, and a server component owner passes the view's props across the server and client line. Ask the user before step 4 when the view takes props React cannot serialize, such as a function that is not a server function, or when the incumbent view is an async server component.

## Telling the user how to switch

Run the dev server as usual, open the screen, then use the pill at the bottom right to pick a variant. The URL carries the pick as `?variant=taste-2`, so a link or a second tab opens the same variant. With two explorations running, each gets its own `?variant=<slug>:<variant-id>`. Production builds show `current`, or the first variant for a new target.

## Capturing a variant

Start the dev server in the background when none is running. Open the page that renders the target with `?variant=<slug>:<variant-id>`, and screenshot it at a desktop and a mobile width. Use the harness's browser tool when it has one, or `npx playwright screenshot --viewport-size "1440, 900" --wait-for-timeout 1500 --full-page <url> <file>` and again with `"390, 844"`. The wait lets entrance motion settle before the capture.

## Variants on this platform

On Next.js a variant is a client component. It can use state and effects, and it is never `async`.

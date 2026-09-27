# Expo

Expo apps on Expo Router.

## Where files go

- The source root is `src/` when it exists, else the project root. The shared folder is `_variants/` inside it, outside `app/`.
- For a component `Foo.tsx`, `Foo.tsx` stays the owner. The view is `FooView.tsx` beside it, and `_variants/` sits beside both.
- For a screen, the route file under `app/` stays the owner. Expo Router makes every code file under `app/` a route, and a `_` prefix does not exempt a folder, so the view moves out. It goes into the project's existing screens or features folder, such as `src/features/<slug>/<Name>View.tsx`, with `_variants/` beside it. When the project has neither folder, ask the user where the view goes.

## Switcher

- Copy `templates/switcher-expo.tsx` to `<source-root>/_variants/switcher.tsx`.
- Copy one storage file to `<source-root>/_variants/storage.ts`. Use `templates/storage-async.ts` when package.json already lists `@react-native-async-storage/async-storage`, and `templates/storage-memory.ts` otherwise. The project's dependencies stay exactly as they are.
- In the root layout, `app/_layout.tsx`, render `<ExploreSwitcher />` as the last child of the outermost element it returns. When the layout returns a bare navigator, wrap the two in a fragment.

## Telling the user how to switch

In a dev build, open the screen, then use the pill at the right edge above the tab bar. A tap opens a bottom sheet, and a tap on a variant picks it. The pick survives a reload when the project uses AsyncStorage, and resets to `current` otherwise. A screen presented as a native modal covers the pill, so close it to switch. Release builds show `current`, or the first variant for a new target.

## Variants on this platform

- Motion runs on Reanimated when the project depends on `react-native-reanimated`, and on React Native's `Animated` otherwise. Honor the reduce motion setting through Reanimated's `useReducedMotion` or `AccessibilityInfo.isReduceMotionEnabled()`.
- The `awwwards` variants keep that skill's bold, motion-led spirit and build it with Reanimated. GSAP, smooth-scroll libraries, and Three.js are web libraries and stay out of native code.

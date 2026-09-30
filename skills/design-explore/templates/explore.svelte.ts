// Dev-only design switcher state, copied in by the design-explore skill.
// `/design-explore lock` deletes this folder once no exploration is left.
//
// A pick lives in `?variant=`, read from `page.url`, so a link or a second tab
// opens the same variant, and the dev server renders the pick on the first
// request. A pick calls `goto` with `replaceState`, which updates `page.url`
// without a new history entry. The shallow `replaceState` from
// `$app/navigation` leaves `page.url` as it was, and `history.replaceState`
// fights the SvelteKit router.
//
// A link click drops `?variant=`, so the browser also keeps each pick in
// `remembered`, and the URL wins over it. Only the browser writes `remembered`
// and registers explorations, so server renders never write the module state
// that requests share, and hydration sees the same picks the server did.

/* eslint svelte/no-navigation-without-resolve: ["error", { ignoreGoto: true }] -- `goto` gets
   `page.url` with a new query, and `page.url` already holds the base path. */

import { browser, dev } from '$app/environment';
import { goto } from '$app/navigation';
import { page } from '$app/state';
import { untrack } from 'svelte';

const PARAM = 'variant';
// `?variant=taste-2` applies to every exploration that has a `taste-2`.
// `?variant=profile-header:taste-2` applies to one exploration only.
const ANY_TARGET = '*';

export type Exploration = {
	readonly target: string;
	readonly variantIds: readonly string[];
};

// `copies` counts the mounted copies of a target, since the same target can
// render twice on a page. It leaves the bar when its last copy unmounts.
let mounted = $state.raw<readonly (Exploration & { readonly copies: number })[]>([]);
// The picks made in this browser tab, keyed by target.
let remembered = $state.raw<Readonly<Record<string, string>>>({});

/** The explorations rendered on the current page, in mount order. */
export function explorations(): readonly Exploration[] {
	return mounted;
}

function readPicks(url: URL): Record<string, string> {
	const picks: Record<string, string> = {};
	for (const value of url.searchParams.getAll(PARAM)) {
		const colon = value.indexOf(':');
		if (colon === -1) picks[ANY_TARGET] = value;
		else picks[value.slice(0, colon)] = value.slice(colon + 1);
	}
	return picks;
}

function pickFor(picks: Record<string, string>, exploration: Exploration): string | undefined {
	const wanted = picks[exploration.target] ?? picks[ANY_TARGET];
	return wanted !== undefined && exploration.variantIds.includes(wanted) ? wanted : undefined;
}

/** The variant id picked for `exploration` by the URL, then this tab, or its first id. */
export function chosenVariant(exploration: Exploration): string {
	return (
		pickFor(readPicks(page.url), exploration) ??
		pickFor(remembered, exploration) ??
		exploration.variantIds[0] ??
		''
	);
}

function hrefWithPicks(values: readonly string[]): string {
	const params = [...page.url.searchParams].filter(([key]) => key !== PARAM);
	for (const value of values) params.push([PARAM, value]);
	const query = params
		.map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
		.join('&');
	return `${page.url.pathname}${query ? `?${query}` : ''}${page.url.hash}`;
}

export function pickVariant(target: string, variantId: string): void {
	if (!browser) return;
	remembered = { ...remembered, [target]: variantId };
	const scoped = mounted.length > 1;
	const values: string[] = [];
	for (const exploration of mounted) {
		const chosen = exploration.target === target ? variantId : chosenVariant(exploration);
		if (chosen === exploration.variantIds[0]) continue;
		values.push(scoped ? `${exploration.target}:${chosen}` : chosen);
	}
	void goto(hrefWithPicks(values), { replaceState: true, noScroll: true, keepFocus: true });
}

/** Steps `target`, or the first exploration, to the previous or next variant. */
export function stepVariant(target: string | undefined, delta: number): void {
	const exploration = mounted.find((candidate) => candidate.target === target) ?? mounted[0];
	if (!exploration) return;
	const ids = exploration.variantIds;
	const index = ids.indexOf(chosenVariant(exploration));
	const next = ids[(index + delta + ids.length) % ids.length];
	if (next !== undefined) pickVariant(exploration.target, next);
}

function register(target: string, variantIds: readonly string[]): () => void {
	const copies = (mounted.find((exploration) => exploration.target === target)?.copies ?? 0) + 1;
	const entry = { target, variantIds, copies };
	mounted =
		copies > 1
			? mounted.map((exploration) => (exploration.target === target ? entry : exploration))
			: [...mounted, entry];
	return () => {
		mounted = mounted.flatMap((exploration) => {
			if (exploration.target !== target) return [exploration];
			return exploration.copies > 1 ? [{ ...exploration, copies: exploration.copies - 1 }] : [];
		});
	};
}

/**
 * Returns a function that gives the variant picked for `target`, for
 * `$derived.by`. Call it while a component initializes. The first key in
 * `variants` is the default, and the only one ever returned outside dev.
 */
export function useExploreVariant<Variant>(
	target: string,
	variants: Readonly<Record<string, Variant>>
): () => Variant {
	const variantIds = Object.keys(variants);
	const first = variantIds[0];
	if (first === undefined) {
		throw new Error(`useExploreVariant("${target}") needs at least one variant.`);
	}
	// Untracked, since `register` reads the state it writes.
	if (dev) $effect(() => untrack(() => register(target, variantIds)));
	return () => {
		const chosen = dev ? chosenVariant({ target, variantIds }) : first;
		return variants[chosen] ?? variants[first]!;
	};
}

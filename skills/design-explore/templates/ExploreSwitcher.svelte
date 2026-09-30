<!--
	Dev-only design switcher, copied in by the design-explore skill.
	`/design-explore lock` deletes this folder once no exploration is left.

	Every variant is a button in an always-open bar, so a switch is one click.
	The bar is a row at the bottom center when it fits the window, and a column
	at the bottom right when it does not. `[` and `]` step to the previous and
	next variant of the exploration clicked last, or the first one. Mount it once
	in the root layout. It renders nothing outside dev, and nothing on the server,
	since explorations register only in the browser.
-->
<script lang="ts">
	import { dev } from '$app/environment';
	import { chosenVariant, explorations, pickVariant, stepVariant } from './explore.svelte';

	// Gap between the bar and the window edge, in pixels.
	const EDGE = 16;
	// The bar uses neutral grays so it never reads as part of the design under
	// review. Inline styles beat any global stylesheet the app loads.
	const FONT = 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif';
	const ROOT = `position:fixed;bottom:${EDGE}px;z-index:2147483647;display:flex;flex-direction:column;gap:2px;padding:4px;border-radius:12px;background:#171717;box-shadow:0 8px 30px rgba(0,0,0,.35)`;
	const LABEL = `padding:4px 8px;font:600 11px/1.3 ${FONT};letter-spacing:.04em;text-transform:uppercase;white-space:nowrap`;
	const OPTION = `padding:6px 10px;border:0;border-radius:8px;font:500 13px/1.3 ${FONT};text-align:left;white-space:nowrap;cursor:pointer`;
	const styles = {
		rootRow: `${ROOT};left:50%;transform:translateX(-50%);width:max-content`,
		rootColumn: `${ROOT};right:${EDGE}px;max-height:calc(100vh - ${2 * EDGE}px);overflow-y:auto`,
		groupRow: 'display:flex;align-items:center;gap:2px',
		groupColumn: 'display:flex;flex-direction:column;gap:2px',
		label: `${LABEL};color:#737373`,
		labelKeyed: `${LABEL};color:#a3a3a3`,
		option: `${OPTION};background:transparent;color:#d4d4d4`,
		optionActive: `${OPTION};background:#404040;color:#ffffff`
	};

	let activeTarget = $state<string>();
	let layout = $state<'row' | 'column'>('row');
	let root = $state<HTMLDivElement>();
	let rowWidth = { key: '', width: 0 };

	const current = $derived(explorations());
	const contentKey = $derived(
		current
			.map((exploration) => `${exploration.target}:${exploration.variantIds.join(',')}`)
			.join('|')
	);
	const row = $derived(layout === 'row');
	const keyed = $derived(activeTarget ?? current[0]?.target);

	// The row's width is measured while it is a row. The bar turns into a column
	// when that width is more than the window has room for, and back when it fits.
	function fit(): void {
		if (!root) return;
		if (layout === 'row') rowWidth = { key: contentKey, width: root.offsetWidth };
		const measured = rowWidth.key === contentKey;
		const fits = rowWidth.width <= window.innerWidth - 2 * EDGE;
		layout = !measured || fits ? 'row' : 'column';
	}

	$effect(fit);

	function isTyping(element: EventTarget | null): boolean {
		if (!(element instanceof HTMLElement)) return false;
		return element.isContentEditable || element.matches('input, textarea, select');
	}

	function onKeyDown(event: KeyboardEvent): void {
		if (!dev || current.length === 0) return;
		if (event.key !== '[' && event.key !== ']') return;
		if (event.repeat || event.metaKey || event.ctrlKey || event.altKey) return;
		if (event.isComposing || isTyping(event.target)) return;
		event.preventDefault();
		stepVariant(activeTarget, event.key === ']' ? 1 : -1);
	}
</script>

<svelte:window onkeydown={onKeyDown} onresize={fit} />

{#if dev && current.length > 0}
	<div
		bind:this={root}
		role="toolbar"
		aria-label="Design variants"
		aria-orientation={row ? 'horizontal' : 'vertical'}
		title="Press [ or ] to switch variants"
		style={row ? styles.rootRow : styles.rootColumn}
	>
		{#each current as exploration (exploration.target)}
			{@const chosen = chosenVariant(exploration)}
			<div
				role="group"
				aria-label={exploration.target}
				style={row ? styles.groupRow : styles.groupColumn}
			>
				<span style={exploration.target === keyed ? styles.labelKeyed : styles.label}>
					{exploration.target}
				</span>
				{#each exploration.variantIds as variantId (variantId)}
					<button
						type="button"
						aria-pressed={variantId === chosen}
						onclick={() => {
							activeTarget = exploration.target;
							pickVariant(exploration.target, variantId);
						}}
						style={variantId === chosen ? styles.optionActive : styles.option}
					>
						{variantId}
					</button>
				{/each}
			</div>
		{/each}
	</div>
{/if}

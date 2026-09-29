"use client";

// Dev-only design switcher, copied in by the design-explore skill.
// `/design-explore lock` deletes this folder once no exploration is left.
//
// The pick lives in memory and in `?variant=` so a link or a second tab opens
// the same variant. The URL is read from `window.location` and written with
// `history.replaceState(null, ...)`. Passing null, as the Next.js docs do, lets
// the App Router sync to the new URL, so its next render keeps the param.
// That keeps `useSearchParams` out, so no page needs a Suspense boundary for it.
//
// Every variant is a button in an always-open bar, so a switch is one click.
// The bar is a row at the bottom center when it fits the window, and a column
// at the bottom right when it does not. `[` and `]` step to the previous and
// next variant of the exploration clicked last, or the first one.

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore,
  type CSSProperties,
} from "react";

// Next.js. In a Vite project this line becomes: const IS_DEV = import.meta.env.DEV;
const IS_DEV = process.env.NODE_ENV !== "production";

const PARAM = "variant";
// `?variant=taste-2` applies to every exploration that has a `taste-2`.
// `?variant=profile-header:taste-2` applies to one exploration only.
const ANY_TARGET = "*";

type Exploration = {
  readonly target: string;
  readonly variantIds: readonly string[];
};

type Snapshot = {
  readonly explorations: readonly Exploration[];
  readonly picks: Readonly<Record<string, string>>;
};

const SERVER_SNAPSHOT: Snapshot = { explorations: [], picks: {} };
const listeners = new Set<() => void>();
const inBrowser = typeof window !== "undefined";
// React 18 warns when useLayoutEffect runs in a server render.
const useBrowserLayoutEffect = inBrowser ? useLayoutEffect : useEffect;

let snapshot: Snapshot =
  IS_DEV && inBrowser ? { explorations: [], picks: readPicksFromUrl() } : SERVER_SNAPSHOT;

if (IS_DEV && inBrowser) {
  window.addEventListener("popstate", () => {
    update({ ...snapshot, picks: readPicksFromUrl() });
  });
}

function readPicksFromUrl(): Record<string, string> {
  const picks: Record<string, string> = {};
  for (const value of new URLSearchParams(window.location.search).getAll(PARAM)) {
    const colon = value.indexOf(":");
    if (colon === -1) picks[ANY_TARGET] = value;
    else picks[value.slice(0, colon)] = value.slice(colon + 1);
  }
  return picks;
}

function writePicksToUrl(next: Snapshot): void {
  const params = new URLSearchParams(window.location.search);
  params.delete(PARAM);
  const scoped = next.explorations.length > 1;
  for (const exploration of next.explorations) {
    const chosen = resolveVariant(next, exploration);
    if (chosen === exploration.variantIds[0]) continue;
    params.append(PARAM, scoped ? `${exploration.target}:${chosen}` : chosen);
  }
  const query = params.toString();
  const url = `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash}`;
  window.history.replaceState(null, "", url);
}

function resolveVariant(current: Snapshot, exploration: Exploration): string {
  const wanted = current.picks[exploration.target] ?? current.picks[ANY_TARGET];
  if (wanted !== undefined && exploration.variantIds.includes(wanted)) return wanted;
  return exploration.variantIds[0] ?? "";
}

function update(next: Snapshot): void {
  snapshot = next;
  for (const listener of listeners) listener();
}

function register(target: string, variantIds: readonly string[]): void {
  const existing = snapshot.explorations.find((exploration) => exploration.target === target);
  if (existing && existing.variantIds.join("\n") === variantIds.join("\n")) return;
  const entry: Exploration = { target, variantIds };
  const explorations = existing
    ? snapshot.explorations.map((exploration) => (exploration.target === target ? entry : exploration))
    : [...snapshot.explorations, entry];
  update({ ...snapshot, explorations });
}

function pick(target: string, variantId: string): void {
  const next: Snapshot = { ...snapshot, picks: { ...snapshot.picks, [target]: variantId } };
  writePicksToUrl(next);
  update(next);
}

function step(target: string | undefined, delta: number): void {
  const exploration =
    snapshot.explorations.find((candidate) => candidate.target === target) ?? snapshot.explorations[0];
  if (!exploration) return;
  const ids = exploration.variantIds;
  const index = ids.indexOf(resolveVariant(snapshot, exploration));
  const next = ids[(index + delta + ids.length) % ids.length];
  if (next !== undefined) pick(exploration.target, next);
}

function isTyping(element: EventTarget | null): boolean {
  if (!(element instanceof HTMLElement)) return false;
  return element.isContentEditable || element.matches("input, textarea, select");
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot(): Snapshot {
  return snapshot;
}

function getServerSnapshot(): Snapshot {
  return SERVER_SNAPSHOT;
}

/**
 * Returns the variant picked for `target`. The first key in `variants` is the
 * default, and the only one ever returned outside dev builds.
 */
export function useExploreVariant<Variant>(
  target: string,
  variants: Readonly<Record<string, Variant>>,
): Variant {
  const variantIds = Object.keys(variants);
  const idsKey = variantIds.join("\n");

  useEffect(() => {
    if (IS_DEV) register(target, idsKey.split("\n"));
  }, [target, idsKey]);

  const current = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const chosen = IS_DEV ? resolveVariant(current, { target, variantIds }) : variantIds[0];
  const variant = chosen === undefined ? undefined : variants[chosen];
  if (variant === undefined) {
    throw new Error(`useExploreVariant("${target}") needs at least one variant.`);
  }
  return variant;
}

/** Mount once in the root layout. Renders nothing outside dev builds. */
export function ExploreSwitcher() {
  const current = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const [activeTarget, setActiveTarget] = useState<string>();
  const [layout, setLayout] = useState<"row" | "column">("row");
  const rootRef = useRef<HTMLDivElement>(null);
  const rowWidth = useRef({ key: "", width: 0 });
  const contentKey = current.explorations
    .map((exploration) => `${exploration.target}:${exploration.variantIds.join(",")}`)
    .join("|");

  useEffect(() => {
    if (!IS_DEV) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "[" && event.key !== "]") return;
      if (event.repeat || event.metaKey || event.ctrlKey || event.altKey) return;
      if (event.isComposing || isTyping(event.target)) return;
      event.preventDefault();
      step(activeTarget, event.key === "]" ? 1 : -1);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [activeTarget]);

  // The row's width is measured while it is a row. The bar turns into a column
  // when that width is more than the window has room for, and back when it fits.
  useBrowserLayoutEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const fit = () => {
      if (layout === "row") rowWidth.current = { key: contentKey, width: root.offsetWidth };
      const measured = rowWidth.current.key === contentKey;
      const fits = rowWidth.current.width <= window.innerWidth - 2 * EDGE;
      setLayout(!measured || fits ? "row" : "column");
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, [layout, contentKey]);

  if (!IS_DEV || current.explorations.length === 0) return null;

  const row = layout === "row";
  const keyed = activeTarget ?? current.explorations[0]?.target;

  return (
    <div
      ref={rootRef}
      role="toolbar"
      aria-label="Design variants"
      aria-orientation={row ? "horizontal" : "vertical"}
      title="Press [ or ] to switch variants"
      style={row ? styles.rootRow : styles.rootColumn}
    >
      {current.explorations.map((exploration) => {
        const chosen = resolveVariant(current, exploration);
        const labelStyle = exploration.target === keyed ? styles.labelKeyed : styles.label;
        return (
          <div
            key={exploration.target}
            role="group"
            aria-label={exploration.target}
            style={row ? styles.groupRow : styles.groupColumn}
          >
            <span style={labelStyle}>{exploration.target}</span>
            {exploration.variantIds.map((variantId) => (
              <button
                key={variantId}
                type="button"
                aria-pressed={variantId === chosen}
                onClick={() => {
                  setActiveTarget(exploration.target);
                  pick(exploration.target, variantId);
                }}
                style={variantId === chosen ? styles.optionActive : styles.option}
              >
                {variantId}
              </button>
            ))}
          </div>
        );
      })}
    </div>
  );
}

// Neutral chrome on purpose: the switcher is a tool, not part of the design.
const font = 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif';
// Gap between the bar and the window edge, in pixels.
const EDGE = 16;

const root: CSSProperties = {
  position: "fixed",
  bottom: EDGE,
  zIndex: 2147483647,
  display: "flex",
  flexDirection: "column",
  gap: 2,
  padding: 4,
  borderRadius: 12,
  background: "#171717",
  boxShadow: "0 8px 30px rgba(0, 0, 0, 0.35)",
};

const label: CSSProperties = {
  padding: "4px 8px",
  color: "#737373",
  font: `600 11px/1.3 ${font}`,
  letterSpacing: "0.04em",
  textTransform: "uppercase",
  whiteSpace: "nowrap",
};

const option: CSSProperties = {
  padding: "6px 10px",
  border: 0,
  borderRadius: 8,
  background: "transparent",
  color: "#d4d4d4",
  font: `500 13px/1.3 ${font}`,
  textAlign: "left",
  whiteSpace: "nowrap",
  cursor: "pointer",
};

const styles = {
  rootRow: { ...root, left: "50%", transform: "translateX(-50%)", width: "max-content" },
  rootColumn: { ...root, right: EDGE, maxHeight: `calc(100vh - ${2 * EDGE}px)`, overflowY: "auto" },
  groupRow: { display: "flex", alignItems: "center", gap: 2 },
  groupColumn: { display: "flex", flexDirection: "column", gap: 2 },
  label,
  labelKeyed: { ...label, color: "#a3a3a3" },
  option,
  optionActive: { ...option, background: "#404040", color: "#ffffff" },
} satisfies Record<string, CSSProperties>;

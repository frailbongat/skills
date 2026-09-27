"use client";

// Dev-only design switcher, copied in by the design-explore skill.
// `/skill:design-explore lock` deletes this folder once no exploration is left.
//
// The pick lives in memory and in `?variant=` so a link or a second tab opens
// the same variant. The URL is read from `window.location` and written with
// `history.replaceState(null, ...)`. Passing null, as the Next.js docs do, lets
// the App Router sync to the new URL, so its next render keeps the param.
// That keeps `useSearchParams` out, so no page needs a Suspense boundary for it.

import { useEffect, useState, useSyncExternalStore, type CSSProperties } from "react";

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
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [open]);

  if (!IS_DEV || current.explorations.length === 0) return null;

  const only = current.explorations.length === 1 ? current.explorations[0] : undefined;
  const label = only
    ? `${only.target}: ${resolveVariant(current, only)}`
    : `${current.explorations.length} explorations`;

  return (
    <div style={styles.root}>
      {open ? (
        <div role="dialog" aria-label="Design variants" style={styles.panel}>
          {current.explorations.map((exploration) => {
            const chosen = resolveVariant(current, exploration);
            return (
              <div key={exploration.target} role="group" aria-label={exploration.target} style={styles.group}>
                <div style={styles.groupLabel}>{exploration.target}</div>
                {exploration.variantIds.map((variantId) => (
                  <button
                    key={variantId}
                    type="button"
                    aria-pressed={variantId === chosen}
                    onClick={() => pick(exploration.target, variantId)}
                    style={variantId === chosen ? styles.optionActive : styles.option}
                  >
                    {variantId}
                  </button>
                ))}
              </div>
            );
          })}
        </div>
      ) : null}
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((isOpen) => !isOpen)}
        style={styles.pill}
      >
        {label}
      </button>
    </div>
  );
}

// Neutral chrome on purpose: the switcher is a tool, not part of the design.
const font = 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif';

const option: CSSProperties = {
  display: "block",
  width: "100%",
  padding: "6px 10px",
  border: 0,
  borderRadius: 8,
  background: "transparent",
  color: "#e5e5e5",
  font: `500 13px/1.3 ${font}`,
  textAlign: "left",
  cursor: "pointer",
};

const styles = {
  root: {
    position: "fixed",
    right: 16,
    bottom: 16,
    zIndex: 2147483647,
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-end",
    gap: 8,
  },
  panel: {
    width: 240,
    maxHeight: "60vh",
    overflowY: "auto",
    padding: 6,
    borderRadius: 12,
    background: "#171717",
    boxShadow: "0 8px 30px rgba(0, 0, 0, 0.35)",
  },
  group: { padding: "4px 0" },
  groupLabel: {
    padding: "4px 10px",
    color: "#a3a3a3",
    font: `600 11px/1.3 ${font}`,
    letterSpacing: "0.04em",
    textTransform: "uppercase",
  },
  option,
  optionActive: { ...option, background: "#404040", color: "#ffffff" },
  pill: {
    padding: "8px 14px",
    border: 0,
    borderRadius: 999,
    background: "#171717",
    color: "#ffffff",
    font: `600 13px/1 ${font}`,
    boxShadow: "0 4px 16px rgba(0, 0, 0, 0.3)",
    cursor: "pointer",
  },
} satisfies Record<string, CSSProperties>;

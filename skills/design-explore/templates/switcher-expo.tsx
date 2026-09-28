// Dev-only design switcher, copied in by the design-explore skill.
// `/skill:design-explore lock` deletes this folder once no exploration is left.
//
// `./storage` is one of two copies: storage-async.ts remembers the pick across
// reloads when the project already depends on AsyncStorage, storage-memory.ts
// keeps it for the session only.
//
// Every variant is a chip in an always-open bar above the tab bar, so a switch
// is one tap. Each exploration gets one row that scrolls sideways when its
// chips overflow. On Expo web, `[` and `]` step to the previous and next
// variant of the exploration tapped last, or the first one.

import { useEffect, useState, useSyncExternalStore } from "react";
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { loadPicks, savePicks, type Picks } from "./storage";

type Exploration = {
  readonly target: string;
  readonly variantIds: readonly string[];
};

type Snapshot = {
  readonly explorations: readonly Exploration[];
  readonly picks: Picks;
};

const INITIAL_SNAPSHOT: Snapshot = { explorations: [], picks: {} };
const listeners = new Set<() => void>();
let snapshot: Snapshot = INITIAL_SNAPSHOT;

if (__DEV__) {
  void loadPicks().then((saved) => {
    // A pick made before loading finished wins over the saved one.
    update({ ...snapshot, picks: { ...saved, ...snapshot.picks } });
  });
}

function resolveVariant(current: Snapshot, exploration: Exploration): string {
  const wanted = current.picks[exploration.target];
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
  const picks = { ...snapshot.picks, [target]: variantId };
  update({ ...snapshot, picks });
  void savePicks(picks);
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

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot(): Snapshot {
  return snapshot;
}

// Expo web static rendering and hydration use this one.
function getServerSnapshot(): Snapshot {
  return INITIAL_SNAPSHOT;
}

/**
 * Returns the variant picked for `target`. The first key in `variants` is the
 * default, and the only one ever returned outside `__DEV__`.
 */
export function useExploreVariant<Variant>(
  target: string,
  variants: Readonly<Record<string, Variant>>,
): Variant {
  const variantIds = Object.keys(variants);
  const idsKey = variantIds.join("\n");

  useEffect(() => {
    if (__DEV__) register(target, idsKey.split("\n"));
  }, [target, idsKey]);

  const current = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const chosen = __DEV__ ? resolveVariant(current, { target, variantIds }) : variantIds[0];
  const variant = chosen === undefined ? undefined : variants[chosen];
  if (variant === undefined) {
    throw new Error(`useExploreVariant("${target}") needs at least one variant.`);
  }
  return variant;
}

/** Mount once in the root layout. Renders nothing outside `__DEV__`. */
export function ExploreSwitcher() {
  const current = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const [activeTarget, setActiveTarget] = useState<string>();

  useEffect(() => {
    if (!__DEV__ || Platform.OS !== "web") return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "[" && event.key !== "]") return;
      if (event.repeat || event.metaKey || event.ctrlKey || event.altKey || event.isComposing) return;
      const focused = event.target;
      if (focused instanceof HTMLElement && (focused.isContentEditable || focused.matches("input, textarea, select"))) {
        return;
      }
      event.preventDefault();
      step(activeTarget, event.key === "]" ? 1 : -1);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [activeTarget]);

  if (!__DEV__ || current.explorations.length === 0) return null;

  const keyed = activeTarget ?? current.explorations[0]?.target;

  return (
    <View accessibilityLabel="Design variants" style={styles.bar}>
      {current.explorations.map((exploration) => {
        const chosen = resolveVariant(current, exploration);
        return (
          <ScrollView
            key={exploration.target}
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.row}
          >
            <Text style={[styles.label, exploration.target === keyed && styles.labelKeyed]}>
              {exploration.target}
            </Text>
            {exploration.variantIds.map((variantId) => {
              const selected = variantId === chosen;
              return (
                <Pressable
                  key={variantId}
                  accessibilityRole="button"
                  accessibilityState={{ selected }}
                  onPress={() => {
                    setActiveTarget(exploration.target);
                    pick(exploration.target, variantId);
                  }}
                  style={({ pressed }) => [styles.option, selected && styles.optionSelected, pressed && styles.optionPressed]}
                >
                  <Text style={[styles.optionText, selected && styles.optionTextSelected]}>{variantId}</Text>
                </Pressable>
              );
            })}
          </ScrollView>
        );
      })}
    </View>
  );
}

// Neutral chrome on purpose: the switcher is a tool, not part of the design.
const styles = StyleSheet.create({
  bar: {
    position: "absolute",
    left: 12,
    right: 12,
    // High enough to clear a bottom tab bar.
    bottom: 112,
    zIndex: 9999,
    elevation: 12,
    gap: 2,
    padding: 4,
    borderRadius: 14,
    backgroundColor: "#171717",
    shadowColor: "#000000",
    shadowOpacity: 0.3,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
  },
  row: { alignItems: "center", gap: 2 },
  label: {
    paddingHorizontal: 8,
    color: "#737373",
    fontSize: 11,
    fontWeight: "600",
    letterSpacing: 0.5,
    textTransform: "uppercase",
  },
  labelKeyed: { color: "#a3a3a3" },
  option: { paddingHorizontal: 12, paddingVertical: 10, borderRadius: 10 },
  optionSelected: { backgroundColor: "#404040" },
  optionPressed: { opacity: 0.7 },
  optionText: { color: "#d4d4d4", fontSize: 14, fontWeight: "500" },
  optionTextSelected: { color: "#ffffff" },
});

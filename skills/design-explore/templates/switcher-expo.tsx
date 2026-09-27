// Dev-only design switcher, copied in by the design-explore skill.
// `/skill:design-explore lock` deletes this folder once no exploration is left.
//
// `./storage` is one of two copies: storage-async.ts remembers the pick across
// reloads when the project already depends on AsyncStorage, storage-memory.ts
// keeps it for the session only.

import { useEffect, useState, useSyncExternalStore } from "react";
import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
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
  const [open, setOpen] = useState(false);

  if (!__DEV__ || current.explorations.length === 0) return null;

  const only = current.explorations.length === 1 ? current.explorations[0] : undefined;
  const label = only ? resolveVariant(current, only) : `${current.explorations.length} explorations`;

  return (
    <>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`Design variants, showing ${label}`}
        onPress={() => setOpen(true)}
        style={({ pressed }) => [styles.pill, pressed && styles.pillPressed]}
      >
        <Text style={styles.pillText}>{label}</Text>
      </Pressable>
      <Modal visible={open} transparent animationType="slide" onRequestClose={() => setOpen(false)}>
        <View style={styles.sheetLayer}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Close design variants"
            onPress={() => setOpen(false)}
            style={styles.backdrop}
          />
          <View style={styles.sheet}>
            <View style={styles.handle} />
            <ScrollView contentContainerStyle={styles.sheetContent}>
              {current.explorations.map((exploration) => {
                const chosen = resolveVariant(current, exploration);
                return (
                  <View key={exploration.target} style={styles.group}>
                    <Text style={styles.groupLabel}>{exploration.target}</Text>
                    {exploration.variantIds.map((variantId) => {
                      const selected = variantId === chosen;
                      return (
                        <Pressable
                          key={variantId}
                          accessibilityRole="button"
                          accessibilityState={{ selected }}
                          onPress={() => {
                            pick(exploration.target, variantId);
                            setOpen(false);
                          }}
                          style={[styles.option, selected && styles.optionSelected]}
                        >
                          <Text style={[styles.optionText, selected && styles.optionTextSelected]}>
                            {variantId}
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                );
              })}
            </ScrollView>
          </View>
        </View>
      </Modal>
    </>
  );
}

// Neutral chrome on purpose: the switcher is a tool, not part of the design.
const styles = StyleSheet.create({
  pill: {
    position: "absolute",
    right: 12,
    // High enough to clear a bottom tab bar.
    bottom: 112,
    zIndex: 9999,
    elevation: 12,
    paddingHorizontal: 14,
    paddingVertical: 9,
    borderRadius: 999,
    backgroundColor: "#171717",
    shadowColor: "#000000",
    shadowOpacity: 0.3,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
  },
  pillPressed: { opacity: 0.8 },
  pillText: { color: "#ffffff", fontSize: 13, fontWeight: "600" },
  sheetLayer: { flex: 1, justifyContent: "flex-end" },
  // Spelled out because StyleSheet.absoluteFill's type differs across React Native versions.
  backdrop: {
    position: "absolute",
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    backgroundColor: "rgba(0, 0, 0, 0.35)",
  },
  sheet: {
    maxHeight: "70%",
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    backgroundColor: "#171717",
  },
  handle: {
    alignSelf: "center",
    width: 36,
    height: 4,
    marginTop: 8,
    borderRadius: 2,
    backgroundColor: "#525252",
  },
  sheetContent: { padding: 12, paddingBottom: 40 },
  group: { paddingVertical: 6 },
  groupLabel: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    color: "#a3a3a3",
    fontSize: 11,
    fontWeight: "600",
    letterSpacing: 0.5,
    textTransform: "uppercase",
  },
  option: { paddingHorizontal: 10, paddingVertical: 12, borderRadius: 10 },
  optionSelected: { backgroundColor: "#404040" },
  optionText: { color: "#e5e5e5", fontSize: 15, fontWeight: "500" },
  optionTextSelected: { color: "#ffffff" },
});

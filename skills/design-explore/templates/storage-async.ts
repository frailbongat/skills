// Picks for the design-explore switcher, remembered across reloads.
// Copied in as `_variants/storage.ts` only when the project already depends on
// @react-native-async-storage/async-storage.

import AsyncStorage from "@react-native-async-storage/async-storage";

export type Picks = Readonly<Record<string, string>>;

const KEY = "design-explore:picks";

export async function loadPicks(): Promise<Picks> {
  try {
    const raw = await AsyncStorage.getItem(KEY);
    const parsed: unknown = raw === null ? null : JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null) return {};
    return Object.fromEntries(
      Object.entries(parsed).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
    );
  } catch {
    return {};
  }
}

export async function savePicks(picks: Picks): Promise<void> {
  try {
    await AsyncStorage.setItem(KEY, JSON.stringify(picks));
  } catch {
    // The pick still holds in memory for this session.
  }
}

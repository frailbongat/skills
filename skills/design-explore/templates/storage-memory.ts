// Picks for the design-explore switcher, kept for this session only.
// Copied in as `_variants/storage.ts` when the project has no AsyncStorage.

export type Picks = Readonly<Record<string, string>>;

export const loadPicks = (): Promise<Picks> => Promise.resolve({});

export const savePicks: (picks: Picks) => Promise<void> = () => Promise.resolve();

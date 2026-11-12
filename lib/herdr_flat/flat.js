// Design tokens for the Herdr "flat" layout and its mods.
// How the whole layout fits together: docs/herdr-flat.md.
//
// Source of truth. lib/herdr_flat/sync writes these constants (without
// `export`) into a marked block at the top of every mods/flat-*/main.js:
// Herdr won't load a mod's imports through the symlinks dotfiles deploys, so
// the mods can't share a module. Edit here, run the sync, never edit a block.
// tests/herdr_flat_test.sh checks the blocks and that the mods use these
// names instead of bare numbers.
//
// Colours are not here: they come from the theme (theme()), which follows
// the Omarchy theme.

// Corners: boxes are near-square. Round signal dots use .rounded_full().
export const R = 1;

// Lines: borders and dividers.
export const LINE = 1;

// Spacing: a 5px unit. S1 = 5, S2 = 10, S3 = 15, S4 = 20.
export const UNIT = 5;
export const S1 = UNIT;
export const S2 = UNIT * 2;
export const S3 = UNIT * 3;
export const S4 = UNIT * 4;

// A nudge for optical alignment (1-2px), not spacing between things.
export const HAIR = 2;

// Text sizes. Body and names stay at TEXT; SMALL is for meta, counts, badges
// and key chips. Headings are for page and section titles only.
export const TEXT = 13;
export const SMALL = 11;
export const H3 = 15;
export const H2 = 18;
export const H1 = 22;

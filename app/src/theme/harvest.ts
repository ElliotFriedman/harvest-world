/**
 * Harvest design tokens (docs/brand-book.md).
 * Use with Tailwind classes (see globals.css @theme) or inline styles.
 */

export const harvestColors = {
  /** Primary text, active content, success, logo */
  terminalGreen: "#00ff00",
  /** Background — never white/light in product UI */
  terminalDark: "#0a0a0a",
  /** Secondary, labels, inactive, timestamps */
  terminalDim: "#00aa00",
  /** Failures, losses — never decorative */
  errorRed: "#ff4444",
  /** Caution, pending */
  warningAmber: "#ffaa00",
  /** Links, info — sparingly */
  infoBlue: "#4444ff",
  /** Disabled, borders, decorative */
  mutedGray: "#666666",
  /** Elevated surfaces, shortcut bar */
  deepGray: "#1a1a1a",
  /** Marketing: "for humans" tagline, CTAs outside terminal */
  humanAmber: "#f5a623",
  /** Marketing body on dark */
  softWhite: "#e0e0e0",
  /** Marketing headings (not inside terminal UI) */
  warmWhite: "#fafafa",
} as const;

export type HarvestColorName = keyof typeof harvestColors;

export const harvestFontFamily =
  '"JetBrains Mono", "Fira Code", "Courier New", monospace' as const;

/** Terminal UI type scale (px) */
export const harvestTypeTerminal = {
  h1: 24,
  h2: 18,
  h3: 16,
  body: 14,
  output: 13,
  label: 12,
  shortcut: 14,
} as const;

/** Marketing / landing (px) */
export const harvestTypeMarketing = {
  heroLogo: 72,
  heroTagline: 32,
  sectionHeading: 28,
  sectionBody: 18,
  statNumber: 48,
  statLabel: 16,
  cta: 18,
  footer: 14,
} as const;

export const harvestLineHeight = {
  body: 1.5,
  heading: 1.2,
  terminal: 1.6,
} as const;

/** Tappable shortcuts (brand book: UI Patterns / Terminal) */
export const harvestShortcut = {
  paddingX: 16,
  paddingY: 8,
  gap: 8,
  radius: 4,
  borderWidth: 1,
} as const;

/** Logo cursor blink — digital spec */
export const harvestMotion = {
  cursorBlinkMs: 530,
} as const;

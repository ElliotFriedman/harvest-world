# Harvest Brand Book

> DeFi, for humans.

The first yield aggregator on World Chain. Auto-compounding yield. Sybil-resistant. Human-verified.

Built for ETHGlobal Cannes 2026 (April 3-5).

---

## Table of Contents

1. [Brand Positioning](#1-brand-positioning)
2. [Brand Personality and Voice](#2-brand-personality-and-voice)
3. [Color Palette](#3-color-palette)
4. [Typography](#4-typography)
5. [Logo System](#5-logo-system)
6. [App Icon Specification](#6-app-icon-specification)
7. [Content Card for World App Store](#7-content-card-for-world-app-store)
8. [UI Patterns (Terminal)](#8-ui-patterns-terminal)
9. [Landing Page Specification](#9-landing-page-specification)
10. [OG Image and Link Previews](#10-og-image-and-link-previews)
11. [Social Media](#11-social-media)
12. [Hackathon Submission Assets](#12-hackathon-submission-assets)
14. [Asset Export Checklist](#14-asset-export-checklist)

---

## 1. Brand Positioning

### Core Identity

| Element | Value |
|---------|-------|
| Name | Harvest |
| Tagline | DeFi, for humans. |
| Subline | Auto-compounding yield. Sybil-resistant. Human-verified. |
| Elevator pitch | The first yield vault where every depositor is cryptographically verified as a unique human. |
| One-liner (short) | The first yield aggregator on World Chain. |
| One-liner (full) | The first yield aggregator on World Chain -- auto-compounding Morpho vault rewards for verified humans. |

### Tagline Usage

**"DeFi, for humans."** is the primary tagline. It works because it operates on two levels:

1. **Literal:** Every depositor is verified as a unique human via World ID. No bots. No sybils.
2. **Aspirational:** DeFi is complicated. Harvest abstracts it to one command. Deposit and forget.

Usage rules:
- Always include the period. "DeFi, for humans." -- not "DeFi for humans" or "DeFi, For Humans."
- Always lowercase "for humans" -- the period carries the weight, not capitalization.
- The comma after "DeFi" is mandatory. It creates the pause.
- When space is extremely limited (under 30 characters), use just "DeFi, for humans." without any prefix.
- In contexts where more explanation is needed, follow with the subline: "Auto-compounding yield. Sybil-resistant. Human-verified."

### Subline Options (pick based on context)

| Context | Subline |
|---------|---------|
| General marketing | Auto-compounding yield. Sybil-resistant. Human-verified. |
| Technical audience | ERC-4626 vault. Beefy fork. World ID gated. |
| Hackathon submission | The first auto-compounding yield aggregator on World Chain. |
| App store listing | Deposit USDC. Auto-compound yield. Every depositor verified human. |
| Twitter bio | DeFi, for humans. The first yield aggregator on World Chain. |

### Positioning Statement

Harvest exists in the intersection of three things:

1. **World Chain's gap:** $42M+ TVL, zero yield aggregators. Not the fifth Beefy fork on Arbitrum -- the first on World Chain.
2. **Human verification:** World ID means every dollar in the vault traces back to a verified unique person. No other yield aggregator can say that.
3. **Agent-native architecture:** The AI agent is not bolted on. It IS the strategist. AgentKit credentials, x402 micropayments, autonomous harvest execution.

### Competitive Framing

Do NOT position against Beefy or Yearn. Harvest IS a Beefy fork. The message is:
- "Beefy for World Chain" -- not "better than Beefy"
- "The first" -- not "the best"
- "For humans" -- not "for degens"

---

## 2. Brand Personality and Voice

### Personality

**Competent, retro-futuristic, quietly confident.**

The terminal aesthetic says "we are engineers, not marketers." The human verification says "we give a shit about who uses this."

Think: a sysadmin who also cares about financial inclusion. Someone who logs everything, speaks in precise numbers, uses dry humor sparingly, and never oversells.

Harvest does not pitch. It performs. It logs what it did, shows the numbers, and moves on.

### Personality Spectrum

| Trait | Harvest is | Harvest is NOT |
|-------|-----------|----------------|
| Confidence | Quietly confident | Hype-driven or boastful |
| Technical depth | Precise, specific | Jargon-heavy for its own sake |
| Humor | Dry, understated, rare | Meme-brained, emoji-laden |
| Aesthetic | Retro-futuristic terminal | Glossy fintech, gradient buttons |
| Relationship to user | Competent operator | Friendly assistant |
| Communication | Brief, factual | Verbose, emotional |

### Tone Guide

**Inside the terminal (product UI):**
- Pure precision. Log format. Numbers, not adjectives.
- No emoji. No exclamation marks. No "congrats!"
- Commands, not buttons. Actions, not prompts.
- The terminal never apologizes. It reports errors factually: `[ERR] Insufficient balance` not "Oops! Something went wrong."

**Outside the terminal (marketing, social, landing page):**
- Same confidence, slightly more warmth.
- "DeFi, for humans." is the warmest the brand gets.
- Numbers always present. Never say "great yields" -- say "4.15% APY."
- Dry humor is allowed: "We spent 36 hours on contracts, not on pretending we built a production fintech app."
- One exclamation mark per 1000 words maximum.

### Voice Do/Don't

| Do | Don't |
|----|-------|
| "Deposited 500 USDC into morpho-usdc vault" | "Your deposit was successful!" |
| "APY: 4.15% (7d avg)" | "Earn amazing yields!" |
| "Compound complete. +2.34 USDC" | "Congrats! You just earned rewards!" |
| "ERR: Insufficient balance" | "Oops! You don't have enough funds" |
| "Next compound: 6h 12m" | "We'll take care of your rewards soon!" |
| "47 verified humans, not 47 wallets" | "Join our growing community!" |
| "Built in 36 hours" | "Revolutionary DeFi platform" |
| "One harvest benefits everyone" | "Maximize your earning potential!" |

### Writing Style Rules

1. **Precision over hype.** Say "4.15% APY" not "great returns."
2. **Log format for agent actions.** Every automated action reads like a log entry:
   ```
   [04/03 14:32] Compounded 42.5 WLD across 47 depositors
   [04/03 14:32] Gas used: 0.0012 ETH ($2.14)
   [04/03 14:33] Next compound scheduled: 04/03 20:32
   ```
3. **Commands, not buttons.** "Run `deposit 50 usdc`" not "Click the deposit button."
4. **Brief.** If it can be said in fewer words, use fewer words.
5. **Active voice.** "The agent compounded rewards" not "Rewards were compounded by the agent."
6. **Lowercase preference** outside of headings. The brand feels more like a terminal when it does not shout.

---

## 3. Color Palette

### Primary Palette (Terminal / Product UI)

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Terminal Green | `#00ff00` | 0, 255, 0 | Primary text, active content, success states, logo |
| Terminal Dark | `#0a0a0a` | 10, 10, 10 | Background for all surfaces. Never white. Never light. |
| Terminal Dim | `#00aa00` | 0, 170, 0 | Secondary text, labels, inactive content, timestamps |

### Secondary Palette (Terminal / Product UI)

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Error Red | `#ff4444` | 255, 68, 68 | Failures, negative values, errors ONLY. Never decorative. |
| Warning Amber | `#ffaa00` | 255, 170, 0 | Caution states, pending operations |
| Info Blue | `#4444ff` | 68, 68, 255 | Informational text, links (use sparingly) |
| Muted Gray | `#666666` | 102, 102, 102 | Disabled states, timestamps, box-drawing borders, decorative |
| Deep Gray | `#1a1a1a` | 26, 26, 26 | Subtle card backgrounds, elevated surfaces over `#0a0a0a` |

### Warm Accent Palette (Marketing / Human Messaging)

These colors are used OUTSIDE the terminal product UI -- on the landing page hero, marketing materials, social cards, and print assets. They add the warmth that "for humans" implies, without breaking the terminal foundation.

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| Human Amber | `#f5a623` | 245, 166, 35 | Warm accent for "for humans" tagline text, CTAs outside terminal |
| Soft White | `#e0e0e0` | 224, 224, 224 | Body text on dark backgrounds in marketing materials |
| Warm White | `#fafafa` | 250, 250, 250 | Headings in marketing materials (never in terminal UI) |

### Color Rules

1. **Background is always `#0a0a0a`.** Never white. Never light. Not even for marketing.
2. **Terminal Green (`#00ff00`) is the default text color** for active content inside the product.
3. **Dim Green (`#00aa00`)** for secondary, supporting, or inactive text inside the product.
4. **Muted Gray (`#666666`)** for box-drawing borders and decorative elements.
5. **Error Red is ONLY for errors and losses.** Never decorative. Never for emphasis.
6. **Human Amber (`#f5a623`)** is reserved for the "for humans" tagline and marketing CTAs. It does NOT appear inside the terminal product UI.
7. **Soft White (`#e0e0e0`)** is for marketing body copy only. Inside the terminal, all text is green or gray.
8. The warm accent palette exists to signal: "this is the approachable, human-facing layer." The terminal palette signals: "this is the competent, engineering layer." Both live on `#0a0a0a`.

### Color in Context

```
TERMINAL UI (product):
  Background:  #0a0a0a
  Text:        #00ff00 (active), #00aa00 (secondary), #666666 (muted)
  Borders:     #666666
  Status:      #00ff00 (OK), #ff4444 (ERR), #ffaa00 (WARN)

LANDING PAGE / MARKETING:
  Background:  #0a0a0a
  Headline:    #00ff00 (for "> harvest_"), #fafafa (for supporting headings)
  Tagline:     #f5a623 ("DeFi, for humans.")
  Body:        #e0e0e0
  CTA button:  #00ff00 text on #0a0a0a, 1px #00ff00 border
  OR:          #0a0a0a text on #00ff00 background (inverted)

SOCIAL / OG IMAGES:
  Background:  #0a0a0a
  Logo:        #00ff00
  Tagline:     #f5a623 or #e0e0e0 depending on composition
```

---

## 4. Typography

### Primary Font

**JetBrains Mono** -- the only font used anywhere in the brand.

```css
font-family: 'JetBrains Mono', 'Fira Code', 'Courier New', monospace;
```

### Font Weights

| Weight | Name | CSS value | Usage |
|--------|------|-----------|-------|
| Bold | JetBrains Mono Bold | `700` | Logo "harvest", headings, emphasis, vault names |
| Regular | JetBrains Mono Regular | `400` | Body text, terminal output, tagline "DeFi, for humans." |
| Light | JetBrains Mono Light | `300` | Subline text, fine print, secondary marketing copy (optional -- use Regular if Light unavailable) |

### Type Scale (Terminal UI)

| Element | Size | Weight | Color | Letter-spacing |
|---------|------|--------|-------|----------------|
| H1 | 24px | 700 | `#00ff00` | 0 (default) |
| H2 | 18px | 700 | `#00ff00` | 0 |
| H3 | 16px | 700 | `#00aa00` | 0 |
| Body / commands | 14px | 400 | `#00ff00` | 0 |
| Terminal output | 13px | 400 | `#00aa00` | 0 |
| Labels / muted | 12px | 400 | `#666666` | 0 |
| Tappable shortcuts | 14px | 700 | `#00ff00` | 0 |

### Type Scale (Marketing / Landing Page)

| Element | Size | Weight | Color | Notes |
|---------|------|--------|-------|-------|
| Hero logo "harvest" | 72px | 700 | `#00ff00` | Includes "> " prefix and "_" cursor |
| Hero tagline | 32px | 400 | `#f5a623` | "DeFi, for humans." |
| Section heading | 28px | 700 | `#fafafa` | Problem, Solution, How it works |
| Section body | 18px | 400 | `#e0e0e0` | Descriptive paragraphs |
| Stats numbers | 48px | 700 | `#00ff00` | TVL, APY, depositors |
| Stats labels | 16px | 400 | `#666666` | Below stats numbers |
| CTA button text | 18px | 700 | `#00ff00` or `#0a0a0a` | Depending on button style |
| Footer | 14px | 400 | `#666666` | Links, credits |

### Typography Rules

1. **One font family everywhere.** No sans-serif. No serif. Monospace only. JetBrains Mono or the fallback stack.
2. **ALL CAPS for section headers** inside the terminal UI: `VAULTS`, `DEPOSITS`, `ACTIVITY LOG`, `AGENT STATUS`.
3. **Sentence case for marketing headings** outside the terminal: "How it works", not "HOW IT WORKS".
4. **Tabular numbers always.** JetBrains Mono has this by default. All numbers align in columns.
5. **No letter-spacing adjustments.** Let the monospace grid do its work.
6. **Line height:** 1.5 for body text, 1.2 for headings, 1.6 for terminal output (readability in dense output).
7. **The tagline "DeFi, for humans." always uses Regular weight (400)**, even next to the Bold logo. The contrast between Bold "harvest" and Regular tagline creates visual hierarchy.

### Font Loading

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;700&display=swap" rel="stylesheet">
```

---

## 5. Logo System

### Primary Logo: Terminal Prompt

```
> harvest_
```

Lowercase. Terminal prompt prefix `>` followed by a space, the word "harvest" in Bold, and a blinking block cursor `_`. It reads as a command. It implies the system is live.

### Logo Specifications

#### 5A. Primary Wordmark

```
> harvest_
```

| Property | Value |
|----------|-------|
| Font | JetBrains Mono Bold 700 |
| Case | All lowercase |
| Prompt character | `>` (greater-than sign, standard ASCII 0x3E) |
| Cursor character | `_` (underscore, standard ASCII 0x5F) |
| Spacing | One standard monospace space between `>` and `h` |
| Color | `#00ff00` on `#0a0a0a` |
| Cursor animation (digital) | Blink at 530ms on, 530ms off |

#### 5B. Tagline Lockup

The logo stacked with the tagline. Two lines, left-aligned.

```
> harvest_
  DeFi, for humans.
```

| Property | Value |
|----------|-------|
| Line 1 font | JetBrains Mono Bold 700 |
| Line 1 color | `#00ff00` |
| Line 2 font | JetBrains Mono Regular 400 |
| Line 2 color | `#f5a623` (marketing) or `#00aa00` (terminal) |
| Vertical gap | 8px between baselines at 24px type size (scale proportionally) |
| Line 2 indent | 2 monospace characters (to align with the "h" in "harvest", under the space after `>`) |

When the tagline must be green (inside the terminal or monochrome contexts):
```
> harvest_
  DeFi, for humans.
```
Line 2 color: `#00aa00` (dim green).

#### 5C. Icon Mark

For app icons, favicons, and small-format uses where the full wordmark does not fit.

**Primary icon: `>H_`**

| Property | Value |
|----------|-------|
| Characters | `>H_` (greater-than, capital H, underscore) |
| Font | JetBrains Mono Bold 700 |
| Color | `#00ff00` on `#0a0a0a` |
| Note | Capital H for legibility at small sizes. The `>` and `_` provide terminal context. |

**Alternate icon: `H` in terminal box**

A single capital `H` in JetBrains Mono Bold, centered inside a 1px `#00ff00` border rectangle with rounded corners (4px radius at 512px size). This is for contexts where `>H_` is too busy (e.g., 16x16 favicon).

| Property | Value |
|----------|-------|
| Character | `H` (capital) |
| Font | JetBrains Mono Bold 700 |
| Box border | 1px `#00ff00`, 4px corner radius (at 512px; scale proportionally) |
| Box padding | 20% of box width on all sides |
| Color | `#00ff00` letter and border on `#0a0a0a` fill |

**Minimal icon (16x16 only): `>`**

At favicon size, reduce to a single green `>` on dark background. No box, no H.

### Logo Size Specifications

#### 512x512 (App Icon / App Store)

```
Canvas:     512 x 512 px
Background: #0a0a0a, solid fill, no transparency
Content:    ">H_" in JetBrains Mono Bold
Font size:  160px
Color:      #00ff00
Position:   Centered horizontally and vertically
            Optical center (raise ~8px above mathematical center)
Padding:    Minimum 76px (15%) from each edge
Corner rad: 0 (square asset; platforms apply their own rounding)
Export:     PNG, no transparency, sRGB
```

#### 128x128 (Large Favicon / Shortcut)

```
Canvas:     128 x 128 px
Background: #0a0a0a, solid fill
Content:    ">H_" in JetBrains Mono Bold
Font size:  40px
Color:      #00ff00
Position:   Centered
Padding:    Minimum 19px (15%) from each edge
Export:     PNG, no transparency, sRGB
```

#### 64x64 (World App Mini-App List / Small Icon)

```
Canvas:     64 x 64 px
Background: #0a0a0a, solid fill
Content:    ">H_" in JetBrains Mono Bold
Font size:  20px
Color:      #00ff00
Position:   Centered
Padding:    Minimum 10px (15%) from each edge
Export:     PNG, no transparency, sRGB

Legibility test: if ">H_" is not crisp at 64px, fall back to 
boxed "H" (single character, 1px green border box, 28px font)
```

#### 16x16 (Browser Favicon)

```
Canvas:     16 x 16 px
Background: #0a0a0a, solid fill
Content:    ">" in JetBrains Mono Bold
Font size:  12px
Color:      #00ff00
Position:   Centered, nudge 1px right for optical balance
Export:     ICO or PNG, no transparency
Also export: 32x32 version with same design for retina
```

#### 1200x630 (OG Image / Social Share)

See [Section 10: OG Image](#10-og-image-and-link-previews) for full specification.

### Logo Clear Space

Minimum clear space around the logo equals the width of the `>` character at the rendered size. No other elements may enter this zone.

```
           [clear space = width of ">"]
    ┌──────────────────────────────────┐
    │                                  │
    │      > harvest_                  │
    │                                  │
    └──────────────────────────────────┘
```

For the tagline lockup, clear space is measured from the outer edges of both lines.

### Logo Don'ts

1. **Do not use a white or light background.** Always `#0a0a0a` or darker.
2. **Do not change the font.** Always JetBrains Mono Bold.
3. **Do not remove the prompt `>`.** It is part of the logo.
4. **Do not remove the cursor `_`.** It implies the system is live.
5. **Do not capitalize** "harvest" in the wordmark. Always lowercase.
6. **Do not add a period** after "harvest_". The underscore IS the punctuation.
7. **Do not use the logo in color on a colored background.** Green on dark only.
8. **Do not stretch, rotate, or distort.**
9. **Do not add drop shadows, glows, or gradients** (exception: subtle CRT scanline effect on landing page hero only).
10. **Do not animate the text** (exception: typing animation on landing page hero and cursor blink).

### Monochrome / Print Version

When printing on light paper or in single-color contexts:
- Logo: `#0a0a0a` (near-black) on white paper
- Reverse: `#ffffff` on `#0a0a0a` background
- Never use `#00ff00` on white -- it has poor contrast and looks cheap

---

## 6. App Icon Specification

### World Developer Portal Requirements

The World Developer Portal requires a square app icon. It must NOT have a white background and must be readable at 64x64.

### Primary App Icon

```
+--------------------------------------------------+
|                                                  |
|                                                  |
|                                                  |
|                  >H_                             |
|              (centered, green on dark)           |
|                                                  |
|                                                  |
|                                                  |
+--------------------------------------------------+
```

**Exact construction:**

| Property | Value |
|----------|-------|
| Canvas | 512 x 512 px |
| Background color | `#0a0a0a` (solid, no transparency, no gradient) |
| Text content | `>H_` |
| Font | JetBrains Mono Bold (700) |
| Font size | 160px |
| Text color | `#00ff00` |
| Text position | Centered horizontally; vertically centered with 8px upward offset for optical balance |
| Safe zone | Keep text within center 70% (358x358 area) -- platforms crop corners differently |
| Corner radius | Ship square (0px). World App applies its own mask. Do NOT pre-round corners. |
| File format | PNG, sRGB, no transparency |
| File name | `harvest-icon-512.png` |

**Additional exports:**

| Size | File name | Notes |
|------|-----------|-------|
| 512x512 | `harvest-icon-512.png` | App store, Developer Portal |
| 256x256 | `harvest-icon-256.png` | General use |
| 180x180 | `harvest-icon-180.png` | Apple touch icon |
| 128x128 | `harvest-icon-128.png` | Large favicon |
| 64x64 | `harvest-icon-64.png` | World App mini-app list |
| 32x32 | `harvest-icon-32.png` | Favicon retina |
| 16x16 | `harvest-icon-16.png` | Favicon (use `>` only at this size) |

### Legibility Validation

Before shipping, render the icon at each target size and verify:
- At 512px: `>H_` is sharp, centered, and clearly reads as a terminal prompt
- At 64px: `>H_` is still recognizable. If not, switch to boxed `H`
- At 16px: `>` is a distinct green chevron on dark

---

## 7. Content Card for World App Store

### Requirements

The World App Store content card is displayed in the app discovery UI. It is 345x240 at 1x resolution.

### Specification

| Property | Value |
|----------|-------|
| Size | 345 x 240 px (@1x) / 1035 x 720 px (@3x) |
| Background | `#0a0a0a` solid fill |
| Format | PNG, sRGB, no transparency |

### Layout (work at @3x = 1035x720, scale down)

```
+--------------------------------------------------+
|                                                  |
|      > harvest_                                  |
|                                                  |
|      DeFi, for humans.                           |
|                                                  |
|      ┌─────────────────────────────────┐         |
|      │ > deposit 50 usdc              │         |
|      │ OK Deposited. APY: 4.15%       │         |
|      └─────────────────────────────────┘         |
|                                                  |
+--------------------------------------------------+
```

**Element specifications (@3x / 1035x720):**

| Element | Font | Size (@3x) | Color | Position |
|---------|------|------------|-------|----------|
| `> harvest_` | JetBrains Mono Bold | 72px | `#00ff00` | x: 90px, y: 168px (baseline) |
| `DeFi, for humans.` | JetBrains Mono Regular | 42px | `#f5a623` | x: 90px, y: 240px (baseline) |
| Terminal snippet box | -- | 540 x 180px | `#1a1a1a` fill, `#666666` 2px border | x: 90px, y: 300px (top-left) |
| Terminal text line 1 | JetBrains Mono Regular | 33px | `#00ff00` | x: 120px, y: 360px (baseline) |
| Terminal text line 2 | JetBrains Mono Regular | 33px | `#00aa00` | x: 120px, y: 408px (baseline) |
| Terminal snippet corner radius | -- | 12px | -- | -- |

**Terminal snippet content:**
```
> deposit 50 usdc
OK Deposited into Re7 USDC (4.15% APY)
```

**Design rationale:** The card shows the brand (logo + tagline) AND what the product does (a deposit command with result). A judge or user scanning the World App Store immediately understands: terminal UI, yield product, human-verified. The snippet is a miniature demo.

**Alternative layout (if the snippet feels too busy at 345x240):**

Simpler version -- logo, tagline, and one stat:

```
+--------------------------------------------------+
|                                                  |
|                                                  |
|            > harvest_                            |
|            DeFi, for humans.                     |
|                                                  |
|            Auto-compounding yield                |
|            on World Chain                        |
|                                                  |
+--------------------------------------------------+
```

Center all elements. `> harvest_` at 72px Bold green, tagline at 42px Regular amber, descriptor at 33px Regular `#e0e0e0`.

---

## 8. UI Patterns (Terminal)

### Borders

Use Unicode box-drawing characters (`+`, `-`, `|`) for all containers:

```
+--[ VAULT: MORPHO-USDC ]-------------------------+
| APY           4.15%                              |
| TVL           $1,204,832                         |
| Your deposit  500.00 USDC                        |
+--------------------------------------------------+
```

Border color: `#666666`. Header text inside `[ ]`: `#00ff00`.

### Tables

```
VAULT              APY      TVL          YOUR BAL
morpho-usdc        4.15%    $1,204,832   500.00
morpho-weth        3.82%    $892,441     0.00
morpho-wld         6.21%    $341,009     1,200.00
```

Right-align numbers. Left-align names. Use consistent column widths. Header row in `#00aa00`. Data rows in `#00ff00`. Zero balances in `#666666`.

### Progress Bars

```
Compounding... [================        ] 67%
```

Filled portion: `#00ff00`. Unfilled: `#666666`. Percentage: `#00aa00`.

### Spinners

Rotate through: `/ - \ |` at 100ms intervals.

```
Fetching vault data... /
```

Spinner character in `#00ff00`. Status text in `#00aa00`.

### Status Indicators

```
[OK] Vault synced
[ERR] Transaction reverted: insufficient balance
[WARN] Gas price elevated: 42 gwei
[INFO] Next compound in 2h 14m
```

| Prefix | Color |
|--------|-------|
| `[OK]` | `#00ff00` |
| `[ERR]` | `#ff4444` |
| `[WARN]` | `#ffaa00` |
| `[INFO]` | `#00aa00` |

Message text: same color as the prefix.

### Command Input

```
> deposit 50 usdc_
```

Prompt `>` in `#666666`. Command text in `#00ff00`. Cursor `_` blinks at 530ms on/off.

### Tappable Shortcuts (Mobile)

Bottom of the terminal screen, a row of buttons for common commands:

```
[ vaults ]  [ portfolio ]  [ deposit ]  [ agent status ]  [ help ]
```

| Property | Value |
|----------|-------|
| Background | `#1a1a1a` |
| Border | 1px `#666666` |
| Text | `#00ff00`, JetBrains Mono Bold, 14px |
| Padding | 8px 16px |
| Border radius | 4px |
| Active state | Background `#00ff00`, text `#0a0a0a` |
| Gap between buttons | 8px |

### Terminal Boot Sequence

```
> Initializing Harvest v1.0...
> Connecting to World Chain (480)...
> World ID: VERIFIED (orb)
> Wallet: 0x1a2B...9fC4
> Session active. Type 'help' to begin.
```

Each line appears with a 200ms delay between lines. Lines in `#00aa00`. The final line switches to `#00ff00`.

### No Emoji Rule

The terminal UI does not use emoji. Ever. Status indicators use `[OK]`, `[ERR]`, `[WARN]`, `[INFO]` -- not checkmarks, crosses, or warning triangles. The only exception: if World App's MiniKit injects native UI elements (e.g., confirmation modals), those may contain platform emoji outside the terminal viewport.

---

## 9. Landing Page Specification

### Architecture Decision

**The landing page IS the pre-auth state of the terminal.**

Before World ID verification, the terminal displays landing content. After verification, it becomes the interactive terminal. One URL (`/`), two states. This avoids building a separate marketing site, keeps the brand consistent, and creates a memorable transition: the "marketing page" literally transforms into the product when you verify as human.

### Pre-Auth State (Landing Content)

The page loads on `#0a0a0a` background. Content renders inside a terminal-style container, but with larger type sizes and more breathing room than the post-auth terminal.

#### Section 1: Hero (above the fold)

**Visual:** Dark screen. Subtle CRT scanline overlay (horizontal lines at 2px intervals, `#ffffff` at 3% opacity). Optional: faint grid pattern in `#1a1a1a`.

**Content sequence (typing animation):**

```
> harvest_
```

The `> harvest_` types in character by character at 80ms per character, in `#00ff00`, JetBrains Mono Bold, 72px (mobile: 48px). After a 600ms pause, the tagline types below:

```
  DeFi, for humans.
```

In `#f5a623`, JetBrains Mono Regular, 32px (mobile: 24px). Indented 2 characters to align with "harvest".

After another 400ms pause, the subline fades in (no typing animation, just opacity 0 to 1 over 300ms):

```
  Auto-compounding yield. Sybil-resistant. Human-verified.
```

In `#e0e0e0`, JetBrains Mono Regular, 18px (mobile: 14px). Same indent.

**Layout:**
- Terminal container: max-width 800px, centered, padding 48px (mobile: 24px)
- Logo position: 30% down from viewport top
- CTA below subline, 32px gap

**CTA Button:**

```
[ Open in World App ]
```

| Property | Value |
|----------|-------|
| Text | "Open in World App" |
| Font | JetBrains Mono Bold, 18px |
| Text color | `#0a0a0a` |
| Background | `#00ff00` |
| Border | none |
| Padding | 16px 32px |
| Border radius | 4px |
| Hover | Background `#00cc00` |
| Mobile | Full width (max-width 400px), centered |

Alternative CTA style (outline, feels more terminal):

| Property | Value |
|----------|-------|
| Text color | `#00ff00` |
| Background | transparent |
| Border | 2px solid `#00ff00` |
| Hover | Background `#00ff00`, text `#0a0a0a` |

#### Section 2: Problem (scroll into view)

Fade-in on scroll. Terminal-style monospace text at 18px.

```
WORLD CHAIN DEFI
$42M TVL. 25M+ users. Zero yield aggregators.

Rewards pile up unclaimed in Merkl.
Bots farm what humans should earn.
1,000 users = 1,000 separate claim transactions.
```

| Element | Color |
|---------|-------|
| "WORLD CHAIN DEFI" header | `#00ff00`, Bold |
| Stats line | `#fafafa`, Regular |
| Description lines | `#e0e0e0`, Regular |

#### Section 3: Solution

Three terminal-style cards, side by side (stacked on mobile). Each card represents one step.

```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ 1. DEPOSIT       │  │ 2. FORGET        │  │ 3. EARN          │
│                  │  │                  │  │                  │
│ > deposit        │  │ Agent compounds  │  │ > portfolio      │
│   50 usdc        │  │   every 6 hours  │  │   Value: $51.23  │
│                  │  │                  │  │   Earned: +$1.23 │
│ OK Deposited.    │  │ You do nothing.  │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

| Property | Value |
|----------|-------|
| Card background | `#1a1a1a` |
| Card border | 1px solid `#666666` |
| Card corner radius | 8px |
| Card padding | 24px |
| Card width | 280px (flexible; 3-column on desktop, single-column stack on mobile) |
| Step number + title | `#00ff00`, Bold, 16px |
| Terminal text | `#00aa00`, Regular, 14px |
| Card gap | 24px |

#### Section 4: How It Works

Four points, each with a terminal-style prefix:

```
HOW IT WORKS

[1] Every depositor is verified human (World ID)
    or human-backed agent (AgentKit)

[2] Deposit into battle-tested Beefy vault contracts
    wrapping Morpho lending positions

[3] One harvest transaction compounds rewards
    for ALL depositors simultaneously

[4] Your yield earns yield. Automatically.
    No manual claiming. No gas costs.
```

| Element | Color |
|---------|-------|
| "HOW IT WORKS" | `#00ff00`, Bold, 24px |
| `[1]` prefix | `#f5a623`, Bold |
| Description line 1 | `#e0e0e0`, Regular, 18px |
| Description line 2 | `#00aa00`, Regular, 16px |

#### Section 5: Live Stats

Four large numbers pulled from on-chain data (or hardcoded for hackathon). Displayed in a horizontal row.

```
$125,000         4.15%          47              12
TVL              APY            Depositors      Harvests
```

| Element | Font | Color |
|---------|------|-------|
| Number | JetBrains Mono Bold, 48px (mobile: 32px) | `#00ff00` |
| Label | JetBrains Mono Regular, 16px | `#666666` |

Layout: 4-column grid, centered. On mobile: 2x2 grid.

Data sources:
- TVL: vault contract `totalAssets()` call, formatted as USD
- APY: from Morpho/DeFiLlama API, cache for 15 minutes
- Depositors: count of unique depositors from on-chain events or Supabase
- Harvests: count of successful harvest transactions from Supabase

For the hackathon demo, hardcode reasonable values if live data is not available.

#### Section 6: CTA (bottom)

```
> Ready to earn?

  [ Open in World App ]

  Every depositor verified. Every harvest shared.
```

Same CTA button spec as hero. Below the button, a single line in `#666666`, Regular, 14px.

#### Section 7: Footer

```
────────────────────────────────────────────────────
  Harvest v1.0 | Built at ETHGlobal Cannes 2026
  GitHub  ·  Twitter  ·  World Chain

  Beefy Finance fork (MIT). Morpho Re7 vaults. Uniswap V3.
────────────────────────────────────────────────────
```

| Element | Color |
|---------|-------|
| Divider | `#666666` |
| Links | `#00aa00`, underline on hover |
| Text | `#666666`, 14px |
| Copyright / version | `#666666`, 12px |

### Post-Auth Transition

When the user verifies with World ID, the landing content clears with a brief animation (fade out over 200ms or scroll up), and the interactive terminal boots with the standard boot sequence:

```
> Initializing Harvest v1.0...
> Connecting to World Chain (480)...
> World ID: VERIFIED (orb)
> Wallet: 0x1a2B...9fC4
> Session active. Type 'help' to begin.
```

The terminal is now interactive. The landing page is gone. One component, two states.

### Landing Page Technical Notes

- Built as the app's root `/` route in Next.js
- Pre-auth state renders static/animated content
- Post-auth state renders the interactive terminal
- State switch triggered by successful World ID verification
- The CRT scanline effect is CSS-only: a pseudo-element with repeating-linear-gradient
- Typing animation is a simple interval-based character reveal -- no library needed
- All text is real HTML text (not images), so it is accessible and indexable

### CRT Scanline Effect (CSS)

```css
.terminal-container::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: repeating-linear-gradient(
    0deg,
    rgba(255, 255, 255, 0.03) 0px,
    rgba(255, 255, 255, 0.03) 1px,
    transparent 1px,
    transparent 3px
  );
  pointer-events: none;
  z-index: 1;
}
```

---

## 10. OG Image and Link Previews

### OG Image Specification (1200x630)

This image appears when the Harvest URL is shared on Twitter, Discord, Telegram, Slack, or any platform that renders Open Graph previews.

```
+------------------------------------------------------------+
|                                                            |
|                                                            |
|                                                            |
|         > harvest_                                         |
|                                                            |
|         DeFi, for humans.                                  |
|                                                            |
|         The first yield aggregator on World Chain          |
|                                                            |
|                                                            |
|                                                            |
+------------------------------------------------------------+
```

**Exact specifications:**

| Property | Value |
|----------|-------|
| Canvas | 1200 x 630 px |
| Background | `#0a0a0a` solid fill |
| CRT scanlines | Optional: same as landing page, 3% white opacity |

| Element | Font | Size | Color | Position (from top-left) |
|---------|------|------|-------|--------------------------|
| `> harvest_` | JetBrains Mono Bold | 64px | `#00ff00` | x: 80px, y: 220px (baseline) |
| `DeFi, for humans.` | JetBrains Mono Regular | 36px | `#f5a623` | x: 80px, y: 300px (baseline) |
| `The first yield aggregator on World Chain` | JetBrains Mono Regular | 22px | `#e0e0e0` | x: 80px, y: 370px (baseline) |

**Bottom-right watermark (optional):**

| Element | Font | Size | Color | Position |
|---------|------|------|-------|----------|
| `ETHGlobal Cannes 2026` | JetBrains Mono Regular | 16px | `#666666` | x: right-aligned at 1120px, y: 580px (baseline) |

**Export:** PNG, sRGB, no transparency. File name: `og-image.png`.

### Twitter Card Meta Tags

```html
<meta property="og:title" content="Harvest — DeFi, for humans." />
<meta property="og:description" content="The first yield aggregator on World Chain. Auto-compounding. Sybil-resistant. Every depositor verified human." />
<meta property="og:image" content="https://[domain]/og-image.png" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:type" content="website" />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="Harvest — DeFi, for humans." />
<meta name="twitter:description" content="The first yield aggregator on World Chain. Auto-compounding yield for verified humans." />
<meta name="twitter:image" content="https://[domain]/og-image.png" />
```

---

## 11. Social Media

### Twitter Profile

**Handle preference list** (register whichever is available, in order):

1. `@UseHarvest` -- action-oriented, implies using the product
2. `@HarvestYield` -- descriptive, clear what the product does
3. `@Harvest_World` -- includes World Chain reference
4. `@HarvestDeFi` -- generic but available fallback

**Display name:** `Harvest`

**Bio (160 chars max):**

```
DeFi, for humans. The first yield aggregator on World Chain. Auto-compounding. Sybil-resistant. Every depositor verified. Built at @ETHGlobal Cannes.
```

Character count: 149. Fits.

**Profile picture:** App icon (512x512, `>H_` green on dark). See Section 6.

**Header image (1500x500):**

Terminal screenshot or stylized version. Layout:

```
+----------------------------------------------------------------------+
|                                                                      |
|   > harvest_                                                         |
|     DeFi, for humans.                                                |
|                                                                      |
|   ┌─────────────────────────────────────────────────────────┐       |
|   │ > deposit 50 usdc                                       │       |
|   │ OK Deposited into Re7 USDC vault (4.15% APY)           │       |
|   │ > portfolio                                             │       |
|   │ Total Value: $50.00 | Earned: +$0.23                   │       |
|   └─────────────────────────────────────────────────────────┘       |
|                                                                      |
+----------------------------------------------------------------------+
```

| Property | Value |
|----------|-------|
| Canvas | 1500 x 500 px |
| Background | `#0a0a0a` |
| Logo | JetBrains Mono Bold, 48px, `#00ff00`, top-left area (x: 60, y: 120 baseline) |
| Tagline | JetBrains Mono Regular, 28px, `#f5a623`, below logo (x: 60, y: 170 baseline) |
| Terminal box | `#1a1a1a` fill, `#666666` 1px border, 8px radius, positioned right of center |
| Terminal text | JetBrains Mono Regular, 20px, `#00ff00` / `#00aa00` |

Note: Twitter crops the header differently on mobile vs. desktop. Keep critical content in the center 60% vertically.

### Pinned Tweet Thread

**Tweet 1 (launch announcement):**

```
DeFi, for humans.

Harvest is the first yield aggregator on World Chain.

> deposit 50 usdc
OK Deposited into Re7 USDC vault (4.15% APY)

One vault. Auto-compounding. Every depositor verified human.
```

Attach: OG image or terminal screenshot showing a deposit.

**Tweet 2 (how it works):**

```
How it works:

1. Verify with World ID (you're human)
2. Deposit USDC
3. Our agent auto-compounds Morpho rewards
4. One harvest tx benefits ALL depositors

No bots. No sybil farms. Just humans earning yield.
```

Attach: Architecture diagram or agent status screenshot.

**Tweet 3 (hackathon context):**

```
Built in 36 hours at @ETHGlobal Cannes.

- First yield aggregator on World Chain ($42M TVL, zero aggregators before us)
- Beefy Finance fork (battle-tested, MIT)
- World ID + AgentKit deposit gate
- Terminal UI because we're engineers

github.com/ElliotFriedman/harvest-world
```

Attach: Team photo or terminal screenshot with the boot sequence.

### Tweet Templates (for ongoing updates)

**Harvest completion:**
```
> agent status

Compounded $[AMOUNT] for [N] depositors.
Gas: $[GAS]. Net savings: [N-1] transactions.

Auto-compounding on World Chain. Silently.
```

**TVL milestone:**
```
> harvest status

$[TVL] deposited. [N] verified humans.
[X] harvests completed. Zero bots.

DeFi, for humans.
```

**Technical update:**
```
Shipped: [feature name]

[1-2 line description in terminal voice]

github.com/ElliotFriedman/harvest-world
```

### Social Media Visual Rules

1. **Screenshots of the terminal UI** are the primary visual content.
2. **Dark background always.** Never post on white.
3. **Crop tight.** Show the data, not the browser chrome.
4. **Add subtle padding** (20px `#0a0a0a`) around screenshots so they do not bleed into dark-mode feeds.
5. **No emoji in tweet copy** unless quoting terminal output (which also has no emoji). Exception: a single thread indicator emoji is acceptable (e.g., a small arrow).
6. **Numbers always included** when referencing performance.

---

## 12. Hackathon Submission Assets

### ETHGlobal Submission Page

**Project name:** Harvest

**Tagline (one line, under 100 characters):**
```
DeFi, for humans -- the first auto-compounding yield aggregator on World Chain
```
Character count: 79. Fits.

**Description (~250 words):**

```
World Chain has $42M in DeFi TVL and 25 million users -- but zero yield 
aggregators. No Beefy. No Yearn. Nothing. Users deposit into Morpho vaults 
and earn yield, but Merkl rewards pile up unclaimed. A thousand users making 
a thousand separate claim transactions, every cycle.

Harvest fixes this. It is the first yield aggregator on World Chain, built 
on a Beefy Finance fork (MIT licensed, battle-tested across 25+ chains). 
Users deposit USDC into a shared vault. An AI-powered agent -- built with 
AgentKit and x402 micropayments -- automatically claims Merkl rewards, swaps 
them via Uniswap V3, and redeposits into the Morpho vault. One transaction 
compounds yield for every depositor simultaneously.

What makes Harvest different: every depositor is cryptographically verified 
as a unique human. World ID (orb-level) gates direct deposits. AgentKit 
verifies that external agents are human-backed. No bots. No sybil farms. 
Every dollar in the vault traces back to a verified person.

The interface is a terminal. Green on black, monospace, command-driven. 
Type "deposit 50 usdc" and you are in. Type "agent status" and you see 
every harvest the agent has executed. It runs as a World Mini App inside 
World App, accessible to 40 million users without installing anything new.

Without Harvest, users earn 4.15% APY. With weekly auto-compounding, 
that becomes 4.23%. The difference compounds. And nobody has to do anything.

DeFi, for humans. Deposit. Forget. Earn.
```

Word count: ~230.

### Screenshots to Capture

Capture these four terminal screenshots for the submission page. Each should be a clean, full-screen capture of the terminal UI inside World App (or browser dev tools simulating mobile).

**Screenshot 1: Boot + Auth**
```
> Initializing Harvest v1.0...
> Connecting to World Chain (480)...
> World ID: VERIFIED (orb)
> Wallet: 0x1a2B...9fC4
> Session active. Type 'help' to begin.

> _
```
Purpose: Shows World ID verification, terminal aesthetic, live connection.

**Screenshot 2: Vaults**
```
> vaults

AVAILABLE VAULTS
  +------------+--------+----------+-------------+
  | Vault      | APY    | TVL      | Depositors  |
  +------------+--------+----------+-------------+
  | Re7 USDC   | 4.15%  | $125.0K  | 47          |
  +------------+--------+----------+-------------+

> _
```
Purpose: Shows vault data, table formatting, real numbers.

**Screenshot 3: Deposit + Portfolio**
```
> deposit 50 usdc
DEPOSIT 50.00 USDC -> Re7 USDC Vault
  TX: 0xabc...def (confirmed, block 84291)
  OK Deposited 50.00 USDC.

> portfolio
YOUR PORTFOLIO
  Total Value:  $50.00
  Earnings:     +$0.00

  +------------+------------+----------+--------+
  | Vault      | Deposited  | Value    | Earned |
  +------------+------------+----------+--------+
  | Re7 USDC   | 50.00      | $50.00   | +$0.00 |
  +------------+------------+----------+--------+

> _
```
Purpose: Shows the core flow -- deposit and verify position.

**Screenshot 4: Agent Status + Harvest**
```
> agent status
AGENT STATUS
  Strategy:     StrategyMorpho (Re7 USDC)
  AgentKit:     ACTIVE (human-backed, x402-enabled)
  Last harvest: 2h ago

  RECENT HARVESTS
  +------------------+----------+-----------+---------+
  | Time             | Claimed  | Compound  | Gas     |
  +------------------+----------+-----------+---------+
  | Apr 3, 14:22     | 42 WLD   | $38.14    | $0.002  |
  | Apr 3, 08:15     | 31 WLD   | $28.07    | $0.002  |
  +------------------+----------+-----------+---------+

> _
```
Purpose: Shows the agent at work -- the core innovation.

### Screenshot Specifications

| Property | Value |
|----------|-------|
| Resolution | 1290 x 2796 px (iPhone 15 Pro Max) or 1170 x 2532 px (iPhone 15 Pro) |
| Alternative | 1080 x 1920 for a general mobile screenshot |
| Background | Must be `#0a0a0a` with no visible browser chrome |
| Font rendering | Ensure JetBrains Mono is loaded before capture |
| Capture method | Use Chrome DevTools device emulation or actual iPhone screen recording |
| File format | PNG, sRGB |

For the submission page, crop screenshots to focus on the terminal content (remove status bar if not running in World App).

### Demo Video Thumbnail

Use **Screenshot 4 (Agent Status)** as the video thumbnail, with the logo and tagline overlaid:

```
+------------------------------------------------------------+
|  [Agent status terminal screenshot, slightly dimmed]       |
|                                                            |
|            > harvest_                                      |
|            DeFi, for humans.                               |
|                                                            |
|            ▶ (play button overlay, white, 80px, centered)  |
|                                                            |
+------------------------------------------------------------+
```

| Property | Value |
|----------|-------|
| Size | 1280 x 720 px (16:9) |
| Background | Screenshot at 60% opacity on `#0a0a0a` |
| Logo | JetBrains Mono Bold, 48px, `#00ff00` |
| Tagline | JetBrains Mono Regular, 28px, `#f5a623` |
| Play button | White circle (80px diameter, 30% opacity), white triangle (centered) |

### Team Section

If the submission page requires team member info:
- Individual photos not required for ETHGlobal
- If needed: casual hackathon photos, not headshots
- Team description format: `[Name] -- [Role] ([Key tech])` as shown in the one-pager
---

## 14. Asset Export Checklist

### Critical (must have for submission)

| Asset | Size | Status |
|-------|------|--------|
| App icon (Developer Portal) | 512x512 PNG | [x] |
| App icon (favicon) | 16x16, 32x32 ICO/PNG | [x] |
| App icon (small) | 64x64 PNG | [x] |
| Content card (World App Store) | 1035x720 PNG (@3x) | [x] |
| OG image | 1200x630 PNG | [x] |
| Screenshot 1: Boot + Auth | Mobile resolution PNG | [x] |
| Screenshot 2: Vaults | Mobile resolution PNG | [x] |
| Screenshot 3: Deposit + Portfolio | Mobile resolution PNG | [x] |
| Screenshot 4: Agent Status | Mobile resolution PNG | [x] |
| Demo video thumbnail | 1280x720 PNG | [x] |

### Important (should have for social launch)

| Asset | Size | Status |
|-------|------|--------|
| Twitter profile picture | 400x400 PNG | [x] |
| Twitter header image | 1500x500 PNG | [x] |
| Pinned tweet images (1-3) | 1200x675 PNG each | [x] |

### Nice to Have (if time permits)

| Asset | Size | Status |
|-------|------|--------|
| QR code business cards | 3.5x2 in, print file | [x] |
| Judge one-pager | Letter/A4, PDF | [x] |
| Laptop stickers | 3x1 in, print file | [x] |
| Architecture diagram (clean) | 1200x800 PNG | [x] |
| CRT scanline overlay (CSS) | Code snippet | [x] |

### File Naming Convention

```
harvest-icon-512.png
harvest-icon-128.png
harvest-icon-64.png
harvest-icon-32.png
harvest-icon-16.png
harvest-content-card-3x.png
harvest-og-image.png
harvest-screenshot-01-boot.png
harvest-screenshot-02-vaults.png
harvest-screenshot-03-deposit.png
harvest-screenshot-04-agent.png
harvest-twitter-header.png
harvest-thumb-demo.png
```

Store all assets in `/public/brand/` within the Next.js app, or `/assets/` at the repo root.

---

## Quick Reference Card

```
Brand:        Harvest
Tagline:      DeFi, for humans.
Subline:      Auto-compounding yield. Sybil-resistant. Human-verified.
Elevator:     The first yield vault where every depositor is
              cryptographically verified as a unique human.

Font:         JetBrains Mono (Bold 700, Regular 400)
Background:   #0a0a0a (always dark, never white)
Primary:      #00ff00 (terminal green)
Secondary:    #00aa00 (dim green)
Muted:        #666666 (borders, labels)
Warm accent:  #f5a623 (tagline, marketing CTAs only)
Soft white:   #e0e0e0 (marketing body text only)
Error:        #ff4444 (errors only, never decorative)

Logo:         > harvest_
Icon:         >H_ (green on dark)
Favicon:      > (green on dark, 16px)

Voice:        Precise. Brief. Log-formatted.
              Technical confidence + dry humor.
              Never hype. Always numbers.

Terminal:     Green text, dark bg, monospace, no emoji
Marketing:    Same palette + warm amber accent + larger type
```

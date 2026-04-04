import type { Config } from "tailwindcss";

/** Brand tokens + terminal UI; merged with Integrations landing (font-harvest, marquee) */
export default {
  content: [
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // Match existing terminal (#00ff41) so home page visuals stay consistent
        "terminal-green": "#00ff41",
        "terminal-dark": "#0a0a0a",
        "terminal-dim": "#00aa00",
        "error-red": "#ff4444",
        "warning-amber": "#ffaa00",
        "info-blue": "#4444ff",
        "muted-gray": "#666666",
        "deep-gray": "#1a1a1a",
        "human-amber": "#f5a623",
        "soft-white": "#e0e0e0",
        "warm-white": "#fafafa",
      },
      fontFamily: {
        harvest: [
          'var(--font-harvest-loaded, "JetBrains Mono")',
          '"Fira Code"',
          '"Courier New"',
          "monospace",
        ],
      },
      fontSize: {
        "harvest-h1": ["1.5rem", { lineHeight: "1.2" }],
        "harvest-h2": ["1.125rem", { lineHeight: "1.2" }],
        "harvest-h3": ["1rem", { lineHeight: "1.2" }],
        "harvest-body": ["0.875rem", { lineHeight: "1.5" }],
        "harvest-output": ["0.8125rem", { lineHeight: "1.6" }],
        "harvest-label": ["0.75rem", { lineHeight: "1.5" }],
        "harvest-shortcut": ["0.875rem", { lineHeight: "1.2" }],
        "harvest-hero": ["4.5rem", { lineHeight: "1.2" }],
        "harvest-tagline": ["2rem", { lineHeight: "1.5" }],
        "harvest-section": ["1.75rem", { lineHeight: "1.2" }],
        "harvest-marketing-body": ["1.125rem", { lineHeight: "1.5" }],
        "harvest-stat": ["3rem", { lineHeight: "1.2" }],
        "harvest-stat-label": ["1rem", { lineHeight: "1.5" }],
        "harvest-cta": ["1.125rem", { lineHeight: "1.2" }],
        "harvest-footer": ["0.875rem", { lineHeight: "1.5" }],
      },
      lineHeight: {
        "harvest-body": "1.5",
        "harvest-heading": "1.2",
        "harvest-terminal": "1.6",
      },
      borderRadius: {
        harvest: "4px",
      },
      keyframes: {
        "harvest-cursor-blink": {
          "0%, 49%": { opacity: "1" },
          "50%, 100%": { opacity: "0" },
        },
        marquee: {
          "0%": { transform: "translateX(0)" },
          "100%": { transform: "translateX(-50%)" },
        },
        "marquee-reverse": {
          "0%": { transform: "translateX(-50%)" },
          "100%": { transform: "translateX(0)" },
        },
      },
      animation: {
        "harvest-cursor-blink":
          "harvest-cursor-blink 1060ms steps(1, end) infinite",
        marquee: "marquee 30s linear infinite",
        "marquee-reverse": "marquee-reverse 30s linear infinite",
        "marquee-fast": "marquee 15s linear infinite",
        "marquee-fast-reverse": "marquee-reverse 18s linear infinite",
      },
    },
  },
  plugins: [],
} satisfies Config;

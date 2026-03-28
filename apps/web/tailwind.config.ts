import type { Config } from "tailwindcss";
import animate from "tailwindcss-animate";

/**
 * Phase 1 — Aegis Risk-inspired design system.
 *
 * Palette sourced from the Relief Registry / Aegis Risk reference screens:
 *   warm cream backgrounds, muted olive-charcoal text, terracotta-orange
 *   secondary/accent, scholarly blue tertiary.
 *
 * Typography: Newsreader (serif headlines), Inter (body/labels).
 */
export default {
  darkMode: ["class"],
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        /* --- surface / background layers --- */
        background: "var(--background)",
        foreground: "var(--foreground)",
        card: "var(--card)",
        "card-foreground": "var(--card-foreground)",
        muted: "var(--muted)",
        "muted-foreground": "var(--muted-foreground)",
        border: "var(--border)",
        primary: "var(--primary)",
        "primary-foreground": "var(--primary-foreground)",
        accent: "var(--accent)",
        "accent-foreground": "var(--accent-foreground)",
        ring: "var(--ring)",

        /* --- Aegis extended palette (direct hex for convenience) --- */
        surface: {
          DEFAULT: "#fffcf7",
          dim: "#e4e3d7",
          container: "#f6f4ec",
          "container-low": "#fcf9f3",
          "container-high": "#f0eee5",
          "container-highest": "#eae9de",
          "container-lowest": "#ffffff",
        },
        "on-surface": "#373831",
        "on-surface-variant": "#64655d",
        secondary: {
          DEFAULT: "#a14b2f",
          dim: "#914024",
          container: "#ffdbd0",
        },
        tertiary: {
          DEFAULT: "#516583",
          dim: "#455976",
          container: "#c7dbfe",
        },
        outline: {
          DEFAULT: "#818178",
          variant: "#babab0",
        },
        error: {
          DEFAULT: "#a64542",
          container: "#fe8983",
        },
      },
      borderRadius: {
        DEFAULT: "0.125rem",
        sm: "0.25rem",
        md: "0.5rem",
        lg: "0.75rem",
        xl: "1rem",
      },
      fontFamily: {
        headline: ["Newsreader", "serif"],
        body: ["Inter", "system-ui", "sans-serif"],
        sans: ["Inter", "system-ui", "sans-serif"],
      },
      boxShadow: {
        spotlight: "0 20px 50px rgba(55, 56, 49, 0.06)",
        glass: "0 4px 24px rgba(55, 56, 49, 0.08)",
      },
    },
  },
  plugins: [animate],
} satisfies Config;

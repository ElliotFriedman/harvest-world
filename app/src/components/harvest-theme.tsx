import type { ReactNode } from "react";

type Surface = "terminal" | "elevated" | "marketing";

const surfaceClass: Record<Surface, string> = {
  /** Default app shell — §3 primary palette */
  terminal: "bg-terminal-dark text-terminal-green",
  /** Cards / shortcut bar — deep gray on dark */
  elevated: "bg-deep-gray text-terminal-green border border-muted-gray",
  /** Pre-auth landing layer — warm text colors allowed */
  marketing: "bg-terminal-dark text-soft-white",
};

type HarvestThemeProps = {
  children: ReactNode;
  /** Visual layer; default matches post-auth terminal */
  surface?: Surface;
  className?: string;
};

/**
 * Semantic layout wrapper. Prefer Tailwind utilities from @theme in globals.css.
 */
export function HarvestTheme({
  children,
  surface = "terminal",
  className = "",
}: HarvestThemeProps) {
  return (
    <div className={`min-h-dvh font-harvest antialiased ${surfaceClass[surface]} ${className}`}>
      {children}
    </div>
  );
}

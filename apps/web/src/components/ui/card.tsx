import type { HTMLAttributes } from "react";

import { cn } from "@/lib/utils";

/**
 * Phase 1 — Aegis-styled card component.
 * Subtle shadow, warm background, refined rounded corners.
 */
export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-xl border border-outline-variant/10 bg-surface-container-lowest p-6 shadow-spotlight",
        className,
      )}
      {...props}
    />
  );
}

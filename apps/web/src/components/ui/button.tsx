import { cva, type VariantProps } from "class-variance-authority";
import type { ButtonHTMLAttributes } from "react";

import { cn } from "@/lib/utils";

/**
 * Phase 1 — Aegis-styled button component.
 * Matches the Relief Registry design: muted charcoal primary, terracotta secondary,
 * refined rounded shapes with uppercase tracking on some variants.
 */
const buttonVariants = cva(
  "inline-flex items-center justify-center rounded-md text-sm font-medium transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 active:scale-[0.98]",
  {
    variants: {
      variant: {
        default:
          "bg-gradient-to-br from-[#5f5e5c] to-[#535250] px-6 py-3 text-[#faf7f3] shadow-md hover:opacity-95 tracking-widest uppercase text-xs font-semibold",
        secondary:
          "bg-[#a14b2f] px-6 py-3 text-white shadow-md hover:bg-[#914024] tracking-widest uppercase text-xs font-semibold",
        outline:
          "border border-outline-variant bg-surface-container-lowest px-6 py-3 text-[#5f5e5c] hover:bg-surface-container-high",
        ghost:
          "px-4 py-2 text-on-surface-variant hover:bg-surface-container hover:text-on-surface",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
);

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof buttonVariants>;

export function Button({ className, variant, ...props }: ButtonProps) {
  return <button className={cn(buttonVariants({ className, variant }))} {...props} />;
}

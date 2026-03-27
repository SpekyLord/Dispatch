import type { HTMLAttributes } from "react";

import { cn } from "@/lib/utils";

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-[1.5rem] border border-border/80 bg-card/90 p-6 text-card-foreground shadow-spotlight backdrop-blur",
        className,
      )}
      {...props}
    />
  );
}

import type { ReactNode } from "react";
import { Link, NavLink } from "react-router-dom";

import { Button } from "@/components/ui/button";
import { useSessionStore } from "@/lib/auth/session-store";
import { cn } from "@/lib/utils";

type AppShellProps = {
  title: string;
  subtitle: string;
  children: ReactNode;
};

const navItems = [
  { to: "/", label: "Overview" },
  { to: "/feed", label: "Feed" },
  { to: "/profile", label: "Profile" },
];

export function AppShell({ title, subtitle, children }: AppShellProps) {
  const signOut = useSessionStore((state) => state.signOut);
  const user = useSessionStore((state) => state.user);

  return (
    <div className="min-h-screen">
      <header className="border-b border-border/70 bg-white/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <div>
            <Link className="text-lg font-semibold tracking-tight" to="/">
              Dispatch
            </Link>
            <p className="text-sm text-muted-foreground">{subtitle}</p>
          </div>
          <nav className="hidden items-center gap-2 md:flex">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                className={({ isActive }) =>
                  cn(
                    "rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground",
                    isActive && "bg-muted text-foreground",
                  )
                }
                to={item.to}
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex items-center gap-3">
            {user ? (
              <>
                <span className="rounded-full bg-accent/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-accent">
                  {user.role}
                </span>
                <Button onClick={signOut} variant="outline">
                  Sign out
                </Button>
              </>
            ) : (
              <Button onClick={() => undefined} variant="ghost">
                Phase 0 shell
              </Button>
            )}
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-6 py-10">
        <div className="mb-8">
          <p className="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
            Phase 0 foundation
          </p>
          <h1 className="mt-2 text-4xl font-semibold tracking-tight">{title}</h1>
        </div>
        {children}
      </main>
    </div>
  );
}

import type { ReactNode } from "react";
import { Link, NavLink, useNavigate } from "react-router-dom";

import { Button } from "@/components/ui/button";
import { useSessionStore } from "@/lib/auth/session-store";
import { apiRequest } from "@/lib/api/client";
import { cn } from "@/lib/utils";

type AppShellProps = {
  title: string;
  subtitle: string;
  children: ReactNode;
};

const roleNavItems: Record<string, { to: string; label: string }[]> = {
  citizen: [
    { to: "/citizen", label: "My Reports" },
    { to: "/feed", label: "Feed" },
    { to: "/profile", label: "Profile" },
  ],
  department: [
    { to: "/department", label: "Dashboard" },
    { to: "/feed", label: "Feed" },
    { to: "/profile", label: "Profile" },
  ],
  municipality: [
    { to: "/municipality", label: "Overview" },
    { to: "/municipality/verification", label: "Verification" },
    { to: "/municipality/departments", label: "Departments" },
    { to: "/profile", label: "Profile" },
  ],
};

const defaultNavItems = [
  { to: "/", label: "Home" },
  { to: "/feed", label: "Feed" },
];

export function AppShell({ title, subtitle, children }: AppShellProps) {
  const navigate = useNavigate();
  const signOut = useSessionStore((s) => s.signOut);
  const user = useSessionStore((s) => s.user);

  const navItems = user ? (roleNavItems[user.role] ?? defaultNavItems) : defaultNavItems;

  async function handleSignOut() {
    try {
      await apiRequest("/api/auth/logout", { method: "POST" });
    } catch {
      // sign out locally even if API call fails
    }
    signOut();
    navigate("/");
  }

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
                <Button onClick={handleSignOut} variant="outline">
                  Sign out
                </Button>
              </>
            ) : (
              <Link to="/auth/login">
                <Button variant="ghost">Sign in</Button>
              </Link>
            )}
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-6 py-10">
        <div className="mb-8">
          <h1 className="text-4xl font-semibold tracking-tight">{title}</h1>
        </div>
        {children}
      </main>
    </div>
  );
}

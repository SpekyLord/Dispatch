import type { ReactNode } from "react";
import { Link, NavLink, useNavigate } from "react-router-dom";

import { useSessionStore } from "@/lib/auth/session-store";
import { apiRequest } from "@/lib/api/client";
import { cn } from "@/lib/utils";

/**
 * Phase 1 — Aegis-styled application shell.
 * Fixed top nav bar + collapsible side nav (desktop only) matching the
 * Relief Registry / Aegis Risk dashboard layout.
 */

type AppShellProps = {
  title: string;
  subtitle: string;
  children: ReactNode;
};

/* Navigation config per role — icon uses Material Symbols name */
type NavItem = { to: string; label: string; icon: string };

const roleNavItems: Record<string, NavItem[]> = {
  citizen: [
    { to: "/citizen", label: "My Reports", icon: "description" },
    { to: "/citizen/report/new", label: "New Report", icon: "add_circle" },
    { to: "/feed", label: "Feed", icon: "newspaper" },
    { to: "/citizen/news-feed", label: "News Feed", icon: "campaign" },
    { to: "/notifications", label: "Notifications", icon: "notifications" },
    { to: "/profile", label: "Profile", icon: "person" },
  ],
  department: [
    { to: "/department", label: "Dashboard", icon: "dashboard" },
    { to: "/department/reports", label: "Incident Board", icon: "assignment" },
    { to: "/feed", label: "Feed", icon: "newspaper" },
    { to: "/department/news-feed", label: "News Feed", icon: "campaign" },
    { to: "/notifications", label: "Notifications", icon: "notifications" },
    { to: "/department/profile", label: "Profile", icon: "person" },
  ],
  municipality: [
    { to: "/municipality", label: "Overview", icon: "dashboard" },
    { to: "/municipality/reports/escalated", label: "Escalations", icon: "crisis_alert" },
    { to: "/municipality/verification", label: "Verification", icon: "verified_user" },
    { to: "/municipality/departments", label: "Departments", icon: "domain" },
    { to: "/municipality/news-feed", label: "News Feed", icon: "campaign" },
    { to: "/notifications", label: "Notifications", icon: "notifications" },
    { to: "/profile", label: "Profile", icon: "person" },
  ],
};

const roleSidebarTitle: Record<string, { title: string; subtitle: string }> = {
  citizen: { title: "Citizen Hub", subtitle: "Incident Reporting" },
  department: { title: "Dept. Ops", subtitle: "Response Command" },
  municipality: { title: "Municipal Admin", subtitle: "Regional Oversight" },
};

export function AppShell({ title, subtitle, children }: AppShellProps) {
  const navigate = useNavigate();
  const signOut = useSessionStore((s) => s.signOut);
  const user = useSessionStore((s) => s.user);

  const navItems = user ? (roleNavItems[user.role] ?? []) : [];
  const sidebarMeta = user ? (roleSidebarTitle[user.role] ?? { title: "Dispatch", subtitle: "" }) : { title: "Dispatch", subtitle: "" };

  async function handleSignOut() {
    try {
      await apiRequest("/api/auth/logout", { method: "POST" });
    } catch {
      /* sign out locally even if API call fails */
    }
    signOut();
    navigate("/");
  }

  return (
    <div className="min-h-screen bg-surface">
      {/* ── Top Nav Bar ── */}
      <header className="fixed top-0 left-0 right-0 z-50 bg-[#fffcf7] flex justify-between items-center w-full px-8 py-4">
        <div className="flex items-center gap-8">
          <Link to="/" className="text-2xl font-headline italic text-on-surface">
            Dispatch
          </Link>
          {/* Top nav links — hidden on mobile */}
          <nav className="hide-scrollbar hidden max-w-[52vw] items-center gap-4 overflow-x-auto whitespace-nowrap md:flex">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  cn(
                    "flex-shrink-0 text-on-surface-variant hover:text-on-surface transition-colors duration-300 text-sm font-medium",
                    isActive && "text-[#D97757] font-semibold border-b-2 border-[#D97757] pb-1",
                  )
                }
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
        </div>
        <div className="flex items-center gap-4">
          {user ? (
            <>
              <span className="hidden sm:inline-block text-xs font-bold uppercase tracking-widest text-on-surface-variant">
                {user.full_name ?? user.email}
              </span>
              <button
                onClick={handleSignOut}
                className="p-2 hover:bg-surface-container-high rounded-lg transition-colors"
                title="Sign out"
              >
                <span className="material-symbols-outlined text-on-surface-variant">logout</span>
              </button>
              <button className="p-2 hover:bg-surface-container-high rounded-lg transition-colors">
                <span className="material-symbols-outlined text-on-surface-variant">account_circle</span>
              </button>
            </>
          ) : (
            <Link
              to="/auth/login"
              className="text-sm font-medium text-on-surface-variant hover:text-on-surface transition-colors"
            >
              Sign in
            </Link>
          )}
        </div>
      </header>

      {/* ── Side Nav Bar (desktop only) ── */}
      {user && (
        <aside className="hidden lg:flex flex-col h-screen fixed left-0 top-0 pt-24 pb-8 px-4 border-r border-outline-variant/15 bg-surface-container w-64 z-40">
          <div className="mb-8 px-4">
            <h2 className="font-headline text-xl text-on-surface">{sidebarMeta.title}</h2>
            <p className="text-xs text-on-surface-variant font-medium uppercase tracking-widest mt-1">
              {sidebarMeta.subtitle}
            </p>
          </div>

          <nav className="flex-1 flex flex-col gap-1">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === "/citizen" || item.to === "/department" || item.to === "/municipality"}
                className={({ isActive }) =>
                  cn(
                    "flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-all",
                    isActive
                      ? "bg-surface-container-lowest text-[#D97757] shadow-sm"
                      : "text-on-surface-variant hover:bg-surface-container-low hover:text-on-surface",
                  )
                }
              >
                <span className="material-symbols-outlined text-[20px]">{item.icon}</span>
                {item.label}
              </NavLink>
            ))}
          </nav>

          <div className="mt-auto border-t border-outline-variant/10 pt-4">
            <button
              onClick={handleSignOut}
              className="flex items-center gap-3 text-on-surface-variant px-4 py-3 hover:bg-surface-container-low rounded-lg transition-all w-full text-sm font-medium"
            >
              <span className="material-symbols-outlined text-[20px]">logout</span>
              Sign out
            </button>
          </div>
        </aside>
      )}

      {/* ── Main Content ── */}
      <main className={cn("pt-24 min-h-screen", user && "lg:pl-64")}>
        <div className="max-w-[1200px] mx-auto p-8">
          {/* Page header */}
          <section className="mb-10">
            <p className="text-xs font-bold uppercase tracking-widest text-[#D97757] mb-2">
              {subtitle}
            </p>
            <h1 className="font-headline text-4xl lg:text-5xl font-bold tracking-tight text-on-surface">
              {title}
            </h1>
          </section>
          {children}
        </div>
      </main>

      {/* ── Mobile Bottom Nav ── */}
      {user && (
        <nav className="hide-scrollbar lg:hidden fixed bottom-0 left-0 right-0 glass-panel border-t border-outline-variant/10 flex items-center gap-4 overflow-x-auto px-4 py-3 z-50">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) =>
                cn(
                  "flex min-w-[72px] flex-col items-center gap-1",
                  isActive ? "text-[#D97757]" : "text-on-surface-variant",
                )
              }
            >
              <span className="material-symbols-outlined text-[20px]">{item.icon}</span>
              <span className="text-[10px] font-bold uppercase tracking-tighter">{item.label}</span>
            </NavLink>
          ))}
        </nav>
      )}
    </div>
  );
}

import { type ReactNode, useState } from "react";
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
const popupPanelShadowClassName =
  "shadow-[rgba(0,0,0,0.4)_0px_2px_4px,rgba(0,0,0,0.3)_0px_7px_13px_-3px,rgba(0,0,0,0.2)_0px_-3px_0px_inset]";

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
    { to: "/department/assessments", label: "Assessments", icon: "assessment" },
    { to: "/feed", label: "Feed", icon: "newspaper" },
    { to: "/department/news-feed", label: "News Feed", icon: "campaign" },
    { to: "/notifications", label: "Notifications", icon: "notifications" },
    { to: "/department/profile", label: "Profile", icon: "person" },
  ],
  municipality: [
    { to: "/municipality", label: "Overview", icon: "dashboard" },
    { to: "/municipality/reports", label: "Reports", icon: "summarize" },
    { to: "/municipality/analytics", label: "Analytics", icon: "analytics" },
    { to: "/municipality/assessments", label: "Assessments", icon: "assessment" },
    { to: "/municipality/reports/escalated", label: "Escalations", icon: "crisis_alert" },
    { to: "/municipality/verification", label: "Verification", icon: "verified_user" },
    { to: "/municipality/departments", label: "Departments", icon: "domain" },
    { to: "/municipality/mesh", label: "Mesh & SAR", icon: "cell_tower" },
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
  const department = useSessionStore((s) => s.department);
  const [isSignOutConfirmOpen, setIsSignOutConfirmOpen] = useState(false);
  const [isSigningOut, setIsSigningOut] = useState(false);

  const navItems = user ? (roleNavItems[user.role] ?? []) : [];
  const desktopNavItems = navItems.filter((item) => item.label !== "Profile");
  const sidebarMeta = user ? (roleSidebarTitle[user.role] ?? { title: "Dispatch", subtitle: "" }) : { title: "Dispatch", subtitle: "" };
  const profileRoute = user?.role === "department" ? "/department/profile" : "/profile";
  const profileName =
    user?.role === "department"
      ? department?.name ?? user?.full_name ?? user?.email ?? "Dispatch User"
      : user?.full_name ?? user?.email ?? "Dispatch User";
  const profileHandleSource =
    user?.role === "department"
      ? department?.name ?? user?.full_name ?? user?.email ?? "dispatch"
      : user?.full_name ?? user?.email ?? "dispatch";
  const profileHandle = `@${profileHandleSource
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "")
    .slice(0, 18) || "dispatch"}`;
  const profileImage = department?.profile_picture || department?.profile_photo || user?.avatar_url;
  const profileInitial = (profileName.trim().charAt(0) || "D").toUpperCase();

  function openSignOutConfirm() {
    if (!isSigningOut) {
      setIsSignOutConfirmOpen(true);
    }
  }

  function closeSignOutConfirm() {
    if (!isSigningOut) {
      setIsSignOutConfirmOpen(false);
    }
  }

  async function handleSignOut() {
    if (isSigningOut) {
      return;
    }

    setIsSigningOut(true);
    try {
      await apiRequest("/api/auth/logout", { method: "POST" });
    } catch {
      /* sign out locally even if API call fails */
    }
    setIsSignOutConfirmOpen(false);
    signOut();
    navigate("/");
  }

  return (
    <div className="min-h-screen bg-surface">
      {/* ── Top Nav Bar ── */}
      <header className="fixed top-0 left-0 right-0 z-50 flex w-full items-center justify-between bg-gradient-to-r from-[#d98d63] via-[#bf6e49] to-[#a86446] px-8 py-4">
        <div className="flex items-center">
          <Link to="/" className="text-2xl font-headline italic text-white">
            Dispatch
          </Link>
        </div>
        <div className="flex items-center gap-4">
          {user ? (
            <>
              <span className="hidden sm:inline-block text-xs font-bold uppercase tracking-widest text-white/80">
                {user.full_name ?? user.email}
              </span>
              <button
                onClick={openSignOutConfirm}
                className="rounded-lg p-2 transition-colors hover:bg-white/10"
                title="Sign out"
              >
                <span className="material-symbols-outlined text-white/85">logout</span>
              </button>
              <button className="rounded-lg p-2 transition-colors hover:bg-white/10">
                <span className="material-symbols-outlined text-white/85">account_circle</span>
              </button>
            </>
          ) : (
            <Link
              to="/auth/login"
              className="text-sm font-medium text-white/85 transition-colors hover:text-white"
            >
              Sign in
            </Link>
          )}
        </div>
      </header>

      {/* ── Side Nav Bar (desktop only) ── */}
      {user && (
        <aside className="hidden">
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
              onClick={openSignOutConfirm}
              className="flex items-center gap-3 text-on-surface-variant px-4 py-3 hover:bg-surface-container-low rounded-lg transition-all w-full text-sm font-medium"
            >
              <span className="material-symbols-outlined text-[20px]">logout</span>
              Sign out
            </button>
          </div>
        </aside>
      )}

      {/* ── Main Content ── */}
      <main className="pt-24 min-h-screen">
        <div className={cn("mx-auto p-8", user ? "max-w-[1500px] lg:pl-[21rem]" : "max-w-[1200px]")}>
          {user && (
            <aside className="hidden lg:fixed lg:left-[max(2rem,calc(50%-750px+2rem))] lg:top-32 lg:flex lg:h-[calc(100vh-10rem)] lg:w-[18rem] lg:flex-col lg:border-r lg:border-outline-variant/15 lg:bg-surface lg:px-6 lg:pb-8 lg:pt-6">
              <div className="mb-8 px-4">
                <h2 className="font-headline text-3xl italic text-on-surface">Dispatch</h2>
                <p className="mt-1 text-xs font-medium uppercase tracking-widest text-on-surface-variant">
                  {sidebarMeta.subtitle}
                </p>
              </div>

              <nav className="flex-1 overflow-y-auto pr-2 flex flex-col gap-1">
                {desktopNavItems.map((item) => (
                  <NavLink
                    key={item.to}
                    to={item.to}
                    end={item.to === "/citizen" || item.to === "/department" || item.to === "/municipality"}
                    className={({ isActive }) =>
                      cn(
                        "flex items-center gap-4 px-4 py-3.5 rounded-xl text-lg font-medium transition-all duration-200",
                        isActive
                          ? "bg-surface-container-lowest text-[#D97757] shadow-sm"
                          : "text-on-surface-variant hover:bg-[#d98d63]/18 hover:text-[#a86446] hover:shadow-[0_10px_24px_rgba(168,100,70,0.12)]",
                      )
                    }
                  >
                    <span className="material-symbols-outlined text-[26px]">{item.icon}</span>
                    {item.label}
                  </NavLink>
                ))}
              </nav>

              <div className="mt-auto border-t border-outline-variant/10 pt-5">
                <NavLink
                  to={profileRoute}
                  className={({ isActive }) =>
                    cn(
                      "flex w-full items-center gap-4 rounded-2xl px-4 py-3 transition-all duration-200",
                      isActive
                        ? "bg-surface-container-lowest shadow-sm"
                        : "hover:bg-[#d98d63]/16 hover:shadow-[0_10px_24px_rgba(168,100,70,0.12)]",
                    )
                  }
                >
                  {profileImage ? (
                    <img
                      src={profileImage}
                      alt={profileName}
                      className="h-14 w-14 rounded-full object-cover ring-1 ring-outline-variant/20"
                    />
                  ) : (
                    <div className="flex h-14 w-14 items-center justify-center rounded-full bg-[#d98d63]/20 text-lg font-semibold text-[#a86446] ring-1 ring-outline-variant/20">
                      {profileInitial}
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-base font-semibold text-on-surface">{profileName}</p>
                    <p className="truncate text-sm text-on-surface-variant">{profileHandle}</p>
                  </div>
                  <button
                    type="button"
                    onClick={(event) => {
                      event.preventDefault();
                      event.stopPropagation();
                      openSignOutConfirm();
                    }}
                    className="flex h-11 w-11 items-center justify-center rounded-full text-on-surface-variant transition-all duration-200 hover:bg-[#d98d63]/22 hover:text-[#a86446]"
                    title="Sign out"
                  >
                    <span className="material-symbols-outlined text-[24px]">logout</span>
                  </button>
                </NavLink>
              </div>
            </aside>
          )}
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

      {isSignOutConfirmOpen && (
        <div className="fixed inset-0 z-[75] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div className={`w-full max-w-md rounded-[28px] border border-[#efd8d0] bg-[#fff8f3] p-6 ${popupPanelShadowClassName}`}>
            <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
              Sign out
            </p>
            <h3 className="mt-3 text-2xl text-on-surface">Are you sure you want to sign out?</h3>
            <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">
              You&apos;ll be signed out of Dispatch and returned to the home page.
            </p>
            <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <button
                type="button"
                className="rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-5 py-3 text-sm font-semibold text-[#6f625b] transition-colors hover:bg-[#f2e7de] disabled:cursor-not-allowed disabled:opacity-70"
                onClick={closeSignOutConfirm}
                disabled={isSigningOut}
              >
                Cancel
              </button>
              <button
                type="button"
                className="rounded-full bg-[#a14b2f] px-5 py-3 text-sm font-semibold text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-70"
                onClick={() => void handleSignOut()}
                disabled={isSigningOut}
              >
                {isSigningOut ? "Signing out..." : "Sign out"}
              </button>
            </div>
          </div>
        </div>
      )}

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

import type { ReactNode } from "react";
import { Link, NavLink, useNavigate } from "react-router-dom";

import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { useLocale } from "@/lib/i18n/locale-context";
import type { MessageKey } from "@/lib/i18n/messages";
import { cn } from "@/lib/utils";

type AppShellProps = {
  title: string;
  subtitle: string;
  children: ReactNode;
};

type NavItem = {
  to: string;
  labelKey: MessageKey;
  icon: string;
};

const roleNavItems: Record<string, NavItem[]> = {
  citizen: [
    { to: "/citizen", labelKey: "nav.myReports", icon: "description" },
    { to: "/citizen/report/new", labelKey: "nav.newReport", icon: "add_circle" },
    { to: "/feed", labelKey: "nav.feed", icon: "newspaper" },
    { to: "/citizen/news-feed", labelKey: "nav.newsFeed", icon: "campaign" },
    { to: "/notifications", labelKey: "nav.notifications", icon: "notifications" },
    { to: "/profile", labelKey: "nav.profile", icon: "person" },
  ],
  department: [
    { to: "/department", labelKey: "nav.dashboard", icon: "dashboard" },
    { to: "/department/reports", labelKey: "nav.incidentBoard", icon: "assignment" },
    { to: "/department/assessments", labelKey: "nav.assessments", icon: "assessment" },
    { to: "/feed", labelKey: "nav.feed", icon: "newspaper" },
    { to: "/department/news-feed", labelKey: "nav.newsFeed", icon: "campaign" },
    { to: "/notifications", labelKey: "nav.notifications", icon: "notifications" },
    { to: "/department/profile", labelKey: "nav.profile", icon: "person" },
  ],
  municipality: [
    { to: "/municipality", labelKey: "nav.overview", icon: "dashboard" },
    { to: "/municipality/reports", labelKey: "nav.reports", icon: "summarize" },
    { to: "/municipality/analytics", labelKey: "nav.analytics", icon: "analytics" },
    { to: "/municipality/assessments", labelKey: "nav.assessments", icon: "assessment" },
    {
      to: "/municipality/reports/escalated",
      labelKey: "nav.escalations",
      icon: "crisis_alert",
    },
    {
      to: "/municipality/verification",
      labelKey: "nav.verification",
      icon: "verified_user",
    },
    { to: "/municipality/departments", labelKey: "nav.departments", icon: "domain" },
    { to: "/municipality/mesh", labelKey: "nav.meshSar", icon: "cell_tower" },
    { to: "/municipality/news-feed", labelKey: "nav.newsFeed", icon: "campaign" },
    { to: "/notifications", labelKey: "nav.notifications", icon: "notifications" },
    { to: "/profile", labelKey: "nav.profile", icon: "person" },
  ],
};

const roleSidebarTitle: Record<
  string,
  { titleKey: MessageKey; subtitleKey: MessageKey }
> = {
  citizen: {
    titleKey: "sidebar.citizen.title",
    subtitleKey: "sidebar.citizen.subtitle",
  },
  department: {
    titleKey: "sidebar.department.title",
    subtitleKey: "sidebar.department.subtitle",
  },
  municipality: {
    titleKey: "sidebar.municipality.title",
    subtitleKey: "sidebar.municipality.subtitle",
  },
};

export function AppShell({ title, subtitle, children }: AppShellProps) {
  const navigate = useNavigate();
  const signOut = useSessionStore((state) => state.signOut);
  const user = useSessionStore((state) => state.user);
  const { locale, setLocale, t } = useLocale();

  const navItems = user
    ? (roleNavItems[user.role] ?? []).map((item) => ({
        ...item,
        label: t(item.labelKey),
      }))
    : [];

  const sidebarMeta = user
    ? (() => {
        const config = roleSidebarTitle[user.role];
        if (!config) {
          return { title: "Dispatch", subtitle: "" };
        }
        return {
          title: t(config.titleKey),
          subtitle: t(config.subtitleKey),
        };
      })()
    : { title: "Dispatch", subtitle: "" };

  async function handleSignOut() {
    try {
      await apiRequest("/api/auth/logout", { method: "POST" });
    } catch {
      // Sign out locally even if the API call fails.
    }

    signOut();
    navigate("/");
  }

  return (
    <div className="min-h-screen bg-surface">
      <header className="fixed left-0 right-0 top-0 z-50 flex w-full items-center justify-between bg-[#fffcf7] px-8 py-4">
        <div className="flex items-center gap-8">
          <Link className="text-2xl font-headline italic text-on-surface" to="/">
            Dispatch
          </Link>

          <nav className="hide-scrollbar hidden max-w-[52vw] items-center gap-4 overflow-x-auto whitespace-nowrap md:flex">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                className={({ isActive }) =>
                  cn(
                    "flex-shrink-0 text-sm font-medium text-on-surface-variant transition-colors duration-300 hover:text-on-surface",
                    isActive &&
                      "border-b-2 border-[#D97757] pb-1 font-semibold text-[#D97757]",
                  )
                }
                to={item.to}
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
        </div>

        <div className="flex items-center gap-4">
          <div
            aria-label={t("shell.language")}
            className="hidden items-center gap-1 rounded-full border border-outline-variant/20 bg-surface px-1 py-1 sm:flex"
            role="group"
          >
            {(["en", "fil"] as const).map((option) => (
              <button
                key={option}
                aria-pressed={locale === option}
                className={cn(
                  "rounded-full px-3 py-1 text-xs font-bold uppercase tracking-widest transition-colors",
                  locale === option
                    ? "bg-[#D97757] text-white"
                    : "text-on-surface-variant hover:bg-surface-container-high",
                )}
                onClick={() => setLocale(option)}
                type="button"
              >
                {option === "en" ? t("shell.english") : t("shell.filipino")}
              </button>
            ))}
          </div>

          {user ? (
            <>
              <span className="hidden text-xs font-bold uppercase tracking-widest text-on-surface-variant sm:inline-block">
                {user.full_name ?? user.email}
              </span>
              <button
                className="rounded-lg p-2 transition-colors hover:bg-surface-container-high"
                onClick={handleSignOut}
                title={t("shell.signOut")}
                type="button"
              >
                <span className="material-symbols-outlined text-on-surface-variant">
                  logout
                </span>
              </button>
              <button
                className="rounded-lg p-2 transition-colors hover:bg-surface-container-high"
                type="button"
              >
                <span className="material-symbols-outlined text-on-surface-variant">
                  account_circle
                </span>
              </button>
            </>
          ) : (
            <Link
              className="text-sm font-medium text-on-surface-variant transition-colors hover:text-on-surface"
              to="/auth/login"
            >
              {t("shell.signIn")}
            </Link>
          )}
        </div>
      </header>

      {user && (
        <aside className="fixed left-0 top-0 z-40 hidden h-screen w-64 flex-col border-r border-outline-variant/15 bg-surface-container px-4 pb-8 pt-24 lg:flex">
          <div className="mb-8 px-4">
            <h2 className="font-headline text-xl text-on-surface">
              {sidebarMeta.title}
            </h2>
            <p className="mt-1 text-xs font-medium uppercase tracking-widest text-on-surface-variant">
              {sidebarMeta.subtitle}
            </p>
          </div>

          <nav className="flex flex-1 flex-col gap-1">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                className={({ isActive }) =>
                  cn(
                    "flex items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium transition-all",
                    isActive
                      ? "bg-surface-container-lowest text-[#D97757] shadow-sm"
                      : "text-on-surface-variant hover:bg-surface-container-low hover:text-on-surface",
                  )
                }
                end={
                  item.to === "/citizen" ||
                  item.to === "/department" ||
                  item.to === "/municipality"
                }
                to={item.to}
              >
                <span className="material-symbols-outlined text-[20px]">
                  {item.icon}
                </span>
                {item.label}
              </NavLink>
            ))}
          </nav>

          <div className="mt-auto border-t border-outline-variant/10 pt-4">
            <button
              className="flex w-full items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium text-on-surface-variant transition-all hover:bg-surface-container-low"
              onClick={handleSignOut}
              type="button"
            >
              <span className="material-symbols-outlined text-[20px]">
                logout
              </span>
              {t("shell.signOut")}
            </button>
          </div>
        </aside>
      )}

      <main className={cn("min-h-screen pt-24", user && "lg:pl-64")}>
        <div className="mx-auto max-w-[1200px] p-8">
          <section className="mb-10">
            <p className="mb-2 text-xs font-bold uppercase tracking-widest text-[#D97757]">
              {subtitle}
            </p>
            <h1 className="font-headline text-4xl font-bold tracking-tight text-on-surface lg:text-5xl">
              {title}
            </h1>
          </section>
          {children}
        </div>
      </main>

      {user && (
        <nav className="hide-scrollbar glass-panel fixed bottom-0 left-0 right-0 z-50 flex items-center gap-4 overflow-x-auto border-t border-outline-variant/10 px-4 py-3 lg:hidden">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              className={({ isActive }) =>
                cn(
                  "flex min-w-[72px] flex-col items-center gap-1",
                  isActive ? "text-[#D97757]" : "text-on-surface-variant",
                )
              }
              to={item.to}
            >
              <span className="material-symbols-outlined text-[20px]">
                {item.icon}
              </span>
              <span className="text-[10px] font-bold uppercase tracking-tighter">
                {item.label}
              </span>
            </NavLink>
          ))}
        </nav>
      )}
    </div>
  );
}

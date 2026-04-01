import { type ReactNode, useState } from "react";
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

const popupPanelShadowClassName =
  "shadow-[rgba(0,0,0,0.4)_0px_2px_4px,rgba(0,0,0,0.3)_0px_7px_13px_-3px,rgba(0,0,0,0.2)_0px_-3px_0px_inset]";

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
  const department = useSessionStore((state) => state.department);
  const { locale, setLocale, t } = useLocale();
  const [isSignOutConfirmOpen, setIsSignOutConfirmOpen] = useState(false);
  const [isSigningOut, setIsSigningOut] = useState(false);

  const navItems = user
    ? (roleNavItems[user.role] ?? []).map((item) => ({
        ...item,
        label: t(item.labelKey),
      }))
    : [];

  const desktopNavItems = navItems.filter(
    (item) => item.labelKey !== "nav.profile",
  );

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
  const profileImage =
    department?.profile_picture || department?.profile_photo || user?.avatar_url;
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
      // Sign out locally even if the API call fails.
    }
    setIsSignOutConfirmOpen(false);
    signOut();
    navigate("/");
  }

  return (
    <div className="min-h-screen bg-surface">
      <header className="fixed left-0 right-0 top-0 z-50 flex w-full items-center justify-between bg-gradient-to-r from-[#d98d63] via-[#bf6e49] to-[#a86446] px-8 py-4">
        <div className="flex items-center">
          <Link className="text-2xl font-headline italic text-white" to="/">
            Dispatch
          </Link>
        </div>

        <div className="flex items-center gap-4">
          <div
            aria-label={t("shell.language")}
            className="hidden items-center gap-1 rounded-full border border-white/20 bg-white/90 px-1 py-1 shadow-sm sm:flex"
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
              <span className="hidden text-xs font-bold uppercase tracking-widest text-white/80 sm:inline-block">
                {user.full_name ?? user.email}
              </span>
              <button
                className="rounded-lg p-2 transition-colors hover:bg-white/10"
                onClick={openSignOutConfirm}
                title={t("shell.signOut")}
                type="button"
              >
                <span className="material-symbols-outlined text-white/85">
                  logout
                </span>
              </button>
              <button
                className="rounded-lg p-2 transition-colors hover:bg-white/10"
                type="button"
              >
                <span className="material-symbols-outlined text-white/85">
                  account_circle
                </span>
              </button>
            </>
          ) : (
            <Link
              className="text-sm font-medium text-white/85 transition-colors hover:text-white"
              to="/auth/login"
            >
              {t("shell.signIn")}
            </Link>
          )}
        </div>
      </header>

      {/* ── Side Nav Bar (desktop only) ── */}
      {/* ── Main Content ── */}
      <main className="min-h-screen pt-20">
        <div className={cn("mx-auto px-8 pb-8 pt-3", user ? "max-w-[1500px] lg:pl-[21rem]" : "max-w-[1200px]")}>
          {user && (
            <aside className="hidden lg:fixed lg:left-[max(2rem,calc(50%-750px+2rem))] lg:top-24 lg:flex lg:h-[calc(100vh-8rem)] lg:w-[18rem] lg:flex-col lg:border-r lg:border-outline-variant/15 lg:bg-surface lg:px-6 lg:pb-8 lg:pt-6">
              <div className="mb-8 px-4">
                <h2 className="font-headline text-3xl italic text-on-surface">
                  {sidebarMeta.title}
                </h2>
                <p className="mt-1 text-xs font-medium uppercase tracking-widest text-on-surface-variant">
                  {sidebarMeta.subtitle}
                </p>
              </div>

              <nav className="flex flex-1 flex-col gap-1 overflow-y-auto pr-2">
                {desktopNavItems.map((item) => (
                  <NavLink
                    key={item.to}
                    className={({ isActive }) =>
                      cn(
                        "flex items-center gap-4 rounded-xl px-4 py-3.5 text-lg font-medium transition-all duration-200",
                        isActive
                          ? "bg-surface-container-lowest text-[#D97757] shadow-sm"
                          : "text-on-surface-variant hover:bg-[#d98d63]/18 hover:text-[#a86446] hover:shadow-[0_10px_24px_rgba(168,100,70,0.12)]",
                      )
                    }
                    end={
                      item.to === "/citizen" ||
                      item.to === "/department" ||
                      item.to === "/municipality"
                    }
                    to={item.to}
                  >
                    <span className="material-symbols-outlined text-[26px]">
                      {item.icon}
                    </span>
                    {item.label}
                  </NavLink>
                ))}
              </nav>

              <div className="mt-auto border-t border-outline-variant/10 pt-5">
                <NavLink
                  className={({ isActive }) =>
                    cn(
                      "flex w-full items-center gap-4 rounded-2xl px-4 py-3 transition-all duration-200",
                      isActive
                        ? "bg-surface-container-lowest shadow-sm"
                        : "hover:bg-[#d98d63]/16 hover:shadow-[0_10px_24px_rgba(168,100,70,0.12)]",
                    )
                  }
                  to={profileRoute}
                >
                  {profileImage ? (
                    <img
                      alt={profileName}
                      className="h-14 w-14 rounded-full object-cover ring-1 ring-outline-variant/20"
                      src={profileImage}
                    />
                  ) : (
                    <div className="flex h-14 w-14 items-center justify-center rounded-full bg-[#d98d63]/20 text-lg font-semibold text-[#a86446] ring-1 ring-outline-variant/20">
                      {profileInitial}
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-base font-semibold text-on-surface">
                      {profileName}
                    </p>
                    <p className="truncate text-sm text-on-surface-variant">
                      {profileHandle}
                    </p>
                  </div>
                  <button
                    className="flex h-11 w-11 items-center justify-center rounded-full text-on-surface-variant transition-all duration-200 hover:bg-[#d98d63]/22 hover:text-[#a86446]"
                    onClick={(event) => {
                      event.preventDefault();
                      event.stopPropagation();
                      openSignOutConfirm();
                    }}
                    title={t("shell.signOut")}
                    type="button"
                  >
                    <span className="material-symbols-outlined text-[24px]">
                      logout
                    </span>
                  </button>
                </NavLink>
              </div>
            </aside>
          )}

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

      {isSignOutConfirmOpen && (
        <div className="fixed inset-0 z-[75] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div
            className={`w-full max-w-md rounded-[28px] border border-[#efd8d0] bg-[#fff8f3] p-6 ${popupPanelShadowClassName}`}
          >
            <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
              {t("shell.signOut")}
            </p>
            <h3 className="mt-3 text-2xl text-on-surface">
              {t("shell.signOutConfirmTitle")}
            </h3>
            <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">
              {t("shell.signOutConfirmBody")}
            </p>
            <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <button
                className="rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-5 py-3 text-sm font-semibold text-[#6f625b] transition-colors hover:bg-[#f2e7de] disabled:cursor-not-allowed disabled:opacity-70"
                disabled={isSigningOut}
                onClick={closeSignOutConfirm}
                type="button"
              >
                {t("shell.cancel")}
              </button>
              <button
                className="rounded-full bg-[#a14b2f] px-5 py-3 text-sm font-semibold text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-70"
                disabled={isSigningOut}
                onClick={() => void handleSignOut()}
                type="button"
              >
                {isSigningOut ? t("shell.signingOut") : t("shell.signOut")}
              </button>
            </div>
          </div>
        </div>
      )}

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

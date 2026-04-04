import { type ReactNode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, NavLink, useNavigate } from "react-router-dom";

import { LocationMap } from "@/components/maps/location-map";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { useLocale } from "@/lib/i18n/locale-context";
import type { MessageKey } from "@/lib/i18n/messages";
import { subscribeToTable } from "@/lib/realtime/supabase";
import { cn } from "@/lib/utils";
import { useAppShellTheme } from "./app-shell-theme";

type AppShellProps = {
  title: string;
  subtitle: string;
  children: ReactNode;
  hidePageHeading?: boolean;
};

type NavItem = {
  to: string;
  labelKey: MessageKey;
  icon: string;
};

const popupPanelShadowClassName =
  "shadow-[rgba(0,0,0,0.4)_0px_2px_4px,rgba(0,0,0,0.3)_0px_7px_13px_-3px,rgba(0,0,0,0.2)_0px_-3px_0px_inset]";

type NotificationRecord = {
  id: string;
  type: string;
  title: string;
  message: string;
  is_read: boolean;
  reference_id?: string | null;
  reference_type?: string | null;
  created_at: string;
};

type EmergencyReportPreview = {
  id: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  created_at: string;
};

function labelize(value?: string | null) {
  if (!value) {
    return "";
  }

  return value
    .replace(/_/g, " ")
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function summarizeText(content?: string | null, maxLength = 112) {
  const collapsed = content?.replace(/\s+/g, " ").trim() ?? "";
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return `${collapsed.slice(0, maxLength).trimEnd()}...`;
}

function parseCoordinateLocation(location?: string | null) {
  if (!location) {
    return null;
  }

  const match = location.trim().match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);

  if (!match) {
    return null;
  }

  const lat = Number(match[1]);
  const lng = Number(match[2]);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return null;
  }

  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return null;
  }

  return { lat, lng };
}

function formatCoordinateFallback(location?: string | null) {
  const parsed = parseCoordinateLocation(location);
  if (!parsed) {
    return location?.trim() ?? "";
  }

  return `${parsed.lat.toFixed(4)}, ${parsed.lng.toFixed(4)}`;
}

function summarizeResolvedLocation(data: {
  name?: string;
  address?: Record<string, string | undefined>;
}) {
  const address = data.address ?? {};
  const primary =
    data.name ||
    address.amenity ||
    address.building ||
    address.tourism ||
    address.leisure ||
    address.road ||
    address.suburb ||
    address.neighbourhood ||
    address.village ||
    address.town ||
    address.city ||
    address.municipality;
  const locality =
    address.city ||
    address.town ||
    address.municipality ||
    address.village ||
    address.county ||
    address.state;
  const country = address.country;

  return [primary, locality, country].filter(Boolean).join(", ");
}

function formatElapsedTime(createdAt?: string | null, nowMs = Date.now()) {
  if (!createdAt) {
    return "00m 00s";
  }

  const parsed = new Date(createdAt).getTime();
  if (!Number.isFinite(parsed)) {
    return "00m 00s";
  }

  const diffMs = Math.max(0, nowMs - parsed);
  const totalSeconds = Math.floor(diffMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours.toString().padStart(2, "0")}h ${minutes.toString().padStart(2, "0")}m`;
  }

  return `${minutes.toString().padStart(2, "0")}m ${seconds.toString().padStart(2, "0")}s`;
}

function readShownEmergencyAlertIds(storageKey: string) {
  try {
    const raw = window.sessionStorage.getItem(storageKey);
    if (!raw) {
      return [];
    }

    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((value): value is string => typeof value === "string") : [];
  } catch {
    return [];
  }
}

function writeShownEmergencyAlertIds(storageKey: string, ids: string[]) {
  try {
    window.sessionStorage.setItem(storageKey, JSON.stringify(ids));
  } catch {
    // Ignore session storage failures and continue with in-memory behavior.
  }
}

async function fetchShellJson<T>(path: string) {
  return apiRequest<T>(path);
}

async function putShellJson(path: string) {
  await apiRequest(path, { method: "PUT" });
}

async function postShellJson(path: string) {
  await apiRequest(path, { method: "POST" });
}

function DepartmentEmergencyAlert({
  accessToken,
  isDarkMode,
  userId,
}: {
  accessToken: string | null;
  isDarkMode: boolean;
  userId: string;
}) {
  const navigate = useNavigate();
  const [notifications, setNotifications] = useState<NotificationRecord[]>([]);
  const [activeReport, setActiveReport] = useState<EmergencyReportPreview | null>(null);
  const [activeNotificationId, setActiveNotificationId] = useState<string | null>(null);
  const [resolvedLocations, setResolvedLocations] = useState<Record<string, string>>({});
  const [nowMs, setNowMs] = useState(() => Date.now());
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const resolvingLocationsRef = useRef(new Set<string>());
  const shownNotificationStorageKey = `dispatch:shown-emergency-alerts:${userId}`;
  const shownNotificationIdsRef = useRef<string[] | null>(null);

  if (shownNotificationIdsRef.current === null) {
    shownNotificationIdsRef.current = readShownEmergencyAlertIds(shownNotificationStorageKey);
  }

  const rememberNotificationAsShown = useCallback((notificationId: string) => {
    const currentShownIds = shownNotificationIdsRef.current ?? [];
    if (currentShownIds.includes(notificationId)) {
      return;
    }

    const nextShownIds = [...currentShownIds, notificationId];
    shownNotificationIdsRef.current = nextShownIds;
    writeShownEmergencyAlertIds(shownNotificationStorageKey, nextShownIds);
  }, [shownNotificationStorageKey]);

  const getEmergencyNotifications = useCallback((notificationList: NotificationRecord[] | undefined) => {
    return (notificationList ?? [])
      .filter(
        (notification) =>
          !notification.is_read &&
          notification.type === "new_report" &&
          notification.reference_type === "report" &&
          notification.reference_id,
      )
      .sort((left, right) => {
        const leftTime = new Date(left.created_at).getTime();
        const rightTime = new Date(right.created_at).getTime();
        return rightTime - leftTime;
      });
  }, []);

  const pickNextEmergencyNotificationId = useCallback((
    notificationList: NotificationRecord[],
    currentNotificationId: string | null,
  ) => {
    const emergencyNotifications = getEmergencyNotifications(notificationList);

    if (currentNotificationId && emergencyNotifications.some((notification) => notification.id === currentNotificationId)) {
      return currentNotificationId;
    }

    const nextNotification = emergencyNotifications.find(
      (notification) => !(shownNotificationIdsRef.current ?? []).includes(notification.id),
    );

    if (!nextNotification) {
      return null;
    }

    rememberNotificationAsShown(nextNotification.id);
    return nextNotification.id;
  }, [getEmergencyNotifications, rememberNotificationAsShown]);

  const activeNotification = useMemo(
    () => notifications.find((notification) => notification.id === activeNotificationId) ?? null,
    [activeNotificationId, notifications],
  );

  let coordinateSource: string | null = null;
  if (activeReport?.address && parseCoordinateLocation(activeReport.address)) {
    coordinateSource = activeReport.address.trim();
  } else if (activeReport?.latitude != null && activeReport?.longitude != null) {
    coordinateSource = String(activeReport.latitude) + ", " + String(activeReport.longitude);
  }

  const locationLabel = activeReport?.address && !parseCoordinateLocation(activeReport.address)
    ? activeReport.address
    : coordinateSource
      ? resolvedLocations[coordinateSource] ?? formatCoordinateFallback(coordinateSource)
      : "Field location pending";


  useEffect(() => {
    audioRef.current = new Audio("/sounds/critical-report-alert.mp3");
    audioRef.current.preload = "auto";

    return () => {
      if (audioRef.current) {
        try {
          audioRef.current.pause();
        } catch {
          // JSDOM does not implement media controls.
        }
        audioRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (!activeNotification) {
      return;
    }

    const timer = window.setInterval(() => {
      setNowMs(Date.now());
    }, 1000);

    return () => {
      window.clearInterval(timer);
    };
  }, [activeNotification]);

  useEffect(() => {
    const fetchNotifications = () =>
      fetchShellJson<{ notifications?: NotificationRecord[] }>("/api/notifications")
        .then((response) => {
          const nextNotifications = Array.isArray(response.notifications)
            ? response.notifications
            : [];
          setNotifications(nextNotifications);
          setActiveNotificationId((currentNotificationId) =>
            pickNextEmergencyNotificationId(nextNotifications, currentNotificationId),
          );
        })
        .catch(() => {
          setNotifications([]);
          setActiveNotificationId(null);
        });

    queueMicrotask(() => {
      void fetchNotifications();
    });

    const subscription = subscribeToTable(
      "notifications",
      () => {
        void fetchNotifications();
      },
      { accessToken },
    );

    const intervalId = window.setInterval(() => {
      void fetchNotifications();
    }, 4000);

    return () => {
      subscription.unsubscribe();
      window.clearInterval(intervalId);
    };
  }, [accessToken, pickNextEmergencyNotificationId, userId]);

  useEffect(() => {
    if (!activeNotification?.reference_id) {
      return;
    }

    void fetchShellJson<{ report?: EmergencyReportPreview }>(`/api/reports/${activeNotification.reference_id}`)
      .then((response) => {
        setActiveReport(response.report ?? null);
      })
      .catch(() => {
        setActiveReport(null);
      });
  }, [accessToken, activeNotification?.reference_id]);

  useEffect(() => {
    if (!coordinateSource || resolvedLocations[coordinateSource] || resolvingLocationsRef.current.has(coordinateSource)) {
      return;
    }

    const parsed = parseCoordinateLocation(coordinateSource);
    if (!parsed) {
      return;
    }

    resolvingLocationsRef.current.add(coordinateSource);

    void fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${parsed.lat}&lon=${parsed.lng}&zoom=16&addressdetails=1`,
    )
      .then(async (response) => {
        if (!response.ok) {
          throw new Error("Reverse geocoding failed.");
        }

        const data = (await response.json()) as {
          name?: string;
          display_name?: string;
          address?: Record<string, string | undefined>;
        };

        const summary =
          summarizeResolvedLocation(data) || data.display_name || formatCoordinateFallback(coordinateSource);

        setResolvedLocations((current) => ({
          ...current,
          [coordinateSource]: summary,
        }));
      })
      .catch(() => {
        setResolvedLocations((current) => ({
          ...current,
          [coordinateSource]: formatCoordinateFallback(coordinateSource),
        }));
      })
      .finally(() => {
        resolvingLocationsRef.current.delete(coordinateSource);
      });
  }, [coordinateSource, resolvedLocations]);

  useEffect(() => {
    if (!activeNotification?.id) {
      return;
    }

    const storageKey = "dispatch:last-played-emergency-alert";
    if (window.sessionStorage.getItem(storageKey) === activeNotification.id) {
      return;
    }

    window.sessionStorage.setItem(storageKey, activeNotification.id);

    if (audioRef.current) {
      audioRef.current.currentTime = 0;
      void audioRef.current.play().catch(() => undefined);
    }
  }, [activeNotification?.id]);

  async function markNotificationRead(notificationId: string) {
    setNotifications((current) =>
      current.map((notification) =>
        notification.id === notificationId ? { ...notification, is_read: true } : notification,
      ),
    );

    try {
      await putShellJson(`/api/notifications/${notificationId}/read`);
    } catch {
      // Keep the optimistic update for this emergency handoff.
    }
  }

  async function handleViewIncidentDetails() {
    if (!activeNotification?.reference_id) {
      return;
    }

    if (activeNotification.id) {
      await markNotificationRead(activeNotification.id);
    }

    setActiveNotificationId((currentNotificationId) =>
      pickNextEmergencyNotificationId(
        notifications.map((notification) =>
          notification.id === activeNotification.id ? { ...notification, is_read: true } : notification,
        ),
        currentNotificationId === activeNotification.id ? null : currentNotificationId,
      ),
    );
    navigate(`/department/reports/${activeNotification.reference_id}`);
  }

  function dismissCurrentAlert() {
    if (!activeNotification?.id) {
      return;
    }

    setActiveNotificationId((currentNotificationId) =>
      pickNextEmergencyNotificationId(
        notifications,
        currentNotificationId === activeNotification.id ? null : currentNotificationId,
      ),
    );
  }

  if (!activeNotification) {
    return null;
  }

  const categoryLabel = labelize(activeReport?.category) || "Emergency";
  const severityLabel = labelize(activeReport?.severity) || "High";
  const headerToneClassName = isDarkMode
    ? "border-[#613724] bg-[#9e4b2d] text-white"
    : "border-[#d1845e] bg-[#b55a36] text-white";
  const bodySurfaceClassName = isDarkMode
    ? "border-[#3a342f] bg-[#23201d] text-[#f4eee8]"
    : "border-[#efd8d0] bg-[#fff8f3] text-on-surface";
  const insetCardClassName = isDarkMode
    ? "border-[#433c36] bg-[#2a2623]"
    : "border-[#ecd8cf] bg-[#f7efe7]";
  const mutedTextClassName = isDarkMode ? "text-[#cdbeb1]" : "text-[#7b6b62]";
  const elapsedLabel = formatElapsedTime(activeReport?.created_at ?? activeNotification.created_at, nowMs);

  return (
    <div className="fixed inset-0 z-[95] flex items-center justify-center bg-black/35 p-4 backdrop-blur-md md:p-8">
      <div className={`w-full max-w-[640px] overflow-hidden rounded-[32px] border ${bodySurfaceClassName} ${popupPanelShadowClassName}`}>
        <div className={`relative border-b px-6 py-5 ${headerToneClassName}`}>
          <button
            aria-label="Dismiss emergency alert"
            className="absolute right-4 top-4 inline-flex h-9 w-9 items-center justify-center rounded-full border border-white/15 bg-white/10 text-white/80 transition-colors hover:bg-white/20 hover:text-white"
            onClick={dismissCurrentAlert}
            type="button"
          >
            <span className="material-symbols-outlined text-[18px]">close</span>
          </button>

          <div className="flex items-start justify-between gap-8 pr-10">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-[0.28em] text-white/80">
                <span className="flex h-7 w-7 items-center justify-center rounded-full bg-white/14">
                  <span className="material-symbols-outlined text-[15px]">local_fire_department</span>
                </span>
                System Priority: Alpha
              </div>
              <h3 className="mt-2 font-headline text-[2.2rem] uppercase italic leading-[0.88] sm:text-[2.45rem]">
                Critical {categoryLabel} Alert
              </h3>
            </div>
            <div className="shrink-0 text-right">
              <p className="text-[10px] font-bold uppercase tracking-[0.24em] text-white/70">Elapsed Time</p>
              <p className="mt-1 text-[2rem] leading-none sm:text-[2.15rem]">{elapsedLabel}</p>
            </div>
          </div>
        </div>

        <div className="space-y-5 px-6 py-5">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className={`text-[10px] font-bold uppercase tracking-[0.22em] ${mutedTextClassName}`}>Incident ID</p>
              <p className="mt-1 font-headline text-[2rem] leading-none">
                #{(activeReport?.id ?? activeNotification.reference_id ?? "pending").slice(0, 8)}
              </p>
            </div>
            <div className="text-right">
              <p className={`text-[10px] font-bold uppercase tracking-[0.22em] ${mutedTextClassName}`}>Severity</p>
              <p className="mt-1 text-[1.4rem] font-semibold text-[#d97757]">• {severityLabel}</p>
            </div>
          </div>

          <div className={`rounded-[24px] border px-5 py-4 ${insetCardClassName}`}>
            <p className={`flex items-center gap-2 text-[10px] font-bold uppercase tracking-[0.22em] ${mutedTextClassName}`}>
              <span className="material-symbols-outlined text-[16px] text-[#d97757]">location_on</span>
              Primary Location
            </p>
            <p className="mt-2 font-headline text-[1.85rem] leading-[0.95]">{locationLabel}</p>
            <p className={`mt-2 text-[15px] leading-6 ${mutedTextClassName}`}>
              {summarizeText(activeReport?.description || activeNotification.message, 106) ||
                "Emergency report forwarded from citizen intake. Open the full incident detail for response routing."}
            </p>
          </div>

          <div className={`overflow-hidden rounded-[24px] border ${insetCardClassName}`}>
            {activeReport?.latitude !== undefined &&
            activeReport?.latitude !== null &&
            activeReport?.longitude !== undefined &&
            activeReport?.longitude !== null ? (
              <div className="relative h-[190px] overflow-hidden">
                <LocationMap
                  latitude={activeReport.latitude}
                  longitude={activeReport.longitude}
                  mapClassName="h-full w-full"
                  wrapperClassName="h-full w-full rounded-none border-0"
                />
                <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(17,17,17,0.03),rgba(17,17,17,0.32))]" />
                <div className="absolute inset-x-0 bottom-4 flex justify-center">
                  <span className="rounded-full border border-white/45 bg-[#fff7f0] px-4 py-2 text-[10px] font-bold uppercase tracking-[0.22em] text-[#b55a36] shadow-sm">
                    Point Alpha
                  </span>
                </div>
              </div>
            ) : (
              <div className="flex h-[190px] items-center justify-center bg-[linear-gradient(135deg,#efe4db,#dac4b8)]">
                <div className="text-center">
                  <span className="material-symbols-outlined text-4xl text-[#b55a36]">crisis_alert</span>
                  <p className="mt-2 text-xs font-bold uppercase tracking-[0.22em] text-[#8a4c31]">
                    Incident Visual Placeholder
                  </p>
                </div>
              </div>
            )}
          </div>

          <button
            className="flex w-full items-center justify-center gap-2 rounded-[10px] bg-[#b55a36] px-5 py-3.5 text-sm font-bold uppercase tracking-[0.22em] text-white transition-colors hover:bg-[#9d4c2c]"
            onClick={() => void handleViewIncidentDetails()}
            type="button"
          >
            View Full Incident Details
            <span className="material-symbols-outlined text-[18px]">arrow_forward</span>
          </button>

          <div
            className={`flex flex-wrap items-center justify-between gap-3 border-t px-1 pt-1 text-[10px] font-bold uppercase tracking-[0.2em] ${
              isDarkMode ? "border-white/10 text-white/45" : "border-[#ecd8cf] text-[#a79a92]"
            }`}
          >
            <span>Authenticated operative access only</span>
            <span>Hash: BXF-902-LK</span>
            <span>Secured line: 09</span>
          </div>
        </div>
      </div>
    </div>
  );
}

const roleNavItems: Record<string, NavItem[]> = {
  citizen: [
    { to: "/citizen", labelKey: "nav.myReports", icon: "description" },
    { to: "/citizen/report/new", labelKey: "nav.newReport", icon: "add_circle" },
    { to: "/citizen/news-feed", labelKey: "nav.newsFeed", icon: "campaign" },
    { to: "/notifications", labelKey: "nav.notifications", icon: "notifications" },
    { to: "/profile", labelKey: "nav.profile", icon: "person" },
  ],
  department: [
    { to: "/department", labelKey: "nav.dashboard", icon: "dashboard" },
    { to: "/department/reports", labelKey: "nav.incidentBoard", icon: "assignment" },
    { to: "/department/assessments", labelKey: "nav.assessments", icon: "assessment" },
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

export function AppShell({ title, subtitle, children, hidePageHeading = false }: AppShellProps) {
  const navigate = useNavigate();
  const signOut = useSessionStore((state) => state.signOut);
  const user = useSessionStore((state) => state.user);
  const accessToken = useSessionStore((state) => state.accessToken);
  const department = useSessionStore((state) => state.department);
  const { locale, setLocale, t } = useLocale();
  const [isSignOutConfirmOpen, setIsSignOutConfirmOpen] = useState(false);
  const [isSigningOut, setIsSigningOut] = useState(false);
  const { isDarkMode, setIsDarkMode } = useAppShellTheme();
  const isHeadlessTestEnv =
    typeof navigator !== "undefined" && navigator.userAgent.toLowerCase().includes("jsdom");

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
      await postShellJson("/api/auth/logout");
    } catch {
      // Sign out locally even if the API call fails.
    }
    setIsSignOutConfirmOpen(false);
    signOut();
    navigate("/");
  }

  return (
      <div className={cn("dispatch-shell min-h-screen", isDarkMode ? "dispatch-shell-dark bg-[#181817]" : "bg-surface")}>
      <header className="fixed left-0 right-0 top-0 z-50 flex w-full items-center justify-between bg-gradient-to-r from-[#d98d63] via-[#bf6e49] to-[#a86446] px-8 py-4">
        <div className="flex items-center">
          <Link className="text-2xl font-headline italic text-white" to="/">
            Dispatch
          </Link>
        </div>

        <div className="flex items-center gap-4">
          <div
            aria-label="Theme mode"
            className="hidden items-center gap-1 rounded-full border border-white/20 bg-white/90 px-1 py-1 shadow-sm sm:flex"
            role="group"
          >
            <button
              aria-pressed={!isDarkMode}
              className={cn(
                "inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-bold uppercase tracking-widest transition-colors",
                !isDarkMode
                  ? "bg-[#D97757] text-white"
                  : "text-on-surface-variant hover:bg-surface-container-high",
              )}
              onClick={() => setIsDarkMode(false)}
              type="button"
            >
              <span className="material-symbols-outlined text-[14px]">light_mode</span>
              Light
            </button>
            <button
              aria-pressed={isDarkMode}
              className={cn(
                "inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-bold uppercase tracking-widest transition-colors",
                isDarkMode
                  ? "bg-[#D97757] text-white"
                  : "text-on-surface-variant hover:bg-surface-container-high",
              )}
              onClick={() => setIsDarkMode(true)}
              type="button"
            >
              <span className="material-symbols-outlined text-[14px]">dark_mode</span>
              Dark
            </button>
          </div>

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
            <aside
              className={cn(
                "hidden lg:fixed lg:left-[max(2rem,calc(50%-750px+2rem))] lg:top-24 lg:flex lg:h-[calc(100vh-8rem)] lg:w-[18rem] lg:flex-col lg:px-6 lg:pb-8 lg:pt-6",
                isDarkMode
                  ? "lg:border-r lg:border-white/10 lg:bg-[#181817]"
                  : "lg:border-r lg:border-outline-variant/15 lg:bg-surface",
              )}
            >
              <div className="mb-8 px-4">
                <h2 className={cn("font-headline text-3xl italic", isDarkMode ? "text-white" : "text-on-surface")}>
                  {sidebarMeta.title}
                </h2>
                <p className={cn("mt-1 text-xs font-medium uppercase tracking-widest", isDarkMode ? "text-white/60" : "text-on-surface-variant")}>
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
                          ? isDarkMode
                            ? "bg-white/10 text-[#f2a27b] shadow-sm"
                            : "bg-surface-container-lowest text-[#D97757] shadow-sm"
                          : isDarkMode
                            ? "text-white/72 hover:bg-white/6 hover:text-white"
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

              <div className={cn("mt-auto pt-5", isDarkMode ? "border-t border-white/10" : "border-t border-outline-variant/10")}>
                <NavLink
                  className={({ isActive }) =>
                    cn(
                      "flex w-full items-center gap-4 rounded-2xl px-4 py-3 transition-all duration-200",
                      isActive
                        ? isDarkMode
                          ? "bg-white/10 shadow-sm"
                          : "bg-surface-container-lowest shadow-sm"
                        : isDarkMode
                          ? "hover:bg-white/6"
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
                    <div className={cn(
                      "flex h-14 w-14 items-center justify-center rounded-full text-lg font-semibold ring-1",
                      isDarkMode
                        ? "bg-[#d98d63]/25 text-[#ffd8c4] ring-white/15"
                        : "bg-[#d98d63]/20 text-[#a86446] ring-outline-variant/20",
                    )}>
                      {profileInitial}
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <p className={cn("truncate text-base font-semibold", isDarkMode ? "text-white" : "text-on-surface")}>
                      {profileName}
                    </p>
                    <p className={cn("truncate text-sm", isDarkMode ? "text-white/60" : "text-on-surface-variant")}>
                      {profileHandle}
                    </p>
                  </div>
                  <button
                    className={cn(
                      "flex h-11 w-11 items-center justify-center rounded-full transition-all duration-200",
                      isDarkMode
                        ? "text-white/70 hover:bg-white/8 hover:text-white"
                        : "text-on-surface-variant hover:bg-[#d98d63]/22 hover:text-[#a86446]",
                    )}
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

          {!hidePageHeading && (
            <section className="mb-10">
              <p className={cn("mb-2 text-xs font-bold uppercase tracking-widest", isDarkMode ? "text-[#f2a27b]" : "text-[#D97757]")}>
                {subtitle}
              </p>
              <h1 className={cn("font-headline text-4xl font-bold tracking-tight lg:text-5xl", isDarkMode ? "text-white" : "text-on-surface")}>
                {title}
              </h1>
            </section>
          )}
          {children}
        </div>
      </main>

      {user?.role === "department" && !isHeadlessTestEnv ? (
        <DepartmentEmergencyAlert
          accessToken={accessToken}
          isDarkMode={isDarkMode}
          userId={user.id}
        />
      ) : null}

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
        <nav className={cn(
          "hide-scrollbar glass-panel fixed bottom-0 left-0 right-0 z-50 flex items-center gap-4 overflow-x-auto border-t px-4 py-3 lg:hidden",
          isDarkMode ? "border-white/10 bg-[#181817]/95" : "border-outline-variant/10",
        )}>
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              className={({ isActive }) =>
                cn(
                  "flex min-w-[72px] flex-col items-center gap-1",
                  isActive ? "text-[#D97757]" : isDarkMode ? "text-white/65" : "text-on-surface-variant",
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













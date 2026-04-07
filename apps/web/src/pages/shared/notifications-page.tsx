// Notification center — lists all user notifications with mark-read and mark-all-read actions.

import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { DepartmentPageHero } from "@/components/layout/department-page-hero";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore, type AppRole } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type Notification = {
  id: string;
  type: string;
  title: string;
  message: string;
  is_read: boolean;
  reference_id?: string;
  reference_type?: string;
  created_at: string;
  sender_name?: string;
  sender_avatar_url?: string | null;
};

// Icon per notification type
const typeIcons: Record<string, string> = {
  new_report: "assignment",
  report_update: "update",
  verification_decision: "verified_user",
  announcement: "campaign",
};

const notificationTypeLabels: Record<string, string> = {
  new_report: "New report",
  report_update: "Report update",
  verification_decision: "Verification",
  announcement: "Announcement",
};

const notificationTypeStyles: Record<
  string,
  {
    pillClassName: string;
    iconSurfaceClassName: string;
    iconClassName: string;
  }
> = {
  new_report: {
    pillClassName: "bg-[#ffdbd0] text-[#89391e]",
    iconSurfaceClassName: "bg-[#f2e2d7]",
    iconClassName: "text-[#b25e39]",
  },
  report_update: {
    pillClassName: "bg-[#dfeaf5] text-[#456b86]",
    iconSurfaceClassName: "bg-[#e7eef7]",
    iconClassName: "text-[#4b6e90]",
  },
  verification_decision: {
    pillClassName: "bg-[#ece3f5] text-[#6e4c91]",
    iconSurfaceClassName: "bg-[#f1e9f8]",
    iconClassName: "text-[#7d5ea1]",
  },
  announcement: {
    pillClassName: "bg-[#ffe7cf] text-[#a14b2f]",
    iconSurfaceClassName: "bg-[#ffefe1]",
    iconClassName: "text-[#b35e38]",
  },
};

const notificationCardShadowClassName =
  "shadow-[0_10px_22px_-12px_rgba(120,78,58,0.48),0_5px_5px_0_#00000026]";
const notificationCardHoverShadowClassName =
  "hover:shadow-[0_10px_22px_-12px_rgba(120,78,58,0.48),0_5px_5px_0_#00000026]";
const filterTabBaseClassName =
  "rounded-full border px-[18px] py-[0.55rem] text-[12px] font-semibold transition-colors";
const inactiveFilterTabClassName =
  "border-[#e3d3c6] bg-[#fff8f3] text-[#6f625b] hover:bg-[#f4ebe3] hover:text-[#584137]";
const activeFilterTabClassName =
  "border-[#8f5137] bg-[#8f5137] text-white shadow-[0_10px_22px_-16px_rgba(143,81,55,0.7)]";

const notificationStatusFilterOptions = [
  { value: "all", label: "All" },
  { value: "unread", label: "Unread" },
  { value: "read", label: "Read" },
] as const;

const notificationCategoryFilterOptions = [
  { value: "all", label: "Category" },
  { value: "new_report", label: "New Report" },
  { value: "report_update", label: "Report Update" },
  { value: "verification_decision", label: "Verification" },
  { value: "announcement", label: "Announcement" },
] as const;

function labelize(value?: string | null) {
  if (!value) {
    return "";
  }

  return value
    .replace(/_/g, " ")
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function formatInlineTimestamp(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value;
  }

  return parsed.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatTimelineTimestamp(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return { dateLabel: value, timeLabel: "" };
  }

  return {
    dateLabel: parsed
      .toLocaleDateString(undefined, {
        month: "short",
        day: "numeric",
      })
      .toUpperCase(),
    timeLabel: parsed.toLocaleTimeString(undefined, {
      hour: "2-digit",
      minute: "2-digit",
    }),
  };
}

function NotificationBoardCard({
  notification,
  onOpen,
  onDelete,
  isDeleting,
}: {
  notification: Notification;
  onOpen: (notification: Notification) => void;
  onDelete: (notification: Notification) => void;
  isDeleting: boolean;
}) {
  const typeStyle = notificationTypeStyles[notification.type] ?? {
    pillClassName: "bg-[#f1e4da] text-[#85563f]",
    iconSurfaceClassName: "bg-[#f5ebe3]",
    iconClassName: "text-[#9c684f]",
  };
  const typeLabel =
    notificationTypeLabels[notification.type] ??
    (labelize(notification.type) || "Notification");
  const compactTitle = notification.title?.trim() || typeLabel;
  const compactMessage =
    notification.message?.trim() || "Tap to review this notification.";
  const senderInitial =
    notification.sender_name?.trim().charAt(0).toUpperCase() || null;
  const compactContextLabel =
    notification.reference_type === "report" && notification.reference_id
      ? `Report #${String(notification.reference_id).slice(0, 8)}`
      : notification.reference_type
        ? labelize(notification.reference_type)
        : "Dispatch";
  const leftEdgeClassName = notification.is_read
    ? "before:bg-[linear-gradient(180deg,#e9d7cc,#d9c2b5)]"
    : "before:bg-[linear-gradient(180deg,#d97757,#b35e38)]";

  return (
    <Card
      className={`relative cursor-pointer overflow-hidden rounded-[22px] border-[#ead9cc] bg-[#fff8f3] p-0 before:absolute before:inset-y-0 before:left-0 before:w-[10px] before:content-[''] ${leftEdgeClassName} ${notificationCardShadowClassName} transition-all duration-200 hover:-translate-y-0.5 ${notificationCardHoverShadowClassName}`}
      onClick={() => void onOpen(notification)}
    >
      <article
        className="relative flex min-h-[90px] items-center overflow-hidden pl-6 pr-4 py-3 md:min-h-[86px] md:pl-7 md:pr-5"
        aria-label={`Open notification ${compactTitle}`}
      >
        <div className="relative z-[2] flex w-full min-w-0 items-center">
          <div className="relative z-[3] flex min-w-0 flex-1 items-center gap-3 pr-4 md:pr-6">
            <div className="relative shrink-0">
              {!notification.is_read ? (
                <span className="absolute -left-2 top-1/2 z-[2] h-2.5 w-2.5 -translate-y-1/2 rounded-full bg-[#d97757] shadow-[0_0_0_3px_rgba(255,240,232,0.95)]" />
              ) : null}
              <div
                className={`flex h-10 w-10 items-center justify-center overflow-hidden rounded-full shadow-[0_10px_22px_-18px_rgba(166,92,58,0.55)] ${typeStyle.iconSurfaceClassName} ${typeStyle.iconClassName}`}
              >
                {notification.sender_avatar_url ? (
                  <img
                    alt={notification.sender_name ? `${notification.sender_name} avatar` : "Notification sender avatar"}
                    className="h-full w-full object-cover"
                    src={notification.sender_avatar_url}
                  />
                ) : senderInitial ? (
                  <span className="text-[13px] font-semibold text-[#8f5137]">
                    {senderInitial}
                  </span>
                ) : (
                  <span className="material-symbols-outlined text-[16px]">
                    {typeIcons[notification.type] ?? "notifications"}
                  </span>
                )}
              </div>
            </div>

            <div className="min-w-0 flex-1">
              <div className="min-w-0">
                <h3 className="truncate text-[15px] font-semibold leading-none text-[#4d2b1e]">
                  {compactTitle}
                </h3>
                <p className="mt-1 truncate text-[12.5px] leading-5 text-[#705d52]">
                  {compactMessage}
                </p>
              </div>

            </div>

            <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 whitespace-nowrap text-[9px] font-bold uppercase tracking-[0.18em] text-[#a56a50]">
              <span
                className={`rounded-full px-2 py-1 ${typeStyle.pillClassName}`}
              >
                {typeLabel}
              </span>
              <span className="rounded-full border border-[#e8d8cb] bg-[#fbf4ee] px-2 py-1 text-[#9f7b65]">
                {compactContextLabel}
              </span>
              {!notification.is_read ? (
                <span className="rounded-full border border-[#e9cdb9] bg-[#fff3e6] px-2 py-1 text-[#b1683d]">
                  New
                </span>
              ) : null}
              <span className="rounded-full border border-[#ead7c7] bg-white/75 px-2 py-1 text-[#9f6a4e] md:hidden">
                {formatInlineTimestamp(notification.created_at)}
              </span>
            </div>
          </div>
          <div className="relative z-[3] ml-2 flex shrink-0 items-center self-center">
            <button
              type="button"
              className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-[#e4d0c3] bg-white/85 text-[#9c684f] transition hover:border-[#cf9a80] hover:bg-[#fff1e8] hover:text-[#8f5137] disabled:cursor-not-allowed disabled:opacity-60"
              onClick={(event) => {
                event.stopPropagation();
                onDelete(notification);
              }}
              aria-label={`Delete notification ${compactTitle}`}
              disabled={isDeleting}
              title="Delete notification"
            >
              <span className="material-symbols-outlined text-[18px]">
                delete
              </span>
            </button>
          </div>
        </div>
      </article>
    </Card>
  );
}

function NotificationTimelineBlock({
  notification,
}: {
  notification: Notification;
}) {
  const timelineTimestamp = formatTimelineTimestamp(notification.created_at);

  return (
    <div className="pointer-events-none relative flex min-h-[88px] items-stretch">
      <div className="relative flex w-full justify-start py-3">
        <div className="absolute bottom-3 left-[1.1rem] top-3 w-px bg-[linear-gradient(180deg,rgba(214,160,132,0.08),rgba(214,160,132,0.55)_18%,rgba(214,160,132,0.55)_82%,rgba(214,160,132,0.08))]" />
        <span className="absolute left-[0.83rem] top-5 h-2.5 w-2.5 rounded-full border border-[#dba788] bg-[#fff8f3] shadow-[0_0_0_3px_rgba(255,248,243,0.88)]" />
        <div className="relative z-10 ml-7 flex max-w-[4.5rem] flex-col text-left">
          <span className="text-[9px] font-bold uppercase tracking-[0.18em] text-[#b16f52]">
            {timelineTimestamp.dateLabel}
          </span>
          {timelineTimestamp.timeLabel ? (
            <span className="mt-1 text-[10px] font-semibold tracking-[0.04em] text-[#8b644f]">
              {timelineTimestamp.timeLabel}
            </span>
          ) : null}
        </div>
      </div>
    </div>
  );
}

export function NotificationsPage() {
  const navigate = useNavigate();
  const accessToken = useSessionStore((state) => state.accessToken);
  const userRole = useSessionStore((state) => state.user?.role);
  const department = useSessionStore((state) => state.department);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] =
    useState<(typeof notificationStatusFilterOptions)[number]["value"]>("all");
  const [categoryFilter, setCategoryFilter] =
    useState<(typeof notificationCategoryFilterOptions)[number]["value"]>(
      "all",
    );
  const [searchQuery, setSearchQuery] = useState("");
  const [deleteConfirmNotification, setDeleteConfirmNotification] =
    useState<Notification | null>(null);
  const [deletingNotificationId, setDeletingNotificationId] = useState<
    string | null
  >(null);
  const [isDesktopLayout, setIsDesktopLayout] = useState(() => {
    if (typeof window === "undefined") {
      return true;
    }

    if (typeof window.matchMedia === "function") {
      return window.matchMedia("(min-width: 768px)").matches;
    }

    return window.innerWidth >= 768;
  });
  const notificationTargets = useMemo(
    () =>
      Object.fromEntries(
        notifications.map((notification) => [
          notification.id,
          getNotificationTarget(notification, userRole),
        ]),
      ) as Record<string, string | null>,
    [notifications, userRole],
  );
  const visibleNotifications = useMemo(() => {
    const normalizedQuery = searchQuery.trim().toLowerCase();

    return notifications.filter((notification) => {
      if (statusFilter === "unread" && notification.is_read) {
        return false;
      }

      if (statusFilter === "read" && !notification.is_read) {
        return false;
      }

      if (categoryFilter !== "all" && notification.type !== categoryFilter) {
        return false;
      }

      if (!normalizedQuery) {
        return true;
      }

      const typeLabel =
        notificationTypeLabels[notification.type] ??
        labelize(notification.type);
      const searchText = [
        notification.title,
        notification.message,
        typeLabel,
        notification.reference_type
          ? labelize(notification.reference_type)
          : "",
      ]
        .join(" ")
        .toLowerCase();

      return searchText.includes(normalizedQuery);
    });
  }, [categoryFilter, notifications, searchQuery, statusFilter]);

  function fetchNotifications(showLoader = true) {
    if (showLoader) {
      setLoading(true);
    }

    return apiRequest<{ notifications: Notification[]; unread_count: number }>(
      "/api/notifications",
    )
      .then((res) => {
        setNotifications(res.notifications);
        setUnreadCount(res.unread_count);
      })
      .catch(() => {})
      .finally(() => {
        if (showLoader) {
          setLoading(false);
        }
      });
  }

  useEffect(() => {
    queueMicrotask(() => {
      void fetchNotifications();
    });
  }, []);

  useEffect(() => {
    const subscription = subscribeToTable(
      "notifications",
      () => {
        void fetchNotifications(false);
      },
      { accessToken },
    );
    return () => subscription.unsubscribe();
  }, [accessToken]);

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    const updateLayout = () => {
      if (typeof window.matchMedia === "function") {
        setIsDesktopLayout(window.matchMedia("(min-width: 768px)").matches);
        return;
      }

      setIsDesktopLayout(window.innerWidth >= 768);
    };

    updateLayout();

    if (typeof window.matchMedia === "function") {
      const mediaQuery = window.matchMedia("(min-width: 768px)");
      const handleChange = (event: MediaQueryListEvent) => {
        setIsDesktopLayout(event.matches);
      };

      if (typeof mediaQuery.addEventListener === "function") {
        mediaQuery.addEventListener("change", handleChange);
        return () => mediaQuery.removeEventListener("change", handleChange);
      }

      mediaQuery.addListener(handleChange);
      return () => mediaQuery.removeListener(handleChange);
    }

    window.addEventListener("resize", updateLayout);
    return () => window.removeEventListener("resize", updateLayout);
  }, []);

  // Mark single notification read — optimistic with rollback
  async function markRead(id: string) {
    const prev = notifications;
    const prevCount = unreadCount;
    setNotifications((ns) =>
      ns.map((n) => (n.id === id ? { ...n, is_read: true } : n)),
    );
    setUnreadCount((c) => Math.max(0, c - 1));
    try {
      await apiRequest(`/api/notifications/${id}/read`, { method: "PUT" });
      void fetchNotifications(false);
    } catch {
      setNotifications(prev);
      setUnreadCount(prevCount);
    }
  }

  // Mark all notifications read — optimistic with rollback
  async function markAllRead() {
    const prev = notifications;
    const prevCount = unreadCount;
    setNotifications((ns) => ns.map((n) => ({ ...n, is_read: true })));
    setUnreadCount(0);
    try {
      await apiRequest("/api/notifications/read-all", { method: "PUT" });
      void fetchNotifications(false);
    } catch {
      setNotifications(prev);
      setUnreadCount(prevCount);
    }
  }

  async function handleNotificationClick(notification: Notification) {
    if (!notification.is_read) {
      await markRead(notification.id);
    }

    const target = notificationTargets[notification.id];
    if (target) {
      navigate(target);
    }
  }

  async function deleteNotification() {
    if (!deleteConfirmNotification) {
      return;
    }

    const prev = notifications;
    const prevCount = unreadCount;
    setDeletingNotificationId(deleteConfirmNotification.id);
    setNotifications((current) =>
      current.filter((item) => item.id !== deleteConfirmNotification.id),
    );
    if (!deleteConfirmNotification.is_read) {
      setUnreadCount((count) => Math.max(0, count - 1));
    }

    try {
      await apiRequest(`/api/notifications/${deleteConfirmNotification.id}`, {
        method: "DELETE",
      });
      setDeleteConfirmNotification(null);
      void fetchNotifications(false);
    } catch {
      setNotifications(prev);
      setUnreadCount(prevCount);
    } finally {
      setDeletingNotificationId(null);
    }
  }

  return (
    <AppShell subtitle="Stay informed" title="Notifications">
      {userRole === "department" || userRole === "citizen" ? (
        <DepartmentPageHero
          dataTestId="department-notifications-hero"
          department={department}
          eyebrow="Operational Alerts"
          headingTone="soft-light"
          icon="notifications"
          title="Notifications"
        />
      ) : null}

      <div className="mb-8 flex flex-col gap-4">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex min-w-0 flex-wrap items-center gap-2">
            <div className="flex flex-wrap items-center gap-2">
              {notificationStatusFilterOptions.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  className={`${filterTabBaseClassName} ${
                    statusFilter === option.value
                      ? activeFilterTabClassName
                      : inactiveFilterTabClassName
                  }`}
                  onClick={() => setStatusFilter(option.value)}
                >
                  {option.label}
                </button>
              ))}
            </div>

            <label className="relative block">
              <select
                className="h-11 min-w-[146px] appearance-none rounded-[12px] border border-[#e3d3c6] bg-[#fff8f3] pl-3.5 pr-9 text-[13px] font-medium text-[#6f625b] outline-none transition-colors focus:border-[#c98d71]"
                onChange={(event) =>
                  setCategoryFilter(
                    event.target
                      .value as (typeof notificationCategoryFilterOptions)[number]["value"],
                  )
                }
                value={categoryFilter}
              >
                {notificationCategoryFilterOptions.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
              <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-[#9b826f]">
                <span className="material-symbols-outlined text-[16px]">
                  expand_more
                </span>
              </span>
            </label>

            <label className="relative block min-w-0 lg:w-[240px] xl:w-[280px]">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[#a08373]">
                <span className="material-symbols-outlined text-[17px]">
                  search
                </span>
              </span>
              <input
                className="h-11 w-full rounded-[12px] border border-[#e3d3c6] bg-[#fff8f3] pl-10 pr-4 text-[14px] text-[#4d2b1e] outline-none transition-colors placeholder:text-[#a08373] focus:border-[#c98d71]"
                onChange={(event) => setSearchQuery(event.target.value)}
                placeholder="Search notifications"
                type="search"
                value={searchQuery}
              />
            </label>
          </div>

          <div className="flex shrink-0 items-center gap-3">
            {unreadCount > 0 && (
              <Button
                className="h-11 rounded-full border border-[#e3d3c6] bg-[#fff8f3] px-[18px] text-[#7a6558] hover:bg-[#f3e8de]"
                onClick={markAllRead}
                variant="ghost"
              >
                <span className="material-symbols-outlined mr-1 text-[16px]">
                  done_all
                </span>
                Mark all read
              </Button>
            )}
            <Button
              className="h-11 rounded-full border border-[#e3d3c6] bg-[#fff8f3] px-[18px] text-[#7a6558] hover:bg-[#f3e8de]"
              onClick={() => {
                void fetchNotifications();
              }}
              variant="ghost"
            >
              <span className="material-symbols-outlined mr-1 text-[16px]">
                refresh
              </span>
              Refresh
            </Button>
            <span className="text-xs font-semibold text-[#8a776b]">
              Showing {visibleNotifications.length} notification
              {visibleNotifications.length !== 1 ? "s" : ""}
            </span>
          </div>
        </div>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading notifications...
        </Card>
      ) : notifications.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">
            notifications_off
          </span>
          <p className="text-on-surface-variant">No notifications yet.</p>
        </Card>
      ) : visibleNotifications.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">
            search_off
          </span>
          <p className="text-on-surface-variant">
            No notifications match the current filters or search.
          </p>
        </Card>
      ) : !isDesktopLayout ? (
        <div className="space-y-3">
          {visibleNotifications.map((notification) => (
            <NotificationBoardCard
              key={notification.id}
              notification={notification}
              onOpen={handleNotificationClick}
              onDelete={setDeleteConfirmNotification}
              isDeleting={deletingNotificationId === notification.id}
            />
          ))}
        </div>
      ) : (
        <div className="grid md:grid-cols-[minmax(0,1fr)_6.5rem] md:gap-5 md:mr-2 xl:mr-4">
          <section className="overflow-visible rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]">
            <div className="space-y-3">
              {visibleNotifications.map((notification) => (
                <NotificationBoardCard
                  key={notification.id}
                  notification={notification}
                  onOpen={handleNotificationClick}
                  onDelete={setDeleteConfirmNotification}
                  isDeleting={deletingNotificationId === notification.id}
                />
              ))}
            </div>
          </section>

          <aside className="overflow-visible rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]">
            <div className="space-y-3">
              {visibleNotifications.map((notification) => (
                <NotificationTimelineBlock
                  key={notification.id}
                  notification={notification}
                />
              ))}
            </div>
          </aside>
        </div>
      )}

      {deleteConfirmNotification && (
        <div className="fixed inset-0 z-[1200] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div className="relative z-[1201] w-full max-w-md rounded-[28px] border border-[#efd8d0] bg-[#fff8f3] p-6 shadow-[rgba(0,0,0,0.4)_0px_2px_4px,rgba(0,0,0,0.3)_0px_7px_13px_-3px,rgba(0,0,0,0.2)_0px_-3px_0px_inset]">
            <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
              Delete notification
            </p>
            <h3 className="mt-3 text-2xl text-on-surface">
              Are you sure you want to delete this notification?
            </h3>
            <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">
              This will remove the notification from your list and delete the
              linked notification record from the database.
            </p>
            <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <button
                className="rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-5 py-3 text-sm font-semibold text-[#6f625b] transition-colors hover:bg-[#f2e7de] disabled:cursor-not-allowed disabled:opacity-70"
                disabled={deletingNotificationId === deleteConfirmNotification.id}
                onClick={() => setDeleteConfirmNotification(null)}
                type="button"
              >
                Cancel
              </button>
              <button
                className="rounded-full bg-[#a14b2f] px-5 py-3 text-sm font-semibold text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-70"
                disabled={deletingNotificationId === deleteConfirmNotification.id}
                onClick={() => void deleteNotification()}
                type="button"
              >
                {deletingNotificationId === deleteConfirmNotification.id
                  ? "Deleting..."
                  : "Delete notification"}
              </button>
            </div>
          </div>
        </div>
      )}
    </AppShell>
  );
}

function getNotificationTarget(
  notification: Notification,
  userRole: AppRole | undefined,
) {
  if (!notification.reference_id) {
    return null;
  }

  if (notification.reference_type === "report") {
    if (userRole === "department") {
      return `/department/reports/${notification.reference_id}`;
    }
    if (userRole === "municipality") {
      return `/municipality/reports/${notification.reference_id}`;
    }
    if (userRole === "citizen") {
      return `/citizen/report/${notification.reference_id}`;
    }
  }

  if (
    notification.reference_type === "department" &&
    userRole === "department"
  ) {
    return "/department/profile";
  }

  return null;
}

// Notification center — lists all user notifications with mark-read and mark-all-read actions.

import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
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
};

// Icon per notification type
const typeIcons: Record<string, string> = {
  new_report: "assignment",
  report_update: "update",
  verification_decision: "verified_user",
  announcement: "campaign",
};

export function NotificationsPage() {
  const navigate = useNavigate();
  const accessToken = useSessionStore((state) => state.accessToken);
  const userRole = useSessionStore((state) => state.user?.role);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(true);
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

  function fetchNotifications(showLoader = true) {
    if (showLoader) {
      setLoading(true);
    }

    return apiRequest<{ notifications: Notification[]; unread_count: number }>("/api/notifications")
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

  // Mark single notification read — optimistic with rollback
  async function markRead(id: string) {
    const prev = notifications;
    const prevCount = unreadCount;
    setNotifications((ns) => ns.map((n) => n.id === id ? { ...n, is_read: true } : n));
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

  return (
    <AppShell subtitle="Stay informed" title="Notifications">
      <div className="flex items-center justify-between mb-8">
        <p className="text-sm text-on-surface-variant">
          {unreadCount > 0 ? `${unreadCount} unread notification${unreadCount !== 1 ? "s" : ""}` : "All caught up"}
        </p>
        {unreadCount > 0 && (
          <Button variant="ghost" onClick={markAllRead}>
            <span className="material-symbols-outlined text-[16px] mr-1">done_all</span>
            Mark all read
          </Button>
        )}
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading notifications...
        </Card>
      ) : notifications.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">notifications_off</span>
          <p className="text-on-surface-variant">No notifications yet.</p>
        </Card>
      ) : (
        <div className="space-y-3">
          {notifications.map((n) => (
            <Card
              key={n.id}
              className={`cursor-pointer transition-all hover:shadow-glass ${!n.is_read ? "border-l-4 border-l-[#D97757]" : "opacity-70"}`}
              onClick={() => void handleNotificationClick(n)}
            >
              <div className="flex items-start gap-3">
                <div className={`flex-shrink-0 w-9 h-9 rounded-lg flex items-center justify-center ${!n.is_read ? "bg-[#ffdbd0] text-secondary" : "bg-surface-container text-on-surface-variant"}`}>
                  <span className="material-symbols-outlined text-[18px]">{typeIcons[n.type] ?? "notifications"}</span>
                </div>
                <div className="flex-grow min-w-0">
                  <div className="flex items-start justify-between gap-2">
                    <h3 className={`text-sm ${!n.is_read ? "font-semibold text-on-surface" : "text-on-surface-variant"}`}>{n.title}</h3>
                    <span className="text-[10px] text-outline shrink-0">{new Date(n.created_at).toLocaleString()}</span>
                  </div>
                  <p className="text-xs text-on-surface-variant mt-0.5">{n.message}</p>
                </div>
                {!n.is_read && (
                  <div className="w-2 h-2 rounded-full bg-[#D97757] shrink-0 mt-1.5" />
                )}
              </div>
            </Card>
          ))}
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

  if (notification.reference_type === "department" && userRole === "department") {
    return "/department/profile";
  }

  return null;
}

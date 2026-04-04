import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useRef } from "react";

import { useAppShellTheme } from "@/components/layout/app-shell-theme";
import { AppShell } from "@/components/layout/app-shell";
import { LocationMap } from "@/components/maps/location-map";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { useLocale } from "@/lib/i18n/locale-context";
import { subscribeToTable } from "@/lib/realtime/supabase";

type StatusHistory = {
  id: string;
  status?: string;
  new_status?: string;
  note?: string;
  notes?: string;
  created_at: string;
};

type TimelineEntry = {
  type: "status_change" | "department_response";
  timestamp: string;
  new_status?: string;
  old_status?: string;
  notes?: string;
  changed_by?: string;
  action?: string;
  department_name?: string;
  decline_reason?: string;
};

type DeptResponse = {
  department_name: string;
  action: string;
  notes?: string;
  decline_reason?: string;
  responded_at?: string;
};

type Report = {
  id: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string;
  latitude?: number;
  longitude?: number;
  is_escalated: boolean;
  is_mesh_origin?: boolean;
  image_urls?: string[] | string | null;
  created_at: string;
  updated_at: string;
};

type NotificationRecord = {
  id: string;
  user_id: string;
  reference_id?: string | null;
  reference_type?: string | null;
};

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

function MapWarningPulse({ isDarkMode }: { isDarkMode: boolean }) {
  const circleBorderColor = isDarkMode ? "rgba(255, 200, 170, 0.72)" : "rgba(255, 166, 120, 0.78)";
  const circleGlowColor = isDarkMode ? "rgba(255, 182, 145, 0.75)" : "rgba(235, 134, 84, 0.62)";

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute left-1/2 top-1/2 z-[520] h-40 w-40 -translate-x-1/2 -translate-y-[62%]"
    >
      <style>
        {`
          @keyframes dispatch-map-warning-pulse {
            0% {
              opacity: 0;
              width: 0px;
              height: 0px;
              transform: translate(-50%, -50%) scale(1);
            }

            10% {
              opacity: 0.55;
              transform: translate(-50%, -50%) scale(2);
            }

            100% {
              opacity: 0;
              width: 128px;
              height: 128px;
              transform: translate(-50%, -50%) scale(1);
            }
          }
        `}
      </style>

      {[0.2, 0.45, 0.8, 1.1].map((delay, index) => (
        <span
          key={index}
          className="absolute left-1/2 top-1/2 rounded-full"
          style={{
            width: 0,
            height: 0,
            opacity: 0,
            border: `1px solid ${circleBorderColor}`,
            boxShadow: `0 0 10px ${circleGlowColor}`,
            animation: `dispatch-map-warning-pulse 4s infinite linear`,
            animationDelay: `${delay}s`,
          }}
        />
      ))}

      <span
        className="absolute left-1/2 top-1/2 h-8 w-8 -translate-x-1/2 -translate-y-1/2 rounded-full"
        style={{
          background: "transparent",
          boxShadow: isDarkMode
            ? "0 0 48px rgba(228, 116, 63, 0.42)"
            : "0 0 42px rgba(219, 108, 58, 0.34)",
        }}
      />
    </div>
  );
}

const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]" },
  accepted: { bg: "bg-tertiary-container", text: "text-[#3a4e6a]" },
  responding: { bg: "bg-[#e5e2de]", text: "text-[#52524f]" },
  resolved: { bg: "bg-[#d4edda]", text: "text-[#155724]" },
};

const categoryIcons: Record<string, string> = {
  fire: "local_fire_department",
  flood: "water_drop",
  earthquake: "vibration",
  road_accident: "car_crash",
  medical: "medical_services",
  structural: "domain_disabled",
  other: "emergency",
};

function normalizeEvidenceImageUrl(url?: string | null) {
  if (!url) {
    return null;
  }

  const trimmed = url.trim().replace(/^['"]+|['"]+$/g, "");
  if (!trimmed) {
    return null;
  }

  if (/^https?:\/\//i.test(trimmed)) {
    return encodeURI(trimmed);
  }

  if (trimmed.startsWith("/")) {
    return encodeURI(trimmed);
  }

  return encodeURI(`/${trimmed.replace(/^\/+/, "")}`);
}

function parseEvidenceImageUrls(rawImageUrls?: string[] | string | null) {
  if (!rawImageUrls) {
    return [];
  }

  if (typeof rawImageUrls === "string") {
    const trimmed = rawImageUrls.trim();
    if (!trimmed) {
      return [];
    }

    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          return parsed
            .map((value) => normalizeEvidenceImageUrl(typeof value === "string" ? value : String(value)))
            .filter((url): url is string => Boolean(url));
        }
      } catch {
        // Fall through to more permissive parsing below.
      }
    }

    const splitValues = trimmed
      .split(/[\r\n,]+/)
      .map((value) => value.trim())
      .filter(Boolean);

    return splitValues
      .map((url) => normalizeEvidenceImageUrl(url))
      .filter((url): url is string => Boolean(url));
  }

  const expanded = rawImageUrls.flatMap((entry) => {
    if (typeof entry !== "string") {
      return [];
    }

    const trimmed = entry.trim();
    if (!trimmed) {
      return [];
    }

    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          return parsed.filter((value): value is string => typeof value === "string");
        }
      } catch {
        // Fall through to treat it as a direct string.
      }
    }

    return [trimmed];
  });

  return expanded
    .map((url) => normalizeEvidenceImageUrl(url))
    .filter((url): url is string => Boolean(url));
}

export function CitizenReportDetailPage() {
  const { reportId } = useParams<{ reportId: string }>();
  const accessToken = useSessionStore((state) => state.accessToken);
  const userId = useSessionStore((state) => state.user?.id ?? null);
  const { isDarkMode } = useAppShellTheme();
  const {
    t,
    getCategoryLabel,
    getSeverityLabel,
    getStatusLabel,
  } = useLocale();
  const [report, setReport] = useState<Report | null>(null);
  const [history, setHistory] = useState<StatusHistory[]>([]);
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [timelineProgressValue, setTimelineProgressValue] = useState<number | null>(null);
  const [resolvedLocations, setResolvedLocations] = useState<Record<string, string>>({});
  const progressAudioRef = useRef<HTMLAudioElement | null>(null);
  const previousTimelineProgressRef = useRef<number | null>(null);
  const resolvingLocationsRef = useRef(new Set<string>());

  const fetchReport = useCallback(
    (showLoader = true) => {
      if (!reportId) {
        return Promise.resolve();
      }
      if (showLoader) {
        setLoading(true);
      }

      return apiRequest<{
        report: Report;
        status_history: StatusHistory[];
        timeline?: TimelineEntry[];
        department_responses?: DeptResponse[];
      }>(`/api/reports/${reportId}`)
        .then((res) => {
          setReport(res.report);
          setHistory(res.status_history);
          setTimeline(res.timeline ?? []);
          setError(null);
        })
        .catch((err) => {
          setError(err instanceof Error ? err.message : t("detail.error"));
        })
        .finally(() => {
          if (showLoader) {
            setLoading(false);
          }
        });
    },
    [reportId, t],
  );

  useEffect(() => {
    if (!reportId || !userId) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      void fetchReport();
    }, 0);

    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [fetchReport, reportId]);

  useEffect(() => {
    previousTimelineProgressRef.current = null;
    setTimelineProgressValue(null);
  }, [reportId]);

  useEffect(() => {
    if (!reportId || loading) {
      return;
    }

    const intervalId = window.setInterval(() => {
      if (typeof document !== "undefined" && document.visibilityState === "hidden") {
        return;
      }

      void fetchReport(false);
    }, 3000);

    return () => {
      window.clearInterval(intervalId);
    };
  }, [fetchReport, loading, reportId]);

  useEffect(() => {
    if (!reportId) {
      return;
    }

    const reportSubscription = subscribeToTable(
      "incident_reports",
      () => {
        void fetchReport(false);
      },
      { accessToken, filter: `id=eq.${reportId}` },
    );
    const historySubscription = subscribeToTable(
      "report_status_history",
      () => {
        void fetchReport(false);
      },
      { accessToken, filter: `report_id=eq.${reportId}` },
    );
    const responseSubscription = subscribeToTable(
      "department_responses",
      () => {
        void fetchReport(false);
      },
      { accessToken, filter: `report_id=eq.${reportId}` },
    );
    const notificationSubscription = subscribeToTable(
      "notifications",
      (payload) => {
        const eventPayload = payload as {
          new?: NotificationRecord | null;
          old?: NotificationRecord | null;
        };
        const notification = eventPayload.new ?? eventPayload.old;
        if (
          notification?.user_id === userId &&
          notification.reference_type === "report" &&
          notification.reference_id === reportId
        ) {
          void fetchReport(false);
        }
      },
      { accessToken, filter: `user_id=eq.${userId}` },
    );

    return () => {
      reportSubscription.unsubscribe();
      historySubscription.unsubscribe();
      responseSubscription.unsubscribe();
      notificationSubscription.unsubscribe();
    };
  }, [accessToken, fetchReport, reportId, userId]);

  useEffect(() => {
    if (!report) {
      return;
    }

    const coordinateSources = new Set<string>();

    if (report.address && parseCoordinateLocation(report.address)) {
      coordinateSources.add(report.address.trim());
    }

    if (report.latitude !== undefined && report.latitude !== null && report.longitude !== undefined && report.longitude !== null) {
      coordinateSources.add(`${report.latitude}, ${report.longitude}`);
    }

    coordinateSources.forEach((location) => {
      if (resolvedLocations[location] || resolvingLocationsRef.current.has(location)) {
        return;
      }

      const parsed = parseCoordinateLocation(location);
      if (!parsed) {
        return;
      }

      resolvingLocationsRef.current.add(location);

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
            summarizeResolvedLocation(data) || data.display_name || formatCoordinateFallback(location);

          setResolvedLocations((current) => ({
            ...current,
            [location]: summary,
          }));
        })
        .catch(() => {
          setResolvedLocations((current) => ({
            ...current,
            [location]: formatCoordinateFallback(location),
          }));
        })
        .finally(() => {
          resolvingLocationsRef.current.delete(location);
      });
    });
  }, [report, resolvedLocations]);

  useEffect(() => {
    if (typeof Audio === "undefined") {
      return;
    }

    const audio = new Audio("/sounds/citizen-report-progress.mp3");
    audio.preload = "auto";
    progressAudioRef.current = audio;

    return () => {
      progressAudioRef.current = null;
    };
  }, []);

  useEffect(() => {
    if (!report) {
      previousTimelineProgressRef.current = null;
      setTimelineProgressValue(null);
      return;
    }

    const resolvedTimelineForProgress =
      timeline.length > 0
        ? timeline
        : history.map((entry) => ({
            type: "status_change" as const,
            timestamp: entry.created_at,
            new_status: entry.new_status ?? entry.status,
            notes: entry.notes ?? entry.note,
          }));
    const acceptedTimelineEntryForProgress = resolvedTimelineForProgress.find(
      (entry) =>
        (entry.type === "status_change" && (entry.new_status ?? "").toLowerCase() === "accepted") ||
        (entry.type === "department_response" && (entry.action ?? "").toLowerCase() === "accepted"),
    );
    const nextCompletedTimelineStepIndex =
      report.status === "resolved"
        ? 3
        : report.status === "responding"
          ? 2
          : acceptedTimelineEntryForProgress || report.status === "accepted"
            ? 1
            : 0;
    const nextTimelineStepIndex =
      report.status === "resolved" ? 3 : Math.min(nextCompletedTimelineStepIndex + 1, 3);
    const nextTimelineProgress = nextTimelineStepIndex / 3;

    setTimelineProgressValue((current) => {
      if (current === null) {
        return nextTimelineProgress;
      }

      return current === nextTimelineProgress ? current : nextTimelineProgress;
    });
  }, [history, report, timeline]);

  useEffect(() => {
    if (!report) {
      previousTimelineProgressRef.current = null;
      return;
    }

    const resolvedTimelineForProgress =
      timeline.length > 0
        ? timeline
        : history.map((entry) => ({
            type: "status_change" as const,
            timestamp: entry.created_at,
            new_status: entry.new_status ?? entry.status,
            notes: entry.notes ?? entry.note,
          }));
    const acceptedTimelineEntryForProgress = resolvedTimelineForProgress.find(
      (entry) =>
        (entry.type === "status_change" && (entry.new_status ?? "").toLowerCase() === "accepted") ||
        (entry.type === "department_response" && (entry.action ?? "").toLowerCase() === "accepted"),
    );
    const nextCompletedTimelineStepIndex =
      report.status === "resolved"
        ? 3
        : report.status === "responding"
          ? 2
          : acceptedTimelineEntryForProgress || report.status === "accepted"
            ? 1
            : 0;
    const nextTimelineStepIndex =
      report.status === "resolved" ? 3 : Math.min(nextCompletedTimelineStepIndex + 1, 3);
    const nextTimelineProgress = nextTimelineStepIndex / 3;
    const previousProgress = previousTimelineProgressRef.current;

    previousTimelineProgressRef.current = nextTimelineProgress;

    if (previousProgress === null || nextTimelineProgress <= previousProgress) {
      return;
    }

    const playbackDelay = window.setTimeout(() => {
      if (!progressAudioRef.current) {
        return;
      }

      progressAudioRef.current.currentTime = 0;
      void progressAudioRef.current.play().catch(() => undefined);
    }, 140);

    return () => {
      window.clearTimeout(playbackDelay);
    };
  }, [history, report, timeline]);

  if (loading) {
    return (
      <AppShell subtitle={t("detail.subtitle")} title={t("detail.loadingTitle")}>
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots sizeClassName="h-5 w-5" />
        </Card>
      </AppShell>
    );
  }

  if (error || !report) {
    return (
      <AppShell subtitle={t("detail.subtitle")} title={t("detail.errorTitle")}>
        <Card className="py-16 text-center text-error">{error ?? t("detail.notFound")}</Card>
      </AppShell>
    );
  }

  const style = statusStyles[report.status] ?? {
    bg: "bg-surface-container-highest",
    text: "text-on-surface-variant",
  };
  const resolvedTimeline =
    timeline.length > 0
      ? timeline
      : history.map((entry) => ({
          type: "status_change" as const,
          timestamp: entry.created_at,
          new_status: entry.new_status ?? entry.status,
          notes: entry.notes ?? entry.note,
        }));
  const pageClassName = isDarkMode ? "space-y-8 text-[#f4eee8]" : "space-y-8";
  const titleTextClassName = isDarkMode ? "text-[#f4eee8]" : "text-[#3f352f]";
  const mutedTextClassName = isDarkMode ? "text-[#c6b8ac]" : "text-on-surface-variant";
  const laneEffectClassName = isDarkMode
    ? "overflow-hidden rounded-[34px] border border-[#2d2926] bg-[#1f1c1a] p-3 shadow-[rgba(0,0,0,0.38)_0px_30px_50px_-12px_inset,rgba(255,255,255,0.03)_0px_18px_26px_-18px_inset]"
    : "overflow-hidden rounded-[34px] border border-[#ead8cc] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]";
  const panelClassName = isDarkMode
    ? "rounded-[30px] border border-[#34302b] bg-[#23211f] shadow-[14px_14px_28px_rgba(0,0,0,0.34),-10px_-10px_22px_rgba(255,255,255,0.02)]"
    : "rounded-[30px] border border-[#efd8d0] bg-[#fff8f3] shadow-[15px_15px_30px_rgba(208,191,179,0.78),-15px_-15px_30px_rgba(255,255,255,0.96)]";
  const mapShellClassName = isDarkMode
    ? "relative overflow-hidden rounded-[30px] border border-[#34302b] bg-[#23211f] shadow-[0_30px_50px_-20px_rgba(0,0,0,0.4)]"
    : "relative overflow-hidden rounded-[30px] border border-[#efd8d0] bg-[#fff8f3] shadow-[0_30px_50px_-20px_rgba(56,56,49,0.16)]";
  const evidenceTileClassName = isDarkMode
    ? "group overflow-hidden rounded-[22px] border border-[#34302b] bg-[#2a2724]"
    : "group overflow-hidden rounded-[22px] border border-[#ead8cc] bg-[#f4ece4]";
  const sectionLabelClassName =
    "text-[11px] font-bold uppercase tracking-[0.22em] text-[#d97757]";
  const floatingPanelClassName = isDarkMode
    ? "rounded-[28px] border border-[#3a342f] bg-[#23201d] shadow-[0_24px_56px_rgba(0,0,0,0.34)]"
    : "rounded-[28px] border border-[#edd8cb] bg-[#fff8f2] shadow-[0_24px_56px_rgba(92,60,41,0.14)]";
  const chipClassName = isDarkMode
    ? "border-[#5c463c] bg-[#2b241f] text-[#f3b08f]"
    : "border-[#e6cfc2] bg-[#fff1e8] text-[#8a4c31]";
  const strongTextClassName = isDarkMode ? "text-[#f4eee8]" : "text-on-surface";
  const mapBackdropClassName = isDarkMode
    ? "absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(24,24,23,0)_0%,rgba(24,24,23,0.1)_42%,rgba(24,24,23,0.55)_100%)]"
    : "absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(255,248,243,0)_0%,rgba(255,248,243,0.04)_45%,rgba(82,61,45,0.16)_100%)]";
  const mapMinHeightClassName =
    "min-h-[560px] lg:min-h-[700px] xl:min-h-[760px] 2xl:min-h-[calc(100vh-9.75rem)]";
  const coordinateSource = report.address && parseCoordinateLocation(report.address)
    ? report.address.trim()
    : report.latitude !== undefined &&
        report.latitude !== null &&
        report.longitude !== undefined &&
        report.longitude !== null
      ? `${report.latitude}, ${report.longitude}`
      : null;
  const resolvedReportLocation = coordinateSource
    ? resolvedLocations[coordinateSource] ?? formatCoordinateFallback(coordinateSource)
    : null;
  const reportLocationTitle =
    (report.address && !parseCoordinateLocation(report.address) ? report.address : null) ||
    resolvedReportLocation ||
    "Location Pending";
  const evidenceImageUrls = parseEvidenceImageUrls(report.image_urls);
  const acceptedTimelineEntry = resolvedTimeline.find(
    (entry) =>
      (entry.type === "status_change" && (entry.new_status ?? "").toLowerCase() === "accepted") ||
      (entry.type === "department_response" && (entry.action ?? "").toLowerCase() === "accepted"),
  );
  const respondingTimelineEntry = resolvedTimeline.find(
    (entry) => entry.type === "status_change" && (entry.new_status ?? "").toLowerCase() === "responding",
  );
  const resolvedStatusTimelineEntry = resolvedTimeline.find(
    (entry) => entry.type === "status_change" && (entry.new_status ?? "").toLowerCase() === "resolved",
  );
  const timelineMilestones = [
    {
      key: "pending",
      title: getStatusLabel("pending"),
      description: "Report submitted.",
      timestamp: report.created_at,
    },
    {
      key: "accepted",
      title: getStatusLabel("accepted"),
      description: acceptedTimelineEntry
        ? "A department has accepted your report."
        : "Awaiting department acceptance.",
      timestamp: acceptedTimelineEntry?.timestamp ?? null,
    },
    {
      key: "responding",
      title: getStatusLabel("responding"),
      description: respondingTimelineEntry
        ? "Emergency responders are moving to the incident."
        : "Response team deployment pending.",
      timestamp: respondingTimelineEntry?.timestamp ?? null,
    },
    {
      key: "resolved",
      title: getStatusLabel("resolved"),
      description: resolvedStatusTimelineEntry
        ? "This incident has been marked as resolved."
        : "Awaiting final resolution.",
      timestamp: resolvedStatusTimelineEntry?.timestamp ?? null,
    },
  ] as const;
  const completedTimelineStepIndex =
    report.status === "resolved"
      ? 3
      : report.status === "responding"
        ? 2
        : acceptedTimelineEntry || report.status === "accepted"
          ? 1
          : 0;
  const currentTimelineStepIndex =
    report.status === "resolved"
      ? 3
      : Math.min(completedTimelineStepIndex + 1, timelineMilestones.length - 1);
  const targetTimelineProgress =
    timelineMilestones.length > 1 ? currentTimelineStepIndex / (timelineMilestones.length - 1) : 0;
  const displayedTimelineProgress = timelineProgressValue ?? targetTimelineProgress;

  function renderTimelineStepper() {
    const baselineMutedClassName = isDarkMode ? "bg-[#4f4038]" : "bg-[#ecd7cd]";
    const circleSize = 36;
    const connectorInsetPercent = timelineMilestones.length > 1 ? 50 / timelineMilestones.length : 0;

    return (
      <div className="relative min-w-[680px] w-full">
        {timelineMilestones.length > 1 ? (
          <>
            <span
              aria-hidden="true"
              className={`absolute top-[2.45rem] h-[2px] ${baselineMutedClassName}`}
              style={{
                left: `${connectorInsetPercent}%`,
                right: `${connectorInsetPercent}%`,
              }}
            />
            <span
              aria-hidden="true"
              className="absolute top-[2.45rem] h-[2px] bg-[#d97757] transition-transform duration-700 ease-out"
              style={{
                left: `${connectorInsetPercent}%`,
                right: `${connectorInsetPercent}%`,
                transform: `scaleX(${displayedTimelineProgress})`,
                transformOrigin: "left center",
                transitionDuration: "700ms",
              }}
            />
          </>
        ) : null}
        <div className="flex w-full items-start">
          {timelineMilestones.map((milestone, index) => {
            const timestamp = milestone.timestamp ? new Date(milestone.timestamp) : null;
            const formattedDate = timestamp?.toLocaleDateString(undefined, {
              month: "short",
              day: "numeric",
            });
            const formattedTime = timestamp?.toLocaleTimeString([], {
              hour: "numeric",
              minute: "2-digit",
            });
            const isComplete =
              report?.status === "resolved" ? index <= completedTimelineStepIndex : index < currentTimelineStepIndex;
            const isCurrent = report?.status !== "resolved" && index === currentTimelineStepIndex;

            return (
              <div
                key={milestone.key}
                className="relative min-w-0 flex-1 px-2"
              >
                <p className={`text-center text-[10px] uppercase tracking-[0.18em] ${mutedTextClassName}`}>
                  {formattedDate && formattedTime ? `${formattedDate}, ${formattedTime}` : "--"}
                </p>
                <div className="mt-3 flex items-center justify-center">
                  <span
                    className={`relative z-[1] flex items-center justify-center overflow-hidden rounded-full border text-[12px] font-bold transition-all duration-500 ease-out ${
                      isComplete
                        ? "border-[#d97757] bg-[#d97757] text-white shadow-[0_0_0_6px_rgba(217,119,87,0.12)]"
                        : isCurrent
                          ? "border-[#d97757] bg-white text-[#d97757] shadow-[0_0_0_6px_rgba(217,119,87,0.1)]"
                          : isDarkMode
                            ? "border-[#5c4b42] bg-[#26211e] text-[#c2a999]"
                            : "border-[#ead8cc] bg-white text-[#c3a595]"
                    }`}
                    style={{ width: `${circleSize}px`, height: `${circleSize}px` }}
                  >
                    <span
                      className={`absolute inset-0 flex items-center justify-center transition-all duration-300 ease-out ${
                        isComplete ? "scale-75 opacity-0" : "scale-100 opacity-100"
                      }`}
                    >
                      {String(index + 1).padStart(2, "0")}
                    </span>
                    <svg
                      aria-hidden="true"
                      className={`h-[16px] w-[16px] transition-opacity duration-300 ease-out ${
                        isComplete ? "opacity-100" : "opacity-0"
                      }`}
                      viewBox="0 0 24 24"
                    >
                      <path
                        className="fill-none stroke-white stroke-[3] [stroke-linecap:round] [stroke-linejoin:round] transition-[stroke-dashoffset] duration-500 ease-out"
                        d="M6.5 12.5l3.5 3.5 7.5-8"
                        style={{
                          strokeDasharray: 22,
                          strokeDashoffset: isComplete ? 0 : 22,
                          transitionDelay: isComplete ? "120ms" : "0ms",
                        }}
                      />
                    </svg>
                  </span>
                </div>
                <div className="mt-3 text-center">
                  <p className={`text-sm font-semibold leading-5 ${strongTextClassName}`}>{milestone.title}</p>
                  <p className={`mt-1 text-xs leading-5 ${mutedTextClassName}`}>
                    {milestone.description}
                  </p>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    );
  }

  const overviewCard = (
    <Card className={`${floatingPanelClassName} p-6`}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className={sectionLabelClassName}>Incident Overview</p>
          <h2 className={`mt-2 font-headline text-[1.95rem] leading-none ${titleTextClassName}`}>
            {reportLocationTitle}
          </h2>
        </div>
        <span
          className={`rounded-full px-3 py-1.5 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}
        >
          {getStatusLabel(report.status)}
        </span>
      </div>

      <div className="mt-4 space-y-2">
        <div className={`flex items-center gap-2 text-sm ${mutedTextClassName}`}>
          <span className="material-symbols-outlined text-[16px] text-[#d97757]">location_on</span>
          {reportLocationTitle}
        </div>
        {report.latitude !== undefined && report.latitude !== null && report.longitude !== undefined && report.longitude !== null ? (
          <div className={`flex items-center gap-2 text-xs ${mutedTextClassName}`}>
            <span className="material-symbols-outlined text-[14px] text-[#d97757]">my_location</span>
            {`${report.latitude.toFixed(4)}° N, ${report.longitude.toFixed(4)}° E`}
          </div>
        ) : null}
        <div className={`flex items-center gap-2 text-sm ${mutedTextClassName}`}>
          <span className="material-symbols-outlined text-[16px] text-[#d97757]">schedule</span>
          Submitted {new Date(report.created_at).toLocaleString()}
        </div>
      </div>

      <div className="mt-6 space-y-5">
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <p className={sectionLabelClassName}>{t("detail.category")}</p>
            <div
              className={`mt-2 inline-flex items-center gap-2 rounded-full border px-3 py-2 text-sm font-semibold ${chipClassName}`}
            >
              <span className="material-symbols-outlined text-[16px]">
                {categoryIcons[report.category] ?? "emergency"}
              </span>
              {getCategoryLabel(report.category)}
            </div>
          </div>

          <div>
            <p className={sectionLabelClassName}>{t("detail.severity")}</p>
            <div
              className={`mt-2 inline-flex items-center gap-2 rounded-full border px-3 py-2 text-sm font-semibold ${chipClassName}`}
            >
              <span className="material-symbols-outlined text-[16px]">priority_high</span>
              {getSeverityLabel(report.severity)}
            </div>
          </div>
        </div>

        <div>
          <p className={sectionLabelClassName}>Original Description</p>
          <p className={`mt-2 text-sm leading-7 ${mutedTextClassName}`}>{report.description}</p>
        </div>

        {report.is_escalated && (
          <div
            className={`rounded-[20px] border px-4 py-3 text-sm ${
              isDarkMode
                ? "border-[#5c463c] bg-[#2b241f] text-[#f3b08f]"
                : "border-[#f1c4b5] bg-[#fff4ee] text-[#a14b2f]"
            }`}
          >
            Escalated to wider response coordination.
          </div>
        )}

        {evidenceImageUrls.length > 0 && (
          <div>
            <div className="flex items-center justify-between gap-3">
              <p className={sectionLabelClassName}>Evidence</p>
              <span className={`text-[11px] font-semibold uppercase tracking-[0.18em] ${mutedTextClassName}`}>
                {evidenceImageUrls.length} file{evidenceImageUrls.length > 1 ? "s" : ""}
              </span>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-3">
              {evidenceImageUrls.slice(0, 4).map((url, index) => (
                <div key={index} className={evidenceTileClassName}>
                  <img
                    alt={t("detail.reportImageAlt", { index: index + 1 })}
                    className="aspect-[1.18/1] w-full object-cover"
                    src={url}
                  />
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </Card>
  );

  const timelinePanel = (
    <Card className={`${floatingPanelClassName} p-4 xl:p-4 2xl:p-5`}>
      <p
        className={`text-center text-[12px] font-extrabold uppercase tracking-[0.28em] ${
          isDarkMode ? "text-[#f0b79d]" : "text-[#c8663f]"
        }`}
      >
        {t("detail.timeline")}
      </p>
      <div className="-mx-1 mt-3 overflow-x-auto pb-2">
        <div className="w-full px-2">
          {renderTimelineStepper()}
        </div>
      </div>
    </Card>
  );

  return (
    <AppShell
      hidePageHeading
      subtitle={t("detail.subtitle")}
      title={`Report #${report.id.slice(0, 8)}`}
    >
      <div className={pageClassName}>
        <div className="space-y-5">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#d97757]">
              Report Details
            </p>
            <h1 className={`mt-2 font-headline text-4xl md:text-5xl ${titleTextClassName}`}>
              Report #{report.id.slice(0, 8)}
            </h1>
          </div>
          <Link
            to="/citizen"
            className={`inline-flex items-center gap-1 text-sm transition-colors ${mutedTextClassName} ${
              isDarkMode ? "hover:text-[#f4eee8]" : "hover:text-on-surface"
            }`}
          >
            <span className="material-symbols-outlined text-[16px]">arrow_back</span>
            {t("detail.backToReports")}
          </Link>
          </div>

          <div className={laneEffectClassName}>
            {timelinePanel}
          </div>

          <div className={laneEffectClassName}>
            {report.latitude !== undefined && report.latitude !== null && report.longitude !== undefined && report.longitude !== null ? (
              <div className={`${mapShellClassName} ${mapMinHeightClassName}`}>
                <div className="absolute inset-0">
                  <LocationMap
                    latitude={report.latitude}
                    longitude={report.longitude}
                    mapClassName="h-full w-full"
                    wrapperClassName="h-full w-full rounded-none border-0"
                  />
                </div>
                <div className={mapBackdropClassName} />
                <MapWarningPulse isDarkMode={isDarkMode} />

                <div className="relative z-[400] flex h-full flex-col xl:hidden">
                  <div className="min-h-[250px] sm:min-h-[300px] lg:min-h-[360px]" />
                  <div className="mt-auto space-y-5 p-4 lg:p-5">
                    {overviewCard}
                  </div>
                </div>

                <div className="relative hidden h-full xl:block">
                  <div className="absolute right-6 top-6 z-[400] w-[360px]">
                    {overviewCard}
                  </div>
                </div>
              </div>
            ) : (
              <div className="space-y-5">
                <div className={`${mapShellClassName} ${mapMinHeightClassName}`}>
                  <Card
                    className={`${panelClassName} flex h-full min-h-[560px] flex-col items-center justify-center p-8 text-center`}
                  >
                    <span className="material-symbols-outlined mb-3 text-4xl text-[#d97757]">map</span>
                    <p className={`text-sm ${mutedTextClassName}`}>{t("detail.noGps")}</p>
                  </Card>
                </div>
                {overviewCard}
              </div>
            )}
          </div>
        </div>
      </div>
    </AppShell>
  );
}

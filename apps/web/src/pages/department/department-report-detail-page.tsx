// Department report detail — view report info, accept/decline, update status, response roster.

import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { useAppShellTheme } from "@/components/layout/app-shell-theme";
import { AppShell } from "@/components/layout/app-shell";
import { LocationMap } from "@/components/maps/location-map";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type Report = {
  id: string;
  title?: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string;
  latitude?: number | null;
  longitude?: number | null;
  created_at: string;
  updated_at?: string;
  image_urls?: string[] | string | null;
  is_escalated: boolean;
  reporter_id?: string;
  reporter_name?: string | null;
  reporter_phone?: string | null;
  reporter_avatar_url?: string | null;
};

type StatusEntry = {
  id: string;
  old_status?: string | null;
  new_status?: string;
  status?: string;
  notes?: string;
  note?: string;
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

type RosterEntry = {
  department_id: string;
  department_name: string;
  department_type: string;
  state: string;
  decline_reason?: string | null;
  notes?: string | null;
  responded_at?: string | null;
  is_requesting_department: boolean;
};

type ReportDetailResponse = {
  report: Report;
  status_history: StatusEntry[];
  timeline?: TimelineEntry[];
};

const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]" },
  accepted: { bg: "bg-tertiary-container", text: "text-[#3a4e6a]" },
  responding: { bg: "bg-[#e5e2de]", text: "text-[#52524f]" },
  resolved: { bg: "bg-[#d4edda]", text: "text-[#155724]" },
};

const rosterStateStyles: Record<string, string> = {
  accepted: "bg-green-100 text-green-800",
  declined: "bg-red-100 text-red-800",
  pending: "bg-yellow-100 text-yellow-800",
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

function formatCoordinatePair(latitude: number, longitude: number) {
  const latLabel = `${Math.abs(latitude).toFixed(4)}° ${latitude >= 0 ? "N" : "S"}`;
  const lngLabel = `${Math.abs(longitude).toFixed(4)}° ${longitude >= 0 ? "E" : "W"}`;

  return `${latLabel}, ${lngLabel}`;
}

void formatCoordinatePair;

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

function formatLabel(value?: string | null) {
  if (!value) {
    return "";
  }

  return value
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
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
            animation: "dispatch-map-warning-pulse 4s infinite linear",
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

export function DepartmentReportDetailPage() {
  const { reportId } = useParams<{ reportId: string }>();
  const accessToken = useSessionStore((state) => state.accessToken);
  const { isDarkMode } = useAppShellTheme();
  const [report, setReport] = useState<Report | null>(null);
  const [history, setHistory] = useState<StatusEntry[]>([]);
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [declineReason, setDeclineReason] = useState("");
  const [notes, setNotes] = useState("");
  const [showDeclineForm, setShowDeclineForm] = useState(false);
  const [showConfirmationCallHint, setShowConfirmationCallHint] = useState(false);
  const [activeImageViewer, setActiveImageViewer] = useState<{
    photos: string[];
    title: string;
    index: number;
  } | null>(null);
  const [timelineProgressValue, setTimelineProgressValue] = useState<number | null>(null);
  const [resolvedLocations, setResolvedLocations] = useState<Record<string, string>>({});
  const resolvingLocationsRef = useRef(new Set<string>());

  const fetchAll = useCallback(
    (showLoader = true) => {
      if (!reportId) {
        return Promise.resolve();
      }

      if (showLoader) {
        setLoading(true);
      }

      return Promise.all([
        apiRequest<ReportDetailResponse>(`/api/reports/${reportId}`),
        apiRequest<{ report: Report; responses: RosterEntry[] }>(`/api/departments/reports/${reportId}/responses`),
      ])
        .then(([detail, rosterRes]) => {
          setReport(detail.report);
          setHistory(detail.status_history);
          setTimeline(detail.timeline ?? []);
          setRoster(rosterRes.responses);
          setLoadError(null);
        })
        .catch((error) => {
          setLoadError(error instanceof Error ? error.message : "Failed to load report.");
        })
        .finally(() => {
          if (showLoader) {
            setLoading(false);
          }
        });
    },
    [reportId],
  );

  useEffect(() => {
    if (!reportId) {
      return;
    }

    void fetchAll();
  }, [fetchAll, reportId]);

  useEffect(() => {
    if (!reportId) {
      return;
    }

    const reportSubscription = subscribeToTable(
      "incident_reports",
      () => {
        void fetchAll(false);
      },
      { accessToken, filter: `id=eq.${reportId}` },
    );
    const responseSubscription = subscribeToTable(
      "department_responses",
      () => {
        void fetchAll(false);
      },
      { accessToken, filter: `report_id=eq.${reportId}` },
    );
    const historySubscription = subscribeToTable(
      "report_status_history",
      () => {
        void fetchAll(false);
      },
      { accessToken, filter: `report_id=eq.${reportId}` },
    );

    return () => {
      reportSubscription.unsubscribe();
      responseSubscription.unsubscribe();
      historySubscription.unsubscribe();
    };
  }, [accessToken, fetchAll, reportId]);

  useEffect(() => {
    if (!report) {
      return;
    }

    const coordinateSources = new Set<string>();

    if (report.address && parseCoordinateLocation(report.address)) {
      coordinateSources.add(report.address.trim());
    }

    if (
      report.latitude !== undefined &&
      report.latitude !== null &&
      report.longitude !== undefined &&
      report.longitude !== null
    ) {
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
    if (!report) {
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
    const ownResponseForProgress = roster.find((entry) => entry.is_requesting_department);
    const hasRespondedForProgress =
      ownResponseForProgress != null && ownResponseForProgress.state !== "pending";
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
          : acceptedTimelineEntryForProgress ||
              ownResponseForProgress?.state === "accepted" ||
              report.status === "accepted"
            ? 1
            : hasRespondedForProgress
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
  }, [history, report, roster, timeline]);

  async function handleAccept() {
    setActionLoading(true);
    setActionError(null);

    try {
      await apiRequest(`/api/departments/reports/${reportId}/accept`, {
        method: "POST",
        body: JSON.stringify({ notes: notes.trim() || undefined }),
      });
      setNotes("");
      setShowDeclineForm(false);
      setShowConfirmationCallHint(false);
      void fetchAll(false);
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Action failed.");
    } finally {
      setActionLoading(false);
    }
  }

  async function handleDecline() {
    if (!declineReason.trim()) {
      setActionError("Decline reason is required.");
      return;
    }

    setActionLoading(true);
    setActionError(null);

    try {
      await apiRequest(`/api/departments/reports/${reportId}/decline`, {
        method: "POST",
        body: JSON.stringify({
          decline_reason: declineReason.trim(),
          notes: notes.trim() || undefined,
        }),
      });
      setDeclineReason("");
      setNotes("");
      setShowDeclineForm(false);
      setShowConfirmationCallHint(false);
      void fetchAll(false);
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Action failed.");
    } finally {
      setActionLoading(false);
    }
  }

  async function handleStatusUpdate(newStatus: string) {
    setActionLoading(true);
    setActionError(null);

    try {
      await apiRequest(`/api/departments/reports/${reportId}/status`, {
        method: "PUT",
        body: JSON.stringify({ status: newStatus, notes: notes.trim() || undefined }),
      });
      setNotes("");
      void fetchAll(false);
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Action failed.");
    } finally {
      setActionLoading(false);
    }
  }

  function openEvidenceViewer(startIndex = 0) {
    if (evidenceImageUrls.length === 0) {
      return;
    }

    setActiveImageViewer({
      photos: evidenceImageUrls,
      title: reportHeading,
      index: startIndex,
    });
  }

  function shiftEvidenceViewer(direction: "prev" | "next") {
    setActiveImageViewer((current) => {
      if (!current || current.photos.length <= 1) {
        return current;
      }

      const delta = direction === "next" ? 1 : -1;
      const nextIndex = (current.index + delta + current.photos.length) % current.photos.length;

      return {
        ...current,
        index: nextIndex,
      };
    });
  }

  if (loading) {
    return (
      <AppShell subtitle="Incident response" title="Loading report...">
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots sizeClassName="h-5 w-5" />
        </Card>
      </AppShell>
    );
  }

  if (!report) {
    return (
      <AppShell subtitle="Incident response" title="Report not found">
        <Card className="py-16 text-center text-on-surface-variant">
          {loadError ?? "Report not found."}
        </Card>
      </AppShell>
    );
  }

  const style = statusStyles[report.status] ?? {
    bg: "bg-surface-container-highest",
    text: "text-on-surface-variant",
  };
  const ownResponse = roster.find((entry) => entry.is_requesting_department);
  const hasAccepted = ownResponse?.state === "accepted";
  const hasResponded = ownResponse != null && ownResponse.state !== "pending";
  const isOpen = report.status !== "resolved";
  const errorMessage = actionError ?? loadError;
  const resolvedTimeline =
    timeline.length > 0
      ? timeline
      : history.map((entry) => ({
          type: "status_change" as const,
          timestamp: entry.created_at,
          new_status: entry.new_status ?? entry.status,
          notes: entry.notes ?? entry.note,
        }));
  const parsedAddressCoordinates = report.address ? parseCoordinateLocation(report.address) : null;
  const mapLatitude = report.latitude ?? parsedAddressCoordinates?.lat ?? null;
  const mapLongitude = report.longitude ?? parsedAddressCoordinates?.lng ?? null;
  const coordinateSource =
    report.latitude !== undefined &&
    report.latitude !== null &&
    report.longitude !== undefined &&
    report.longitude !== null
      ? `${report.latitude}, ${report.longitude}`
      : report.address && parseCoordinateLocation(report.address)
        ? report.address.trim()
        : null;
  const resolvedReportLocation = coordinateSource
    ? resolvedLocations[coordinateSource] ?? formatCoordinateFallback(coordinateSource)
    : null;
  const reportLocationTitle =
    (report.address && !parseCoordinateLocation(report.address) ? report.address : null) ||
    resolvedReportLocation ||
    "Location Pending";
  const reportHeading = report.title?.trim() || report.description || reportLocationTitle;
  const evidenceImageUrls = parseEvidenceImageUrls(report.image_urls);
  const reporterName = report.reporter_name?.trim() || "Citizen Reporter";
  const reporterPhone = report.reporter_phone?.trim() || null;
  const reporterInitial = reporterName.charAt(0).toUpperCase() || "C";
  const pageClassName = isDarkMode ? "space-y-8 text-[#f4eee8]" : "space-y-8";
  const titleTextClassName = isDarkMode ? "text-[#f4eee8]" : "text-[#3f352f]";
  const mutedTextClassName = isDarkMode ? "text-[#c6b8ac]" : "text-on-surface-variant";
  const strongTextClassName = isDarkMode ? "text-[#f4eee8]" : "text-on-surface";
  const laneEffectClassName = isDarkMode
    ? "overflow-visible rounded-[34px] border border-[#2d2926] bg-[#1f1c1a] p-3 shadow-[rgba(0,0,0,0.38)_0px_30px_50px_-12px_inset,rgba(255,255,255,0.03)_0px_18px_26px_-18px_inset]"
    : "overflow-visible rounded-[34px] border border-[#ead8cc] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]";
  const panelClassName = isDarkMode
    ? "rounded-[30px] border border-[#34302b] bg-[#23211f] shadow-[14px_14px_28px_rgba(0,0,0,0.34),-10px_-10px_22px_rgba(255,255,255,0.02)]"
    : "rounded-[30px] border border-[#efd8d0] bg-[#fff8f3] shadow-[15px_15px_30px_rgba(208,191,179,0.78),-15px_-15px_30px_rgba(255,255,255,0.96)]";
  const floatingPanelClassName = isDarkMode
    ? "rounded-[28px] border border-[#3a342f] bg-[#23201d] shadow-[0_10px_22px_-12px_rgba(0,0,0,0.52),0_8px_18px_0_rgba(0,0,0,0.34)] transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#4a433d] hover:bg-[#292624] hover:shadow-[0_5px_5px_0_#00000026]"
    : "rounded-[28px] border border-[#edd8cb] bg-[#fff8f2] shadow-[0_8px_18px_-12px_rgba(120,78,58,0.42),0_5px_15px_0_#00000026] transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#e7c7b8] hover:bg-[#fffaf6] hover:shadow-[0_10px_22px_-12px_rgba(120,78,58,0.48),0_5px_5px_0_#00000026]";
  const mapShellClassName = isDarkMode
    ? "relative overflow-hidden rounded-[30px] border border-[#34302b] bg-[#23211f] shadow-[0_30px_50px_-20px_rgba(0,0,0,0.4)]"
    : "relative overflow-hidden rounded-[30px] border border-[#efd8d0] bg-[#fff8f3] shadow-[0_30px_50px_-20px_rgba(56,56,49,0.16)]";
  const mapBackdropClassName = isDarkMode
    ? "absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(24,24,23,0)_0%,rgba(24,24,23,0.08)_46%,rgba(24,24,23,0.42)_100%)]"
    : "absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(255,248,243,0)_0%,rgba(255,248,243,0.03)_46%,rgba(82,61,45,0.16)_100%)]";
  const mapMinHeightClassName =
      "min-h-[420px] lg:min-h-[500px] xl:min-h-[calc(100vh-15rem)]";
  const sectionLabelClassName =
    "text-[11px] font-bold uppercase tracking-[0.22em] text-[#d97757]";
  const sectionDividerClassName = isDarkMode ? "border-[#3a342f]" : "border-[#ead8cc]";
  const chipClassName = isDarkMode
    ? "border-[#5c463c] bg-[#2b241f] text-[#f3b08f]"
    : "border-[#e6cfc2] bg-[#fff1e8] text-[#8a4c31]";
  const responseInputClassName = isDarkMode
    ? "min-h-[92px] w-full rounded-[18px] border border-[#3d3632] bg-[#1d1a18] px-4 py-3 text-sm text-[#f4eee8] placeholder:text-[#8e7f73] focus:border-[#d97757] focus:outline-none"
    : "min-h-[92px] w-full rounded-[18px] border border-[#ead8cc] bg-[#f4ece4] px-4 py-3 text-sm text-[#51443b] placeholder:text-[#a59588] focus:border-[#d97757] focus:outline-none";
  const actionPanelSurfaceClassName = isDarkMode
    ? "rounded-[22px] border border-[#342d29] bg-[#1f1c19]"
    : "rounded-[22px] border border-[#efd8cb] bg-[#fdf5ef]";
  const actionPrioritySurfaceClassName = isDarkMode
    ? "rounded-[24px] border border-[#5f4539] bg-[#2b211d] shadow-[0_18px_35px_-22px_rgba(0,0,0,0.62)]"
    : "rounded-[24px] border border-[#efc6b8] bg-[#fff2e9] shadow-[0_18px_35px_-22px_rgba(161,75,47,0.32)]";
  const actionSupportSurfaceClassName = isDarkMode
    ? "rounded-[22px] border border-[#433832] bg-[#211d1a]"
    : "rounded-[22px] border border-[#ead8cc] bg-[#fffaf5]";
  const evidenceTileClassName = isDarkMode
    ? "group overflow-hidden rounded-[20px] border border-[#34302b] bg-[#2a2724]"
    : "group overflow-hidden rounded-[20px] border border-[#ead8cc] bg-[#f4ece4]";
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
      title: "Pending",
      description: "Report submitted.",
      timestamp: report.created_at,
    },
    {
      key: "accepted",
      title: "Accepted",
      description: acceptedTimelineEntry
        ? "Department formally accepted the incident."
        : "Awaiting department acceptance.",
      timestamp: acceptedTimelineEntry?.timestamp ?? null,
    },
    {
      key: "responding",
      title: "Responding",
      description: respondingTimelineEntry ? "Report marked as responding." : "Dispatch activity pending.",
      timestamp: respondingTimelineEntry?.timestamp ?? null,
    },
    {
      key: "resolved",
      title: "Resolved",
      description: resolvedStatusTimelineEntry ? "Report marked as resolved." : "Awaiting final resolution.",
      timestamp: resolvedStatusTimelineEntry?.timestamp ?? null,
    },
  ] as const;
  const completedTimelineStepIndex =
    report.status === "resolved"
      ? 3
      : report.status === "responding"
        ? 2
        : acceptedTimelineEntry || ownResponse?.state === "accepted" || report.status === "accepted"
          ? 1
          : hasResponded
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
      const isComplete = report?.status === "resolved" ? index <= completedTimelineStepIndex : index < currentTimelineStepIndex;
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
    <Card className={`${floatingPanelClassName} p-3.5 xl:p-3.5 2xl:p-4`}>
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className={sectionLabelClassName}>Incident Overview</p>
          <h2 className={`mt-1.5 break-words font-headline text-[1.38rem] leading-[0.98] xl:text-[1.48rem] 2xl:text-[1.62rem] ${titleTextClassName}`}>
            {reportHeading}
          </h2>
        </div>
        <span
          className={`rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}
        >
          {formatLabel(report.status)}
        </span>
      </div>

      <div className={`mt-3 border-t pt-3 ${sectionDividerClassName}`}>
        <div className={`flex items-start gap-2 text-[13px] ${mutedTextClassName}`}>
          <span className="material-symbols-outlined mt-0.5 text-[16px] text-[#d97757]">location_on</span>
          <span>{reportLocationTitle}</span>
        </div>
        <div className={`mt-2 flex items-start gap-2 text-[13px] ${mutedTextClassName}`}>
          <span className="material-symbols-outlined mt-0.5 text-[16px] text-[#d97757]">schedule</span>
          <span>Submitted {new Date(report.created_at).toLocaleString()}</span>
        </div>
      </div>

      <div className={`mt-3 border-t pt-3 ${sectionDividerClassName}`}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <p className={sectionLabelClassName}>Incident ID</p>
            <p className={`mt-1 text-[13px] font-semibold ${strongTextClassName}`}>#{report.id.slice(0, 8)}</p>
          </div>
          <div className={`sm:border-l sm:pl-4 ${sectionDividerClassName}`}>
            <p className={sectionLabelClassName}>Department State</p>
            <p className={`mt-1 text-[13px] font-semibold ${strongTextClassName}`}>
              {ownResponse ? formatLabel(ownResponse.state) : "Pending response"}
            </p>
          </div>
        </div>
      </div>

      <div className={`mt-3 border-t pt-3 ${sectionDividerClassName}`}>
        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <p className={sectionLabelClassName}>Category</p>
            <div
              className={`mt-1.5 inline-flex items-center gap-2 rounded-full border px-2.5 py-1.5 text-[13px] font-semibold ${chipClassName}`}
            >
              <span className="material-symbols-outlined text-[16px]">
                {categoryIcons[report.category] ?? "emergency"}
              </span>
              {formatLabel(report.category)}
            </div>
          </div>

          <div className={`sm:border-l sm:pl-4 ${sectionDividerClassName}`}>
            <p className={sectionLabelClassName}>Severity</p>
            <div
              className={`mt-1.5 inline-flex items-center gap-2 rounded-full border px-2.5 py-1.5 text-[13px] font-semibold ${chipClassName}`}
            >
              <span className="material-symbols-outlined text-[16px]">priority_high</span>
              {formatLabel(report.severity)}
            </div>
          </div>
        </div>
      </div>

      <div className={`mt-3 border-t pt-3 ${sectionDividerClassName}`}>
        <div className="flex items-center gap-3">
          <div
            className={`flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full ${
              isDarkMode ? "bg-[#2c2521] text-[#f3b08f]" : "bg-[#f7e7dd] text-[#a14b2f]"
            }`}
          >
            {report.reporter_avatar_url ? (
              <img
                alt={`${reporterName} avatar`}
                className="h-full w-full object-cover"
                src={report.reporter_avatar_url}
              />
            ) : (
              <span className="text-sm font-bold">{reporterInitial}</span>
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className={sectionLabelClassName}>Reported By</p>
            <p className={`mt-1 truncate text-[13px] font-semibold ${strongTextClassName}`}>{reporterName}</p>
            <p className={`mt-0.5 text-[12px] ${mutedTextClassName}`}>
              {reporterPhone ?? "No contact number submitted."}
            </p>
          </div>
          {reporterPhone ? (
            <a
              className={`inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-full border transition-colors ${
                isDarkMode
                  ? "border-[#5c463c] bg-[#2b241f] text-[#f3b08f] hover:bg-[#332925]"
                  : "border-[#efd0c0] bg-[#fff4ec] text-[#c8663f] hover:bg-[#ffece1]"
              }`}
              href={`tel:${reporterPhone}`}
              title={`Call ${reporterName}`}
            >
              <span className="material-symbols-outlined text-[18px]">call</span>
            </a>
          ) : null}
        </div>
      </div>

      {report.is_escalated ? (
        <div
          className={`mt-3 rounded-[16px] border px-3.5 py-2.5 text-[13px] ${
            isDarkMode
              ? "border-[#5c463c] bg-[#2b241f] text-[#f3b08f]"
              : "border-[#f1c4b5] bg-[#fff4ee] text-[#a14b2f]"
          }`}
        >
          Escalated to wider response coordination.
        </div>
      ) : null}

      <div className={`mt-3 border-t pt-3 ${sectionDividerClassName}`}>
        <div className="flex items-center justify-between gap-3">
          <p className={sectionLabelClassName}>Evidence</p>
          <span className={`text-[11px] font-semibold uppercase tracking-[0.18em] ${mutedTextClassName}`}>
            {evidenceImageUrls.length} file{evidenceImageUrls.length === 1 ? "" : "s"}
          </span>
        </div>
        {evidenceImageUrls.length > 0 ? (
          <button
            type="button"
            className={`mt-3 w-full text-left transition-transform duration-200 hover:scale-[1.01] ${evidenceTileClassName}`}
            onClick={() => openEvidenceViewer(0)}
          >
            <div className="relative">
              <img
                alt="Evidence preview"
                className="aspect-[2.1/1] w-full object-cover"
                src={evidenceImageUrls[0]}
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/45 via-black/10 to-transparent" />
              <div className="absolute bottom-3 left-3 right-3 flex items-end justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-[10px] font-bold uppercase tracking-[0.22em] text-white/80">
                    Evidence Viewer
                  </p>
                  <p className="mt-1 text-sm font-semibold text-white">
                    Tap to inspect submitted files
                  </p>
                </div>
                <span className="shrink-0 rounded-full bg-white/18 px-3 py-1.5 text-[11px] font-bold uppercase tracking-[0.18em] text-white backdrop-blur-sm">
                  {evidenceImageUrls.length} file{evidenceImageUrls.length === 1 ? "" : "s"}
                </span>
              </div>
            </div>
          </button>
        ) : (
          <div className={`mt-3 rounded-[18px] border px-4 py-4 text-sm ${chipClassName}`}>
            No evidence uploaded for this incident yet.
          </div>
        )}
      </div>
    </Card>
  );

  const actionsCard = (
      <Card className={`${floatingPanelClassName} p-4 xl:p-4 2xl:p-5`}>
        <div className="space-y-6">
        <div>
          <p className={sectionLabelClassName}>Response Actions</p>
          <p className={`mt-2 text-sm leading-6 ${mutedTextClassName}`}>
            Coordinate how your department will handle this incident while keeping the response roster updated.
          </p>
        </div>

        {isOpen ? (
          <div className="space-y-4">
            {!hasResponded ? (
              <>
                <div className={`space-y-4 p-5 ${actionPrioritySurfaceClassName}`}>
                  <div className="space-y-2 text-center">
                    <p className={sectionLabelClassName}>Verification Step</p>
                    <h3 className={`font-headline text-[1.55rem] leading-tight ${titleTextClassName}`}>
                      Confirm before dispatch
                    </h3>
                    <p className={`mx-auto max-w-md text-sm leading-6 ${mutedTextClassName}`}>
                      Use a quick callback step for suspicious, incomplete, or prank submissions before your unit
                      formally accepts the incident.
                    </p>
                  </div>

                  <div className="flex justify-center">
                    <Button
                      className={`min-h-[56px] w-full max-w-[320px] justify-center rounded-[18px] px-6 text-sm font-semibold normal-case tracking-normal shadow-none ${
                        isDarkMode
                          ? "border-[#5a473d] bg-transparent text-[#f3b08f] hover:bg-[#2b221e]"
                          : "border-[#efd5c8] bg-transparent text-[#a14b2f] hover:bg-[#fff7f1]"
                      }`}
                      disabled={actionLoading}
                      onClick={() => setShowConfirmationCallHint((current) => !current)}
                      variant="outline"
                    >
                      <span className="material-symbols-outlined mr-2 text-[18px]">call</span>
                      Call User for Confirmation
                    </Button>
                  </div>

                  {showConfirmationCallHint ? (
                    <div className={`rounded-[18px] border px-4 py-4 text-sm ${actionSupportSurfaceClassName}`}>
                      <div className="flex items-start gap-3">
                        <span className="material-symbols-outlined text-[18px] text-[#d97757]">info</span>
                        <div className={`space-y-1 ${mutedTextClassName}`}>
                          <p className={`font-semibold ${strongTextClassName}`}>Temporary placeholder</p>
                          <p>
                            Voice verification is not wired yet. Keep this step visible for now so operators can do
                            manual confirmation before accepting a suspicious report.
                          </p>
                        </div>
                      </div>
                    </div>
                  ) : null}
                </div>

                <div className={`space-y-4 p-5 ${actionPanelSurfaceClassName}`}>
                  <div className="space-y-2 text-center">
                    <p className={sectionLabelClassName}>Decision Console</p>
                    <p className={`mx-auto max-w-md text-sm leading-6 ${mutedTextClassName}`}>
                      Accept the report to place your department into the active response roster, or decline it with a
                      clear reason for coordination.
                    </p>
                  </div>

                  <div>
                    <label className={sectionLabelClassName}>Notes (Optional)</label>
                    <textarea
                      className={`mt-2 ${responseInputClassName}`}
                      onChange={(event) => setNotes(event.target.value)}
                      placeholder="Add coordination notes..."
                      value={notes}
                    />
                  </div>

                  <div className="flex flex-col items-center gap-3">
                    <Button
                      className="min-h-[58px] w-full max-w-[320px] justify-center rounded-[20px] px-6 text-sm shadow-[0_20px_34px_-22px_rgba(161,75,47,0.95)]"
                      disabled={actionLoading}
                      onClick={handleAccept}
                      variant="secondary"
                    >
                      <span className="material-symbols-outlined mr-2 text-[18px]">check_circle</span>
                      Accept Incident
                    </Button>
                    <Button
                      className="min-h-[52px] w-full max-w-[240px] justify-center rounded-[18px] px-6 text-sm font-semibold normal-case tracking-normal"
                      disabled={actionLoading}
                      onClick={() => setShowDeclineForm((current) => !current)}
                      variant="outline"
                    >
                      <span className="material-symbols-outlined mr-2 text-[18px]">cancel</span>
                      Decline Report
                    </Button>
                  </div>

                  {showDeclineForm ? (
                    <div className={`space-y-3 rounded-[18px] border p-4 ${chipClassName}`}>
                      <div>
                        <label className={sectionLabelClassName}>Decline Reason</label>
                        <textarea
                          className={`mt-2 ${responseInputClassName}`}
                          onChange={(event) => setDeclineReason(event.target.value)}
                          placeholder="Why are you declining?"
                          value={declineReason}
                        />
                      </div>
                      <div className="flex flex-wrap justify-center gap-3">
                        <Button disabled={actionLoading} onClick={handleDecline}>
                          Confirm Decline
                        </Button>
                        <Button
                          disabled={actionLoading}
                          onClick={() => setShowDeclineForm(false)}
                          variant="ghost"
                        >
                          Cancel
                        </Button>
                      </div>
                    </div>
                  ) : null}
                </div>
              </>
            ) : hasAccepted ? (
              <div className={`space-y-5 p-5 ${actionPrioritySurfaceClassName}`}>
                <div className="space-y-2 text-center">
                  <p className={sectionLabelClassName}>Operational Control</p>
                  <h3 className={`font-headline text-[1.6rem] leading-tight ${titleTextClassName}`}>
                    {report.status === "accepted" ? "Prepare the field response" : "Close the response loop"}
                  </h3>
                  <p className={`mx-auto max-w-md text-sm leading-6 ${mutedTextClassName}`}>
                    {report.status === "accepted"
                      ? "Your department is now assigned. Move the incident into live response when the team is mobilized."
                      : "Your team is already in motion. Resolve the incident once the scene is stabilized and cleared."}
                  </p>
                </div>

                <div>
                  <label className={sectionLabelClassName}>Notes (Optional)</label>
                  <textarea
                    className={`mt-2 ${responseInputClassName}`}
                    onChange={(event) => setNotes(event.target.value)}
                    placeholder="Add a field note before updating status..."
                    value={notes}
                  />
                </div>

                <div className="flex justify-center">
                  {report.status === "accepted" ? (
                    <Button
                      className="min-h-[60px] w-full max-w-[340px] justify-center rounded-[20px] px-8 text-sm shadow-[0_22px_36px_-24px_rgba(161,75,47,0.95)]"
                      disabled={actionLoading}
                      onClick={() => handleStatusUpdate("responding")}
                      variant="secondary"
                    >
                      <span className="material-symbols-outlined mr-2 text-[18px]">directions_run</span>
                      Mark Responding
                    </Button>
                  ) : null}
                  {report.status === "responding" ? (
                    <Button
                      className="min-h-[60px] w-full max-w-[340px] justify-center rounded-[20px] px-8 text-sm shadow-[0_22px_36px_-24px_rgba(161,75,47,0.95)]"
                      disabled={actionLoading}
                      onClick={() => handleStatusUpdate("resolved")}
                      variant="secondary"
                    >
                      <span className="material-symbols-outlined mr-2 text-[18px]">task_alt</span>
                      Mark Resolved
                    </Button>
                  ) : null}
                </div>

              </div>
            ) : (
              <div className={`p-4 text-sm italic ${actionPanelSurfaceClassName} ${mutedTextClassName}`}>
                Your department already declined this report.
              </div>
            )}
          </div>
        ) : (
          <div className={`p-4 text-sm ${actionPanelSurfaceClassName} ${mutedTextClassName}`}>
            This incident is already resolved. Response actions are locked.
          </div>
        )}

        <div className="space-y-3 border-t border-[#ead8cc] pt-5 dark:border-[#3a342f]">
          <div className="flex items-center justify-between gap-3">
            <p className={sectionLabelClassName}>Department Responses</p>
            <span className={`text-[11px] font-semibold uppercase tracking-[0.18em] ${mutedTextClassName}`}>
              {roster.length} dept{roster.length === 1 ? "" : "s"}
            </span>
          </div>
          <div className="space-y-3">
            {roster.length > 0 ? (
              roster.map((entry) => (
                <div
                  key={entry.department_id}
                  className={`flex items-start justify-between gap-3 rounded-[18px] border px-4 py-3 ${
                    isDarkMode ? "border-[#3a342f] bg-[#1f1c19]" : "border-[#edd8cb] bg-[#fffaf5]"
                  }`}
                >
                  <div className="min-w-0">
                    <p className={`text-sm font-semibold ${strongTextClassName}`}>
                      {entry.department_name}
                      {entry.is_requesting_department ? (
                        <span className="ml-1 text-[10px] uppercase tracking-[0.14em] text-[#d97757]">(you)</span>
                      ) : null}
                    </p>
                    <p className={`text-xs capitalize ${mutedTextClassName}`}>{entry.department_type}</p>
                    {entry.notes ? (
                      <p className={`mt-1 text-xs ${mutedTextClassName}`}>{entry.notes}</p>
                    ) : null}
                    {entry.decline_reason ? (
                      <p className="mt-1 text-xs text-red-700">Reason: {entry.decline_reason}</p>
                    ) : null}
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${
                      rosterStateStyles[entry.state] ?? "bg-surface-container-highest text-on-surface-variant"
                    }`}
                  >
                    {entry.state}
                  </span>
                </div>
              ))
            ) : (
              <div className={`rounded-[18px] border px-4 py-4 text-sm ${chipClassName}`}>
                No departments have responded yet.
              </div>
            )}
          </div>
        </div>
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
        Report Timeline
      </p>
      <div className="-mx-1 mt-3 overflow-x-auto pb-2">
        <div className="w-full px-2">
          {renderTimelineStepper()}
        </div>
      </div>
    </Card>
  );

  return (
    <>
      <AppShell
        hidePageHeading
        subtitle="Incident response"
        title={`Report #${report.id.slice(0, 8)}`}
      >
        <div className={pageClassName}>
        <div className="space-y-5">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#d97757]">
                Incident Response
              </p>
              <h1 className={`mt-2 font-headline font-semibold text-4xl md:text-5xl ${titleTextClassName}`}>
                Report #{report.id.slice(0, 8)}
              </h1>
            </div>
            <Link
              className={`inline-flex items-center gap-1 text-sm transition-colors ${mutedTextClassName} ${
                isDarkMode ? "hover:text-[#f4eee8]" : "hover:text-on-surface"
              }`}
              to="/department/reports"
            >
              <span className="material-symbols-outlined text-[16px]">arrow_back</span>
              Back to Board
            </Link>
          </div>
          <div className={`border-t ${isDarkMode ? "border-[#3a342f]" : "border-[#ead8cc]"}`} />
        </div>

        {errorMessage ? (
          <div className="rounded-md border border-error/20 bg-error-container/20 px-4 py-3 text-sm text-error">
            {errorMessage}
          </div>
        ) : null}

          <div className="space-y-5">
            <div className={laneEffectClassName}>
              {timelinePanel}
            </div>

            <div className={laneEffectClassName}>
              {mapLatitude !== null && mapLongitude !== null ? (
                <div className={`${mapShellClassName} ${mapMinHeightClassName}`}>
                  <div className="absolute inset-0 z-0">
                    <LocationMap
                      latitude={mapLatitude}
                      longitude={mapLongitude}
                      mapClassName="h-full w-full"
                      wrapperClassName="h-full w-full rounded-none border-0"
                    />
                  </div>
                  <div className={`${mapBackdropClassName} z-[100]`} />
                  <MapWarningPulse isDarkMode={isDarkMode} />

                  <div className="absolute inset-x-0 bottom-0 z-[400] flex max-h-full flex-col xl:hidden">
                    <div className="min-h-[230px] shrink-0 sm:min-h-[290px] lg:min-h-[340px]" />
                    <div className="mt-auto min-h-0 max-h-[calc(100%-11rem)] space-y-5 overflow-y-auto overscroll-contain p-4 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden lg:max-h-[calc(100%-14rem)] lg:p-5">
                      {overviewCard}
                      {actionsCard}
                    </div>
                  </div>

                  <div className="absolute bottom-5 right-5 top-5 z-[400] hidden w-[min(23.5rem,calc(100%-2.5rem))] xl:block">
                    <div className="h-full min-h-0 space-y-4 overflow-y-auto overscroll-contain pr-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                      {overviewCard}
                      {actionsCard}
                    </div>
                  </div>
                </div>
              ) : (
                <div className="space-y-5">
                  <Card
                    className={`${panelClassName} ${mapMinHeightClassName} flex min-w-0 flex-col items-center justify-center p-8 text-center`}
                  >
                    <span className="material-symbols-outlined mb-3 text-4xl text-[#d97757]">map</span>
                    <p className={`text-sm ${mutedTextClassName}`}>
                      GPS coordinates are unavailable for this report.
                    </p>
                  </Card>
                  {overviewCard}
                  {actionsCard}
                </div>
              )}
            </div>
          </div>
        </div>
      </AppShell>
      {activeImageViewer ? (
        <div className="fixed inset-0 z-[72] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md md:p-8">
          <button
            aria-label="Close image viewer"
            className="absolute left-4 top-4 flex h-11 w-11 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
            onClick={() => setActiveImageViewer(null)}
            type="button"
          >
            <span className="material-symbols-outlined">close</span>
          </button>
          {activeImageViewer.photos.length > 1 ? (
            <button
              aria-label="Previous image"
              className="absolute left-4 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
              onClick={() => shiftEvidenceViewer("prev")}
              type="button"
            >
              <span className="material-symbols-outlined">chevron_left</span>
            </button>
          ) : null}
          <div className="flex max-h-full max-w-[min(92vw,960px)] flex-col items-center gap-4">
            <img
              alt={`${activeImageViewer.title} image ${activeImageViewer.index + 1}`}
              className="max-h-[78vh] w-auto max-w-full rounded-[28px] object-contain shadow-[0_24px_60px_rgba(0,0,0,0.4)]"
              src={activeImageViewer.photos[activeImageViewer.index]}
            />
            {activeImageViewer.photos.length > 1 ? (
              <div className="rounded-full bg-white/10 px-4 py-2 text-sm font-medium text-white backdrop-blur-sm">
                {activeImageViewer.index + 1} / {activeImageViewer.photos.length}
              </div>
            ) : null}
          </div>
          {activeImageViewer.photos.length > 1 ? (
            <button
              aria-label="Next image"
              className="absolute right-4 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
              onClick={() => shiftEvidenceViewer("next")}
              type="button"
            >
              <span className="material-symbols-outlined">chevron_right</span>
            </button>
          ) : null}
        </div>
      ) : null}
    </>
    );
  }

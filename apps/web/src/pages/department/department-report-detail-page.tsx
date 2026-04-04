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
  const pageClassName = isDarkMode ? "space-y-8 text-[#f4eee8]" : "space-y-8";
  const titleTextClassName = isDarkMode ? "text-[#f4eee8]" : "text-[#3f352f]";
  const mutedTextClassName = isDarkMode ? "text-[#c6b8ac]" : "text-on-surface-variant";
  const strongTextClassName = isDarkMode ? "text-[#f4eee8]" : "text-on-surface";
  const laneEffectClassName = isDarkMode
    ? "overflow-hidden rounded-[34px] border border-[#2d2926] bg-[#1f1c1a] p-3 shadow-[rgba(0,0,0,0.38)_0px_30px_50px_-12px_inset,rgba(255,255,255,0.03)_0px_18px_26px_-18px_inset]"
    : "overflow-hidden rounded-[34px] border border-[#ead8cc] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]";
  const panelClassName = isDarkMode
    ? "rounded-[30px] border border-[#34302b] bg-[#23211f] shadow-[14px_14px_28px_rgba(0,0,0,0.34),-10px_-10px_22px_rgba(255,255,255,0.02)]"
    : "rounded-[30px] border border-[#efd8d0] bg-[#fff8f3] shadow-[15px_15px_30px_rgba(208,191,179,0.78),-15px_-15px_30px_rgba(255,255,255,0.96)]";
  const floatingPanelClassName = isDarkMode
    ? "rounded-[28px] border border-[#3a342f] bg-[#23201d] shadow-[0_24px_56px_rgba(0,0,0,0.34)]"
    : "rounded-[28px] border border-[#edd8cb] bg-[#fff8f2] shadow-[0_24px_56px_rgba(92,60,41,0.14)]";
  const mapShellClassName = isDarkMode
    ? "relative overflow-hidden rounded-[30px] border border-[#34302b] bg-[#23211f] shadow-[0_30px_50px_-20px_rgba(0,0,0,0.4)]"
    : "relative overflow-hidden rounded-[30px] border border-[#efd8d0] bg-[#fff8f3] shadow-[0_30px_50px_-20px_rgba(56,56,49,0.16)]";
  const mapBackdropClassName = isDarkMode
    ? "absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(24,24,23,0)_0%,rgba(24,24,23,0.08)_46%,rgba(24,24,23,0.42)_100%)]"
    : "absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(255,248,243,0)_0%,rgba(255,248,243,0.03)_46%,rgba(82,61,45,0.16)_100%)]";
  const mapMinHeightClassName =
      "min-h-[460px] lg:min-h-[560px] xl:min-h-[calc(100vh-12rem)]";
  const sectionLabelClassName =
    "text-[11px] font-bold uppercase tracking-[0.22em] text-[#d97757]";
  const chipClassName = isDarkMode
    ? "border-[#5c463c] bg-[#2b241f] text-[#f3b08f]"
    : "border-[#e6cfc2] bg-[#fff1e8] text-[#8a4c31]";
  const responseInputClassName = isDarkMode
    ? "min-h-[92px] w-full rounded-[18px] border border-[#3d3632] bg-[#1d1a18] px-4 py-3 text-sm text-[#f4eee8] placeholder:text-[#8e7f73] focus:border-[#d97757] focus:outline-none"
    : "min-h-[92px] w-full rounded-[18px] border border-[#ead8cc] bg-[#f4ece4] px-4 py-3 text-sm text-[#51443b] placeholder:text-[#a59588] focus:border-[#d97757] focus:outline-none";
  const actionPanelSurfaceClassName = isDarkMode
    ? "rounded-[22px] border border-[#342d29] bg-[#1f1c19]"
    : "rounded-[22px] border border-[#efd8cb] bg-[#fdf5ef]";
  const evidenceTileClassName = isDarkMode
    ? "group overflow-hidden rounded-[20px] border border-[#34302b] bg-[#2a2724]"
    : "group overflow-hidden rounded-[20px] border border-[#ead8cc] bg-[#f4ece4]";

  const overviewCard = (
      <Card className={`${floatingPanelClassName} p-5 xl:p-5 2xl:p-6`}>
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className={sectionLabelClassName}>Incident Overview</p>
          <h2 className={`mt-2 break-words font-headline text-[1.65rem] leading-[0.95] xl:text-[1.72rem] 2xl:text-[1.95rem] ${titleTextClassName}`}>
              {reportHeading}
            </h2>
          </div>
        <span
          className={`rounded-full px-3 py-1.5 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}
        >
          {formatLabel(report.status)}
        </span>
      </div>

        <div className="mt-5 space-y-2.5">
          <div className={`flex items-start gap-2 text-sm ${mutedTextClassName}`}>
            <span className="material-symbols-outlined mt-0.5 text-[16px] text-[#d97757]">location_on</span>
            <span>{reportLocationTitle}</span>
          </div>
        {mapLatitude !== null && mapLongitude !== null ? (
          <div className={`flex items-start gap-2 text-xs ${mutedTextClassName}`}>
            <span className="material-symbols-outlined mt-0.5 text-[14px] text-[#d97757]">my_location</span>
            <span>{formatCoordinatePair(mapLatitude, mapLongitude)}</span>
          </div>
        ) : null}
          <div className={`flex items-start gap-2 text-sm ${mutedTextClassName}`}>
            <span className="material-symbols-outlined mt-0.5 text-[16px] text-[#d97757]">schedule</span>
            <span>Submitted {new Date(report.created_at).toLocaleString()}</span>
          </div>
        </div>

        <div
          className={`mt-5 grid gap-3 rounded-[22px] border px-4 py-3 sm:grid-cols-2 ${
            isDarkMode ? "border-[#3a342f] bg-[#1f1c19]" : "border-[#edd8cb] bg-[#fffaf5]"
          }`}
        >
          <div>
            <p className={sectionLabelClassName}>Incident ID</p>
            <p className={`mt-1 text-sm font-semibold ${strongTextClassName}`}>#{report.id.slice(0, 8)}</p>
          </div>
          <div>
            <p className={sectionLabelClassName}>Department State</p>
            <p className={`mt-1 text-sm font-semibold ${strongTextClassName}`}>
              {ownResponse ? formatLabel(ownResponse.state) : "Pending response"}
            </p>
          </div>
        </div>

          <div className="mt-5 space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <p className={sectionLabelClassName}>Category</p>
            <div
              className={`mt-2 inline-flex items-center gap-2 rounded-full border px-3 py-2 text-sm font-semibold ${chipClassName}`}
            >
              <span className="material-symbols-outlined text-[16px]">
                {categoryIcons[report.category] ?? "emergency"}
              </span>
              {formatLabel(report.category)}
            </div>
          </div>

          <div>
            <p className={sectionLabelClassName}>Severity</p>
            <div
              className={`mt-2 inline-flex items-center gap-2 rounded-full border px-3 py-2 text-sm font-semibold ${chipClassName}`}
            >
              <span className="material-symbols-outlined text-[16px]">priority_high</span>
              {formatLabel(report.severity)}
            </div>
          </div>
        </div>

        <div>
          <p className={sectionLabelClassName}>Original Description</p>
            <p className={`mt-2 text-sm leading-6 ${mutedTextClassName}`}>{report.description}</p>
          </div>

        {report.is_escalated ? (
          <div
            className={`rounded-[18px] border px-4 py-3 text-sm ${
              isDarkMode
                ? "border-[#5c463c] bg-[#2b241f] text-[#f3b08f]"
                : "border-[#f1c4b5] bg-[#fff4ee] text-[#a14b2f]"
            }`}
          >
            Escalated to wider response coordination.
          </div>
        ) : null}

        <div>
          <div className="flex items-center justify-between gap-3">
            <p className={sectionLabelClassName}>Evidence</p>
            <span className={`text-[11px] font-semibold uppercase tracking-[0.18em] ${mutedTextClassName}`}>
              {evidenceImageUrls.length} file{evidenceImageUrls.length === 1 ? "" : "s"}
            </span>
          </div>
          {evidenceImageUrls.length > 0 ? (
              <div className="mt-3 grid grid-cols-2 gap-3">
                {evidenceImageUrls.slice(0, 4).map((url, index) => (
                  <div key={index} className={evidenceTileClassName}>
                    <img
                      alt={`Evidence ${index + 1}`}
                      className="aspect-[1.1/1] w-full object-cover"
                      src={url}
                    />
                  </div>
                ))}
              </div>
          ) : (
            <div className={`mt-3 rounded-[18px] border px-4 py-4 text-sm ${chipClassName}`}>
              No evidence uploaded for this incident yet.
            </div>
          )}
        </div>
      </div>
      </Card>
    );

  const actionsCard = (
      <Card className={`${floatingPanelClassName} p-5 xl:p-5 2xl:p-6`}>
        <div className="space-y-6">
          <div>
            <p className={sectionLabelClassName}>Response Actions</p>
            <p className={`mt-2 text-sm leading-6 ${mutedTextClassName}`}>
            Coordinate how your department will handle this incident while keeping the response roster updated.
          </p>
        </div>

        {isOpen ? (
          <div className={`space-y-4 p-4 ${actionPanelSurfaceClassName}`}>
            <div>
              <label className={sectionLabelClassName}>Notes (Optional)</label>
              <textarea
                className={`mt-2 ${responseInputClassName}`}
                onChange={(event) => setNotes(event.target.value)}
                placeholder="Add coordination notes..."
                value={notes}
              />
            </div>

            {!hasResponded ? (
              <>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <Button
                    className="w-full justify-center"
                    disabled={actionLoading}
                    onClick={handleAccept}
                    variant="secondary"
                  >
                    <span className="material-symbols-outlined mr-1 text-[16px]">check_circle</span>
                    Accept
                  </Button>
                  <Button
                    className="w-full justify-center"
                    disabled={actionLoading}
                    onClick={() => setShowDeclineForm((current) => !current)}
                    variant="outline"
                  >
                    <span className="material-symbols-outlined mr-1 text-[16px]">cancel</span>
                    Decline
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
                    <div className="flex gap-3">
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
              </>
            ) : hasAccepted ? (
              <div className="space-y-3">
                <p className={`text-sm ${mutedTextClassName}`}>
                  Your department accepted this report. Move it forward as field work progresses.
                </p>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  {report.status === "accepted" ? (
                    <Button
                      className="w-full justify-center"
                      disabled={actionLoading}
                      onClick={() => handleStatusUpdate("responding")}
                      variant="secondary"
                    >
                      <span className="material-symbols-outlined mr-1 text-[16px]">directions_run</span>
                      Mark Responding
                    </Button>
                  ) : null}
                  {report.status === "responding" ? (
                    <Button
                      className="w-full justify-center"
                      disabled={actionLoading}
                      onClick={() => handleStatusUpdate("resolved")}
                      variant="secondary"
                    >
                      <span className="material-symbols-outlined mr-1 text-[16px]">task_alt</span>
                      Mark Resolved
                    </Button>
                  ) : null}
                </div>
              </div>
            ) : (
              <p className={`text-sm italic ${mutedTextClassName}`}>
                Your department already declined this report.
              </p>
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

  const timelineCard = (
    <Card className={`${floatingPanelClassName} p-5 xl:p-5 2xl:p-6`}>
      <p className={sectionLabelClassName}>Report Timeline</p>
      <div className="mt-4 space-y-5">
        {resolvedTimeline.length > 0 ? (
          resolvedTimeline.map((entry, index) => {
            if (entry.type === "status_change") {
              const historyStatus = entry.new_status ?? "pending";
              const historyStyle = statusStyles[historyStatus] ?? {
                bg: "bg-surface-container-highest",
                text: "text-on-surface-variant",
              };

              return (
                <div key={`status-${index}`} className="flex gap-3">
                  <div className="mt-1 h-3 w-3 rounded-full border-2 border-[#a14b2f] bg-[#ffefe6]" />
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className={`text-sm font-semibold ${strongTextClassName}`}>
                        {formatLabel(historyStatus)}
                      </span>
                      <span
                        className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest ${historyStyle.bg} ${historyStyle.text}`}
                      >
                        {historyStatus}
                      </span>
                    </div>
                    {entry.notes ? (
                      <p className={`mt-1 text-sm ${mutedTextClassName}`}>{entry.notes}</p>
                    ) : null}
                    <p className={`mt-1 text-[10px] uppercase tracking-[0.2em] ${mutedTextClassName}`}>
                      {new Date(entry.timestamp).toLocaleString()}
                    </p>
                  </div>
                </div>
              );
            }

            const actionColor =
              entry.action === "accepted"
                ? "bg-green-100 text-green-800"
                : entry.action === "declined"
                  ? "bg-red-100 text-red-800"
                  : "bg-surface-container-highest text-on-surface-variant";

            return (
              <div key={`response-${index}`} className="flex gap-3">
                <div className="mt-1 h-3 w-3 rounded-full border-2 border-[#d97757] bg-[#fff1e8]" />
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className={`text-sm font-semibold ${strongTextClassName}`}>
                      {entry.department_name}
                    </span>
                    <span
                      className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest ${actionColor}`}
                    >
                      {formatLabel(entry.action)}
                    </span>
                  </div>
                  {entry.notes ? (
                    <p className={`mt-1 text-sm ${mutedTextClassName}`}>{entry.notes}</p>
                  ) : null}
                  {entry.decline_reason ? (
                    <p className="mt-1 text-sm text-red-700">{entry.decline_reason}</p>
                  ) : null}
                  <p className={`mt-1 text-[10px] uppercase tracking-[0.2em] ${mutedTextClassName}`}>
                    {new Date(entry.timestamp).toLocaleString()}
                  </p>
                </div>
              </div>
            );
          })
        ) : (
          <div className={`rounded-[18px] border px-4 py-4 text-sm ${chipClassName}`}>
            No timeline entries have been recorded yet.
          </div>
        )}
      </div>
    </Card>
  );

  return (
    <AppShell
      hidePageHeading
      subtitle="Incident response"
      title={`Report #${report.id.slice(0, 8)}`}
    >
      <div className={pageClassName}>
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#d97757]">
              Incident Response
            </p>
            <h1 className={`mt-2 font-headline text-4xl md:text-5xl ${titleTextClassName}`}>
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

        {errorMessage ? (
          <div className="rounded-md border border-error/20 bg-error-container/20 px-4 py-3 text-sm text-error">
            {errorMessage}
          </div>
        ) : null}

          <div className={laneEffectClassName}>
            <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_320px] 2xl:grid-cols-[minmax(0,1fr)_352px]">
              {mapLatitude !== null && mapLongitude !== null ? (
                <div className={`${mapShellClassName} ${mapMinHeightClassName} min-w-0`}>
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
                </div>
              ) : (
                <Card
                  className={`${panelClassName} ${mapMinHeightClassName} flex min-w-0 flex-col items-center justify-center p-8 text-center`}
                >
                  <span className="material-symbols-outlined mb-3 text-4xl text-[#d97757]">map</span>
                  <p className={`text-sm ${mutedTextClassName}`}>
                    GPS coordinates are unavailable for this report.
                  </p>
                </Card>
              )}

              <div className="space-y-5 xl:max-h-[calc(100vh-12rem)] xl:overflow-y-auto xl:pr-1">
                {overviewCard}
                {actionsCard}
                {timelineCard}
              </div>
            </div>
          </div>
        </div>
      </AppShell>
    );
  }

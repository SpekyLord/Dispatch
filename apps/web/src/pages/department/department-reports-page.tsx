// Department incident board - lists routed reports with status filters and incident map previews.

import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";

import { useAppShellTheme } from "@/components/layout/app-shell-theme";
import { AppShell } from "@/components/layout/app-shell";
import { LocationMap } from "@/components/maps/location-map";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type DeptReport = {
  id: string;
  title: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  created_at: string;
  is_escalated: boolean;
  visible_via: "primary" | "escalation";
  current_response?: { action: string } | null;
  response_summary: { accepted: number; declined: number; pending: number };
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

const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]" },
  accepted: { bg: "bg-tertiary-container", text: "text-[#3a4e6a]" },
  responding: { bg: "bg-[#e5e2de]", text: "text-[#52524f]" },
  resolved: { bg: "bg-[#d4edda]", text: "text-[#155724]" },
};

const severityColors: Record<string, string> = {
  low: "text-green-700 bg-green-100",
  medium: "text-yellow-800 bg-yellow-100",
  high: "text-orange-800 bg-orange-100",
  critical: "text-red-800 bg-red-100",
};

const incidentStatusFilterOptions = [
  { value: "", label: "All" },
  { value: "pending", label: "Pending" },
  { value: "accepted", label: "Accepted" },
  { value: "responding", label: "Responding" },
  { value: "resolved", label: "Resolved" },
] as const;

const incidentCategoryFilterOptions = [
  { value: "", label: "All" },
  { value: "fire", label: "Fire" },
  { value: "flood", label: "Flood" },
  { value: "earthquake", label: "Earthquake" },
  { value: "road_accident", label: "Road Accident" },
  { value: "medical", label: "Medical" },
  { value: "structural", label: "Structural" },
  { value: "other", label: "Other" },
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

function summarizeText(content?: string | null, maxLength = 112) {
  const collapsed = content?.replace(/\s+/g, " ").trim() ?? "";
  if (collapsed.length <= maxLength) {
    return collapsed;
  }

  return `${collapsed.slice(0, maxLength).trimEnd()}...`;
}

function normalizeComparableText(value?: string | null) {
  return (value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function getReportCopy(report: DeptReport) {
  const rawTitle = report.title?.trim() ?? "";
  const rawDescription = report.description?.trim() ?? "";
  const fallbackHeadline = labelize(report.category) || "Field report";

  if (!rawTitle && !rawDescription) {
    return { headline: fallbackHeadline, summary: null as string | null };
  }

  if (!rawTitle) {
    return { headline: rawDescription || fallbackHeadline, summary: null as string | null };
  }

  if (!rawDescription) {
    return { headline: rawTitle, summary: null as string | null };
  }

  const normalizedTitle = normalizeComparableText(rawTitle);
  const normalizedDescription = normalizeComparableText(rawDescription);
  const looksDuplicated =
    normalizedTitle === normalizedDescription ||
    (normalizedTitle.length > 12 && normalizedDescription.startsWith(normalizedTitle)) ||
    (normalizedDescription.length > 12 && normalizedTitle.startsWith(normalizedDescription));

  if (looksDuplicated) {
    return { headline: rawTitle, summary: null as string | null };
  }

  return {
    headline: rawTitle,
    summary: summarizeText(rawDescription, 86),
  };
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

function formatTimestamp(value: string) {
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

function resolveReportCoordinates(report: DeptReport) {
  if (typeof report.latitude === "number" && typeof report.longitude === "number") {
    return { lat: report.latitude, lng: report.longitude };
  }

  return parseCoordinateLocation(report.address);
}

function getReportCoordinateSource(report: DeptReport) {
  if (typeof report.latitude === "number" && typeof report.longitude === "number") {
    return `${report.latitude}, ${report.longitude}`;
  }

  if (report.address && parseCoordinateLocation(report.address)) {
    return report.address.trim();
  }

  return null;
}

function getReportLocationLabel(report: DeptReport, resolvedLocations: Record<string, string>) {
  const directAddress =
    report.address && !parseCoordinateLocation(report.address) ? report.address.trim() : null;

  if (directAddress) {
    return directAddress;
  }

  const coordinateSource = getReportCoordinateSource(report);
  if (coordinateSource) {
    return resolvedLocations[coordinateSource] ?? formatCoordinateFallback(coordinateSource);
  }

  return "Field location pending";
}

function IncidentMapPulse({ isDarkMode }: { isDarkMode: boolean }) {
  const circleBorderColor = isDarkMode ? "rgba(255, 200, 170, 0.72)" : "rgba(255, 166, 120, 0.78)";
  const circleGlowColor = isDarkMode ? "rgba(255, 182, 145, 0.75)" : "rgba(235, 134, 84, 0.62)";

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute left-1/2 top-1/2 z-[1] h-20 w-20 -translate-x-1/2 -translate-y-[62%] md:h-28 md:w-28"
    >
      <style>
        {`
          @keyframes dispatch-incident-board-pulse {
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
              width: 84px;
              height: 84px;
              transform: translate(-50%, -50%) scale(1);
            }
          }
        `}
      </style>

      {[0.15, 0.45, 0.8, 1.15].map((delay, index) => (
        <span
          key={index}
          className="absolute left-1/2 top-1/2 rounded-full"
          style={{
            width: 0,
            height: 0,
            opacity: 0,
            border: `1px solid ${circleBorderColor}`,
            boxShadow: `0 0 10px ${circleGlowColor}`,
            animation: "dispatch-incident-board-pulse 4s infinite linear",
            animationDelay: `${delay}s`,
          }}
        />
      ))}

      <span
        className="absolute left-1/2 top-1/2 h-6 w-6 -translate-x-1/2 -translate-y-1/2 rounded-full"
        style={{
          background: "transparent",
          boxShadow: isDarkMode
            ? "0 0 36px rgba(228, 116, 63, 0.42)"
            : "0 0 32px rgba(219, 108, 58, 0.34)",
        }}
      />
    </div>
  );
}

function IncidentBoardMapPreview({
  report,
  isDarkMode,
  mobile = false,
}: {
  report: DeptReport;
  isDarkMode: boolean;
  mobile?: boolean;
}) {
  const coordinates = resolveReportCoordinates(report);
  const shellClassName = mobile
    ? "relative h-[120px] overflow-hidden rounded-[20px] border border-[#ead8cb]"
    : "absolute inset-y-0 right-0 hidden overflow-hidden md:block md:w-[42%] md:z-[1]";
  const overlayTabBorderClassName = isDarkMode ? "border-white/10" : "border-[#ead9cc]/95";
  const overlayTabLabelClassName = isDarkMode ? "text-white/36" : "text-[#b38f79]";
  const overlayTabStyle = {
    background: isDarkMode
      ? "linear-gradient(90deg, rgba(24, 24, 23, 0.99) 0%, rgba(24, 24, 23, 0.96) 56%, rgba(24, 24, 23, 0.72) 78%, rgba(24, 24, 23, 0.22) 92%, rgba(24, 24, 23, 0) 100%)"
      : "linear-gradient(90deg, rgba(255, 248, 243, 0.998) 0%, rgba(255, 248, 243, 0.99) 58%, rgba(255, 248, 243, 0.82) 80%, rgba(255, 248, 243, 0.30) 93%, rgba(255, 248, 243, 0) 100%)",
  };

  return (
    <div className={shellClassName} data-testid={`report-map-preview-${report.id}`}>
      {coordinates ? (
        <>
          <div className="absolute inset-y-0 left-[9%] z-0 w-[138%] [&_.leaflet-control-container]:hidden [&_.leaflet-marker-icon]:drop-shadow-[0_8px_18px_rgba(0,0,0,0.18)]">
            <LocationMap
              latitude={coordinates.lat}
              longitude={coordinates.lng}
              mapClassName="h-full w-full"
              wrapperClassName="h-full w-full rounded-none border-0"
            />
          </div>
          {!mobile && (
            <div
              aria-hidden="true"
              className={`pointer-events-none absolute inset-y-0 left-0 z-[2] hidden overflow-hidden rounded-r-[26px] border-r shadow-[0_18px_34px_-24px_rgba(96,61,42,0.22)] backdrop-blur-[2px] md:block md:w-[58%] ${overlayTabBorderClassName}`}
              data-testid={`report-map-overlay-tab-${report.id}`}
              style={overlayTabStyle}
            >
              <div className="absolute inset-y-0 left-0 w-[48%] bg-[linear-gradient(180deg,rgba(255,248,243,0.34),rgba(255,248,243,0.10))]" />
              <div className="absolute inset-y-4 left-4 w-px bg-white/28" />
              <div className="relative flex h-full items-center px-5">
                <span className={`text-[8px] font-bold uppercase tracking-[0.32em] ${overlayTabLabelClassName}`}>
                  Map Feed
                </span>
              </div>
            </div>
          )}
          <IncidentMapPulse isDarkMode={isDarkMode} />
          <div className="pointer-events-none absolute bottom-3 right-3 z-[1]">
            <span className="rounded-full border border-white/70 bg-white/78 px-2.5 py-1 text-[9px] font-bold uppercase tracking-[0.18em] text-[#a65433] shadow-sm backdrop-blur">
              Incident Pin
            </span>
          </div>
        </>
      ) : (
        <div className="flex h-full items-center justify-center bg-[linear-gradient(135deg,#f7ede5,#e8d7c9)]">
          <div className="text-center">
            <span className="material-symbols-outlined text-[32px] text-[#b05a36]">map</span>
            <p className="mt-2 text-[10px] font-bold uppercase tracking-[0.22em] text-[#8a5a43]">
              Location feed pending
            </p>
          </div>
        </div>
      )}
    </div>
  );
}

function IncidentBoardCard({
  report,
  isDarkMode,
  resolvedLocations,
}: {
  report: DeptReport;
  isDarkMode: boolean;
  resolvedLocations: Record<string, string>;
}) {
  const statusStyle =
    statusStyles[report.status] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
  const severityStyle = severityColors[report.severity] ?? "text-on-surface-variant bg-surface-container";
  const ownAction = report.current_response?.action;
  const locationLabel = getReportLocationLabel(report, resolvedLocations);
  const categoryIcon = categoryIcons[report.category] ?? "emergency";
  const reportCopy = getReportCopy(report);

  return (
    <Link className="block" to={`/department/reports/${report.id}`}>
      <Card className="cursor-pointer overflow-hidden border-[#ead9cc] bg-[#fff8f3] p-0 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-glass">
        <article className="relative flex min-h-[196px] flex-col overflow-hidden md:min-h-[154px]">
          <IncidentBoardMapPreview isDarkMode={isDarkMode} report={report} />

          <div className="relative z-[3] flex h-full flex-col gap-3 px-4 py-3.5 md:max-w-[68%] md:px-5">
            <div className="space-y-3.5">
              <div className="flex flex-wrap items-center gap-2 text-[9px] font-bold uppercase tracking-[0.2em] text-[#a56a50]">
                <span className={`rounded-full px-2 py-1 ${severityStyle}`}>
                  {labelize(report.severity) || "High"}
                </span>
                <span className="rounded-full border border-[#ead7c7] bg-white/75 px-2 py-1 text-[#9f6a4e] md:hidden">
                  {formatTimestamp(report.created_at)}
                </span>
                {report.visible_via === "escalation" && (
                  <span className="rounded-full border border-[#e9cdb9] bg-[#fff3e6] px-2 py-1 text-[#b1683d]">
                    Escalation feed
                  </span>
                )}
              </div>

              <div className="flex items-start gap-3">
                <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl bg-[#f2e2d7] text-[#b25e39] shadow-[0_10px_22px_-18px_rgba(166,92,58,0.55)]">
                  <span className="material-symbols-outlined text-[16px]">{categoryIcon}</span>
                </div>

                <div className="min-w-0 flex-1">
                  <p className="text-[8px] font-bold uppercase tracking-[0.18em] text-[#b58167]">
                    Live operational feed
                  </p>
                  <div className="mt-1 flex flex-wrap items-baseline gap-x-2 gap-y-1">
                    <h3 className="font-headline text-[1.12rem] leading-none text-[#4d2b1e] md:text-[1.22rem]">
                      Report #{report.id.slice(0, 8)}
                    </h3>
                    <p className="text-[12px] font-semibold leading-4 text-[#7b4c36]">
                      {reportCopy.headline}
                    </p>
                  </div>
                  {reportCopy.summary && (
                    <p className="mt-1 max-w-[28rem] text-[11.5px] leading-4 text-[#705d52]">
                      {reportCopy.summary}
                    </p>
                  )}
                </div>
              </div>

              <div className="flex flex-wrap items-start gap-x-5 gap-y-3 border-t border-[#f0dfd3] pt-3">
                <div className="min-w-0 max-w-[22rem]">
                  <p className="text-[8px] font-bold uppercase tracking-[0.16em] text-[#a8755d]">
                    Primary Location
                  </p>
                  <div className="mt-1 inline-flex max-w-full items-start gap-2 text-[13px] font-semibold leading-4 text-[#4d2b1e]">
                    <span className="material-symbols-outlined mt-0.5 text-[14px] text-[#d97757]">
                      location_on
                    </span>
                    <span className="line-clamp-2">{locationLabel}</span>
                  </div>
                </div>

                <div className="flex flex-wrap items-center gap-1.5 text-[11px]">
                  <span className="rounded-full bg-[#f1e4da] px-2.5 py-1 font-semibold capitalize text-[#85563f]">
                    {labelize(report.category)}
                  </span>
                  <span className={`rounded-full px-2.5 py-1 font-semibold capitalize ${statusStyle.bg} ${statusStyle.text}`}>
                    {labelize(report.status)}
                  </span>
                  {report.is_escalated && (
                    <span className="rounded-full bg-red-100 px-2.5 py-1 text-[9px] font-bold uppercase tracking-[0.14em] text-red-800">
                      Escalated
                    </span>
                  )}
                  {ownAction && (
                    <span className={`rounded-full px-2.5 py-1 text-[9px] font-bold uppercase tracking-[0.14em] ${
                      ownAction === "accepted" ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"
                    }`}>
                      You {ownAction}
                    </span>
                  )}
                </div>
              </div>
            </div>

            <div className="mt-auto flex flex-wrap items-center gap-2 border-t border-[#ebdbcf] pt-2 text-[8px] font-bold uppercase tracking-[0.14em] text-[#b08a73]">
              <span>{report.response_summary.accepted} accepted</span>
              <span>{report.response_summary.declined} declined</span>
              <span>{report.response_summary.pending} pending</span>
              <span className="ml-auto inline-flex items-center gap-1 text-[#b35e38]">
                View incident details
                <span className="material-symbols-outlined text-[14px]">arrow_forward</span>
              </span>
            </div>
          </div>

          <div className="relative z-10 px-5 pb-5 md:hidden">
            <IncidentBoardMapPreview isDarkMode={isDarkMode} mobile report={report} />
          </div>
        </article>
      </Card>
    </Link>
  );
}

function IncidentTimelineBlock({ report }: { report: DeptReport }) {
  const timelineTimestamp = formatTimelineTimestamp(report.created_at);

  return (
    <div className="pointer-events-none relative flex min-h-[154px] items-stretch">
      <div className="relative flex w-full justify-start py-4">
        <div className="absolute bottom-4 left-[1.1rem] top-4 w-px bg-[linear-gradient(180deg,rgba(214,160,132,0.08),rgba(214,160,132,0.55)_18%,rgba(214,160,132,0.55)_82%,rgba(214,160,132,0.08))]" />
        <span className="absolute left-[0.83rem] top-6 h-2.5 w-2.5 rounded-full border border-[#dba788] bg-[#fff8f3] shadow-[0_0_0_3px_rgba(255,248,243,0.88)]" />
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

export function DepartmentReportsPage() {
  const accessToken = useSessionStore((state) => state.accessToken);
  const { isDarkMode } = useAppShellTheme();
  const [reports, setReports] = useState<DeptReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [resolvedLocations, setResolvedLocations] = useState<Record<string, string>>({});
  const resolvingLocationsRef = useRef(new Set<string>());
  const [isDesktopLayout, setIsDesktopLayout] = useState(() => {
    if (typeof window === "undefined") {
      return true;
    }

    if (typeof window.matchMedia === "function") {
      return window.matchMedia("(min-width: 768px)").matches;
    }

    return window.innerWidth >= 768;
  });

  function fetchReports(showLoader = true) {
    if (showLoader) {
      setLoading(true);
    }
    const params = new URLSearchParams();
    if (statusFilter) params.set("status", statusFilter);
    if (categoryFilter) params.set("category", categoryFilter);
    const qs = params.toString();
    return apiRequest<{ reports: DeptReport[] }>(`/api/departments/reports${qs ? `?${qs}` : ""}`)
      .then((res) => setReports(res.reports))
      .catch(() => {})
      .finally(() => {
        if (showLoader) {
          setLoading(false);
        }
      });
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void fetchReports(); }, [statusFilter, categoryFilter]);

  useEffect(() => {
    const reportSubscription = subscribeToTable(
      "incident_reports",
      () => {
        void fetchReports(false);
      },
      { accessToken },
    );
    const responseSubscription = subscribeToTable(
      "department_responses",
      () => {
        void fetchReports(false);
      },
      { accessToken },
    );

    return () => {
      reportSubscription.unsubscribe();
      responseSubscription.unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accessToken, statusFilter, categoryFilter]);

  useEffect(() => {
    const coordinateSources = new Set<string>();

    reports.forEach((report) => {
      const coordinateSource = getReportCoordinateSource(report);
      if (coordinateSource) {
        coordinateSources.add(coordinateSource);
      }
    });

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
  }, [reports, resolvedLocations]);

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

  const normalizedSearchQuery = searchQuery.trim().toLowerCase();
  const visibleReports = reports.filter((report) => {
    if (!normalizedSearchQuery) {
      return true;
    }

    const searchableParts = [
      report.id,
      report.title,
      report.description,
      getReportLocationLabel(report, resolvedLocations),
      labelize(report.category),
      labelize(report.status),
      labelize(report.severity),
    ];

    return searchableParts.some((value) => value?.toLowerCase().includes(normalizedSearchQuery));
  });

  const filterTabBaseClassName =
    "rounded-full border px-4 py-1.5 text-[12px] font-semibold transition-colors";
  const inactiveFilterTabClassName =
    "border-[#e3d3c6] bg-[#fff8f3] text-[#6f625b] hover:bg-[#f4ebe3] hover:text-[#584137]";
  const activeFilterTabClassName =
    "border-[#8f5137] bg-[#8f5137] text-white shadow-[0_10px_22px_-16px_rgba(143,81,55,0.7)]";

  return (
    <AppShell subtitle="Incident response" title="Incident Board">
      <div className="mb-8 flex flex-col gap-4">
        <div className="flex flex-col gap-3 xl:flex-row xl:items-start xl:justify-between">
          <div className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              {incidentStatusFilterOptions.map((option) => (
                <button
                  className={`${filterTabBaseClassName} ${
                    statusFilter === option.value ? activeFilterTabClassName : inactiveFilterTabClassName
                  }`}
                  key={option.value || "all-statuses"}
                  onClick={() => setStatusFilter(option.value)}
                  type="button"
                >
                  {option.label}
                </button>
              ))}
            </div>

            <div className="flex flex-col gap-3 lg:flex-row lg:items-center">
              <div className="flex flex-wrap items-center gap-2">
                {incidentCategoryFilterOptions.map((option) => (
                  <button
                    className={`${filterTabBaseClassName} ${
                      categoryFilter === option.value ? activeFilterTabClassName : inactiveFilterTabClassName
                    }`}
                    key={option.value || "all-categories"}
                    onClick={() => setCategoryFilter(option.value)}
                    type="button"
                  >
                    {option.label}
                  </button>
                ))}
              </div>

              <label className="relative block min-w-0 lg:w-[240px] xl:w-[280px]">
                <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[#a08373]">
                  <span className="material-symbols-outlined text-[16px]">search</span>
                </span>
                <input
                  className="h-10 w-full rounded-[12px] border border-[#e3d3c6] bg-[#fff8f3] pl-10 pr-4 text-sm text-[#4d2b1e] outline-none transition-colors placeholder:text-[#a08373] focus:border-[#c98d71]"
                  onChange={(event) => setSearchQuery(event.target.value)}
                  placeholder="Search reports"
                  type="search"
                  value={searchQuery}
                />
              </label>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3 xl:justify-end">
            <Button
              className="rounded-full border border-[#e3d3c6] bg-[#fff8f3] px-4 text-[#7a6558] hover:bg-[#f3e8de]"
              onClick={() => { void fetchReports(); }}
              variant="ghost"
            >
              <span className="material-symbols-outlined mr-1 text-[16px]">refresh</span>
              Refresh
            </Button>
            <span className="text-xs font-semibold text-[#8a776b]">
              Showing {visibleReports.length} report{visibleReports.length !== 1 ? "s" : ""}
            </span>
          </div>
        </div>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading reports...
        </Card>
      ) : reports.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined mb-4 block text-5xl text-outline-variant">inbox</span>
          <p className="text-on-surface-variant">No reports match the current filters.</p>
        </Card>
      ) : visibleReports.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined mb-4 block text-5xl text-outline-variant">search_off</span>
          <p className="text-on-surface-variant">No reports match the current filters or search.</p>
        </Card>
      ) : !isDesktopLayout ? (
        <div className="space-y-6">
          {visibleReports.map((report) => (
            <IncidentBoardCard
              isDarkMode={isDarkMode}
              key={report.id}
              report={report}
              resolvedLocations={resolvedLocations}
            />
          ))}
        </div>
      ) : (
        <div className="grid md:grid-cols-[minmax(0,1fr)_6.5rem] md:gap-5 md:mr-2 xl:mr-4">
          <section className="overflow-x-clip rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]">
            <div className="space-y-6">
              {visibleReports.map((report) => (
                <IncidentBoardCard
                  isDarkMode={isDarkMode}
                  key={report.id}
                  report={report}
                  resolvedLocations={resolvedLocations}
                />
              ))}
            </div>
          </section>

          <aside className="overflow-x-clip rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]">
            <div className="space-y-6">
              {visibleReports.map((report) => (
                <IncidentTimelineBlock key={report.id} report={report} />
              ))}
            </div>
          </aside>
        </div>
      )}
    </AppShell>
  );
}

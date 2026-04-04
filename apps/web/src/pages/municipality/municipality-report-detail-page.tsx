// Municipality report detail — read-only view of any incident report with timeline and map.

import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";

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
  title?: string;
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

const severityColors: Record<string, string> = {
  low: "text-green-700 bg-green-100",
  medium: "text-yellow-800 bg-yellow-100",
  high: "text-orange-800 bg-orange-100",
  critical: "text-red-800 bg-red-100",
};

function parseImageUrls(raw?: string[] | string | null): string[] {
  if (!raw) return [];
  if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (trimmed.startsWith("[")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) return parsed.filter((u): u is string => typeof u === "string" && u.trim() !== "");
      } catch { /* fall through */ }
    }
    return trimmed.split(/[\r\n,]+/).map((s) => s.trim()).filter(Boolean);
  }
  return raw.flatMap((entry) => {
    if (typeof entry !== "string") return [];
    const t = entry.trim();
    if (t.startsWith("[")) {
      try { const p = JSON.parse(t); if (Array.isArray(p)) return p.filter((u): u is string => typeof u === "string"); } catch { /* fall through */ }
    }
    return t ? [t] : [];
  });
}

export function MunicipalityReportDetailPage() {
  const { reportId } = useParams<{ reportId: string }>();
  const accessToken = useSessionStore((s) => s.accessToken);
  const { t, getCategoryLabel, getSeverityLabel, getStatusLabel, getResponseActionLabel } = useLocale();

  const [report, setReport] = useState<Report | null>(null);
  const [history, setHistory] = useState<StatusHistory[]>([]);
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  const [deptResponses, setDeptResponses] = useState<DeptResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [resolvedLocation, setResolvedLocation] = useState<string | null>(null);
  const resolvingRef = useRef(false);

  const fetchReport = useCallback(
    (showLoader = true) => {
      if (!reportId) return Promise.resolve();
      if (showLoader) setLoading(true);

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
          setDeptResponses(res.department_responses ?? []);
          setError(null);
        })
        .catch((err) => setError(err instanceof Error ? err.message : "Failed to load report."))
        .finally(() => { if (showLoader) setLoading(false); });
    },
    [reportId],
  );

  useEffect(() => { void fetchReport(); }, [fetchReport]);

  useEffect(() => {
    if (!reportId) return;
    const sub1 = subscribeToTable("incident_reports", () => void fetchReport(false), { accessToken, filter: `id=eq.${reportId}` });
    const sub2 = subscribeToTable("report_status_history", () => void fetchReport(false), { accessToken, filter: `report_id=eq.${reportId}` });
    return () => { sub1.unsubscribe(); sub2.unsubscribe(); };
  }, [accessToken, fetchReport, reportId]);

  // Reverse geocode
  useEffect(() => {
    if (!report || resolvingRef.current) return;
    const lat = report.latitude;
    const lng = report.longitude;
    if (lat == null || lng == null) return;
    resolvingRef.current = true;
    fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&zoom=16&addressdetails=1`)
      .then(async (r) => {
        if (!r.ok) throw new Error();
        const data = await r.json();
        setResolvedLocation(data.display_name ?? `${lat.toFixed(4)}, ${lng.toFixed(4)}`);
      })
      .catch(() => setResolvedLocation(`${lat.toFixed(4)}, ${lng.toFixed(4)}`));
  }, [report]);

  if (loading) {
    return (
      <AppShell subtitle="Report detail" title="Loading...">
        <Card className="py-16 text-center text-on-surface-variant"><LoadingDots sizeClassName="h-5 w-5" /></Card>
      </AppShell>
    );
  }

  if (error || !report) {
    return (
      <AppShell subtitle="Report detail" title="Error">
        <Card className="py-16 text-center text-error">{error ?? "Report not found."}</Card>
      </AppShell>
    );
  }

  const style = statusStyles[report.status] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
  const sevStyle = severityColors[report.severity] ?? "text-on-surface-variant bg-surface-container";
  const resolvedTimeline = timeline.length > 0
    ? timeline
    : history.map((e) => ({ type: "status_change" as const, timestamp: e.created_at, new_status: e.new_status ?? e.status, notes: e.notes ?? e.note }));
  const images = parseImageUrls(report.image_urls);
  const locationLabel = report.address ?? resolvedLocation ?? (report.latitude != null ? `${report.latitude.toFixed(4)}, ${report.longitude?.toFixed(4)}` : null);

  return (
    <AppShell hidePageHeading subtitle="Report detail" title={`Report #${report.id.slice(0, 8)}`}>
      <div className="space-y-8">
        {/* Header */}
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#d97757]">Municipality Review</p>
            <h1 className="mt-2 font-headline text-4xl text-on-surface">
              Report #{report.id.slice(0, 8)}
            </h1>
          </div>
          <Link to="/municipality/reports" className="inline-flex items-center gap-1 text-sm text-on-surface-variant hover:text-on-surface transition-colors">
            <span className="material-symbols-outlined text-[16px]">arrow_back</span>
            Back to Reports
          </Link>
        </div>

        {/* Map */}
        {report.latitude != null && report.longitude != null && (
          <div className="overflow-hidden rounded-2xl border border-outline-variant/20 shadow-sm">
            <LocationMap latitude={report.latitude} longitude={report.longitude} mapClassName="h-80 w-full" wrapperClassName="h-80 w-full rounded-none border-0" />
          </div>
        )}

        {/* Main content grid */}
        <div className="grid gap-6 lg:grid-cols-3">
          {/* Left column — report info */}
          <div className="lg:col-span-2 space-y-6">
            <Card>
              <div className="flex items-start justify-between gap-4 mb-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                    <span className="material-symbols-outlined">{categoryIcons[report.category] ?? "emergency"}</span>
                  </div>
                  <div>
                    <h2 className="text-lg font-semibold text-on-surface">{report.title || report.description.slice(0, 60)}</h2>
                    <p className="text-xs text-on-surface-variant">{new Date(report.created_at).toLocaleString()}</p>
                  </div>
                </div>
                <span className={`rounded-full px-3 py-1.5 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                  {getStatusLabel(report.status)}
                </span>
              </div>

              <p className="text-sm leading-7 text-on-surface-variant mb-4">{report.description}</p>

              <div className="flex flex-wrap gap-2">
                <span className="rounded-md bg-surface-container-highest px-2.5 py-1 text-xs font-medium capitalize text-on-surface-variant">
                  {getCategoryLabel(report.category)}
                </span>
                <span className={`rounded-md px-2.5 py-1 text-xs font-medium capitalize ${sevStyle}`}>
                  {getSeverityLabel(report.severity)}
                </span>
                {report.is_escalated && (
                  <span className="rounded-md bg-red-100 px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest text-red-800">
                    {t("reports.escalatedBadge")}
                  </span>
                )}
                {report.is_mesh_origin && (
                  <span className="rounded-md bg-cyan-100 px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest text-cyan-800">
                    {t("reports.meshBadge")}
                  </span>
                )}
              </div>

              {locationLabel && (
                <div className="mt-4 flex items-center gap-2 text-sm text-on-surface-variant">
                  <span className="material-symbols-outlined text-[16px] text-[#d97757]">location_on</span>
                  {locationLabel}
                </div>
              )}
            </Card>

            {/* Evidence images */}
            {images.length > 0 && (
              <Card>
                <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#d97757] mb-3">
                  Evidence ({images.length})
                </p>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                  {images.slice(0, 6).map((url, i) => (
                    <div key={i} className="overflow-hidden rounded-xl border border-outline-variant/20 bg-surface-container">
                      <img alt={`Evidence ${i + 1}`} className="aspect-[4/3] w-full object-cover" src={url} />
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {/* Department responses */}
            {deptResponses.length > 0 && (
              <Card>
                <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#d97757] mb-4">
                  Department Responses
                </p>
                <div className="space-y-3">
                  {deptResponses.map((resp, i) => {
                    const actionColor = resp.action === "accepted"
                      ? "bg-[#d4edda] text-[#155724]"
                      : resp.action === "declined"
                        ? "bg-red-100 text-red-800"
                        : "bg-surface-container-highest text-on-surface-variant";
                    return (
                      <div key={i} className="flex items-center justify-between gap-3 rounded-lg bg-surface-container p-3">
                        <div>
                          <p className="text-sm font-semibold text-on-surface">{resp.department_name}</p>
                          {resp.notes && <p className="text-xs text-on-surface-variant mt-0.5">{resp.notes}</p>}
                          {resp.decline_reason && <p className="text-xs text-error mt-0.5">{resp.decline_reason}</p>}
                        </div>
                        <span className={`rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${actionColor}`}>
                          {getResponseActionLabel(resp.action)}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </Card>
            )}
          </div>

          {/* Right column — timeline */}
          <div className="space-y-6">
            <Card>
              <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#d97757] mb-4">
                {t("detail.timeline")}
              </p>
              <div className="space-y-4">
                {resolvedTimeline.map((entry, i) => {
                  if (entry.type === "status_change") {
                    const s = entry.new_status ?? "pending";
                    const hStyle = statusStyles[s] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
                    return (
                      <div key={`s-${i}`} className="flex gap-3">
                        <div className="mt-1.5 h-2.5 w-2.5 rounded-full border-2 border-[#a14b2f] bg-[#ffefe6] shrink-0" />
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-semibold text-on-surface">{getStatusLabel(s)}</span>
                            <span className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest ${hStyle.bg} ${hStyle.text}`}>{s}</span>
                          </div>
                          {entry.notes && <p className="mt-1 text-xs text-on-surface-variant">{entry.notes}</p>}
                          <p className="mt-1 text-[10px] uppercase tracking-[0.2em] text-on-surface-variant">
                            {new Date(entry.timestamp).toLocaleString()}
                          </p>
                        </div>
                      </div>
                    );
                  }

                  const actionColor = entry.action === "accepted"
                    ? "bg-[#d4edda] text-[#155724]"
                    : entry.action === "declined"
                      ? "bg-red-100 text-red-800"
                      : "bg-surface-container-highest text-on-surface-variant";
                  return (
                    <div key={`r-${i}`} className="flex gap-3">
                      <div className="mt-1.5 h-2.5 w-2.5 rounded-full border-2 border-[#d97757] bg-[#fff1e8] shrink-0" />
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-semibold text-on-surface">{entry.department_name}</span>
                          <span className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest ${actionColor}`}>
                            {getResponseActionLabel(entry.action ?? "")}
                          </span>
                        </div>
                        {entry.notes && <p className="mt-1 text-xs text-on-surface-variant">{entry.notes}</p>}
                        <p className="mt-1 text-[10px] uppercase tracking-[0.2em] text-on-surface-variant">
                          {new Date(entry.timestamp).toLocaleString()}
                        </p>
                      </div>
                    </div>
                  );
                })}
                {resolvedTimeline.length === 0 && (
                  <p className="text-sm text-on-surface-variant">No timeline entries yet.</p>
                )}
              </div>
            </Card>
          </div>
        </div>
      </div>
    </AppShell>
  );
}

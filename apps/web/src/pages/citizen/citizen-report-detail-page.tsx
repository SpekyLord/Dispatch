import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { LocationMap } from "@/components/maps/location-map";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { useLocale } from "@/lib/i18n/locale-context";
import { subscribeToTable } from "@/lib/realtime/supabase";

// Citizen report detail — bento layout with timeline, images, map sidebar.

type StatusHistory = {
  id: string;
  status?: string;
  new_status?: string;
  note?: string;
  notes?: string;
  created_at: string;
};
// Phase 3 timeline entry combining status changes and department responses
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
  id: string; description: string; category: string; severity: string;
  status: string; address?: string; latitude?: number; longitude?: number;
  is_escalated: boolean; is_mesh_origin?: boolean; image_urls?: string[];
  created_at: string; updated_at: string;
};

const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]" },
  accepted: { bg: "bg-tertiary-container", text: "text-[#3a4e6a]" },
  responding: { bg: "bg-[#e5e2de]", text: "text-[#52524f]" },
  resolved: { bg: "bg-[#d4edda]", text: "text-[#155724]" },
};

const categoryIcons: Record<string, string> = {
  fire: "local_fire_department", flood: "water_drop", earthquake: "vibration",
  road_accident: "car_crash", medical: "medical_services", structural: "domain_disabled", other: "emergency",
};

export function CitizenReportDetailPage() {
  const { reportId } = useParams<{ reportId: string }>();
  const accessToken = useSessionStore((state) => state.accessToken);
  const {
    t,
    getCategoryLabel,
    getResponseActionLabel,
    getSeverityLabel,
    getStatusLabel,
  } = useLocale();
  const [report, setReport] = useState<Report | null>(null);
  const [history, setHistory] = useState<StatusHistory[]>([]);
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  const [deptResponses, setDeptResponses] = useState<DeptResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  function fetchReport(showLoader = true) {
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
        setDeptResponses(res.department_responses ?? []);
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
  }

  useEffect(() => {
    if (!reportId) {
      return;
    }
    void fetchReport();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reportId]);

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

    return () => {
      reportSubscription.unsubscribe();
      historySubscription.unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accessToken, reportId]);

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

  const style = statusStyles[report.status] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };

  return (
    <AppShell subtitle={t("detail.subtitle")} title={`Report #${report.id.slice(0, 8)}`}>
      {/* Back link */}
      <div className="mb-6">
        <Link to="/citizen" className="inline-flex items-center gap-1 text-sm text-on-surface-variant hover:text-on-surface transition-colors">
          <span className="material-symbols-outlined text-[16px]">arrow_back</span>
          {t("detail.backToReports")}
        </Link>
      </div>

      <div className="grid gap-6 lg:grid-cols-12">
        {/* Main content — left 8 cols */}
        <div className="lg:col-span-8 space-y-6">
          {/* Incident details card */}
          <Card>
            <div className="flex items-start justify-between gap-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                  <span className="material-symbols-outlined">{categoryIcons[report.category] ?? "emergency"}</span>
                </div>
                <div>
                  <h2 className="font-headline text-2xl text-on-surface">{t("detail.incidentDetails")}</h2>
                  <p className="text-[10px] uppercase tracking-widest text-on-surface-variant mt-0.5">
                    {t("detail.submitted", { date: new Date(report.created_at).toLocaleString() })}
                  </p>
                </div>
              </div>
              <span className={`rounded-md px-3 py-1.5 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                {getStatusLabel(report.status)}
              </span>
            </div>

            <p className="mt-6 text-on-surface leading-relaxed">{report.description}</p>

            <div className="mt-6 flex flex-wrap gap-2">
              <span className="rounded bg-surface-container-highest px-3 py-1 text-xs font-medium capitalize text-on-surface-variant">
                {getCategoryLabel(report.category)}
              </span>
              <span className="rounded bg-surface-container-highest px-3 py-1 text-xs capitalize text-on-surface-variant">
                {getSeverityLabel(report.severity)}
              </span>
              {report.is_mesh_origin && (
                <span className="rounded bg-cyan-100 px-3 py-1 text-xs font-semibold text-cyan-800">
                  <span className="material-symbols-outlined text-[12px] align-middle mr-1">cell_tower</span>
                  {t("detail.meshOrigin")}
                </span>
              )}
              {report.is_escalated && (
                <span className="rounded bg-error-container/30 px-3 py-1 text-xs font-semibold text-error">
                  <span className="material-symbols-outlined text-[12px] align-middle mr-1">warning</span>
                  {t("detail.escalated")}
                </span>
              )}
            </div>

            {report.address && (
              <div className="mt-4 flex items-center gap-2 text-sm text-on-surface-variant">
                <span className="material-symbols-outlined text-[16px]">location_on</span>
                {report.address}
              </div>
            )}
          </Card>

          {/* Images */}
          {report.image_urls && report.image_urls.length > 0 && (
            <Card>
              <h3 className="font-headline text-xl mb-4">{t("detail.attachedEvidence")}</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                {report.image_urls.map((url, i) => (
                  <img key={i} src={url} alt={t("detail.reportImageAlt", { index: i + 1 })}
                    className="rounded-lg border border-outline-variant/10 object-cover aspect-square" />
                ))}
              </div>
            </Card>
          )}

          {/* Unified timeline — status changes + department responses */}
          <Card>
            <h3 className="font-headline text-xl mb-6">{t("detail.timeline")}</h3>
            {timeline.length === 0 && history.length === 0 ? (
              <p className="text-sm text-on-surface-variant">{t("detail.noActivity")}</p>
            ) : (
              <div className="space-y-4">
                {(timeline.length > 0 ? timeline : history.map((h) => ({
                  type: "status_change" as const,
                  timestamp: h.created_at,
                  new_status: h.new_status ?? h.status,
                  notes: h.notes ?? h.note,
                }))).map((entry, idx) => {
                  // Status change entry
                  if (entry.type === "status_change") {
                    const historyStatus = entry.new_status ?? "pending";
                    const hs = statusStyles[historyStatus] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
                    return (
                      <div key={`sc-${idx}`} className="flex gap-4 border-l-[3px] border-outline-variant/20 pl-5 relative">
                        <div className="absolute -left-[7px] top-0 w-3 h-3 rounded-full bg-surface-container-highest border-2 border-outline-variant" />
                        <div>
                          <span className={`inline-block rounded-md px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-widest ${hs.bg} ${hs.text}`}>
                            {getStatusLabel(historyStatus)}
                          </span>
                          {entry.notes && <p className="mt-1 text-sm text-on-surface-variant">{entry.notes}</p>}
                          <p className="mt-0.5 text-[10px] uppercase tracking-wider text-outline">
                            {new Date(entry.timestamp).toLocaleString()}
                          </p>
                        </div>
                      </div>
                    );
                  }
                  // Department response entry
                  const actionColor = entry.action === "accepted"
                    ? "bg-[#d4edda] text-[#155724]"
                    : entry.action === "declined"
                      ? "bg-red-100 text-red-800"
                      : "bg-surface-container-highest text-on-surface-variant";
                  return (
                    <div key={`dr-${idx}`} className="flex gap-4 border-l-[3px] border-[#D97757]/30 pl-5 relative">
                      <div className="absolute -left-[7px] top-0 w-3 h-3 rounded-full bg-[#D97757]/20 border-2 border-[#D97757]" />
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-semibold text-on-surface">{entry.department_name}</span>
                          <span className={`inline-block rounded-md px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest ${actionColor}`}>
                            {getResponseActionLabel(entry.action ?? "")}
                          </span>
                        </div>
                        {entry.notes && <p className="mt-1 text-sm text-on-surface-variant">{entry.notes}</p>}
                        {entry.decline_reason && (
                          <p className="mt-1 text-sm text-red-700 italic">{t("detail.reason", { reason: entry.decline_reason })}</p>
                        )}
                        <p className="mt-0.5 text-[10px] uppercase tracking-wider text-outline">
                          {new Date(entry.timestamp).toLocaleString()}
                        </p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </Card>

          {/* Department responses summary */}
          {deptResponses.length > 0 && (
            <Card>
              <h3 className="font-headline text-xl mb-4">{t("detail.departmentResponses")}</h3>
              <div className="space-y-3">
                {deptResponses.map((r, i) => (
                  <div key={i} className="flex items-center justify-between rounded-lg bg-surface-container p-3">
                    <span className="text-sm font-medium text-on-surface">{r.department_name}</span>
                    <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${
                      r.action === "accepted" ? "bg-[#d4edda] text-[#155724]" : "bg-red-100 text-red-800"
                    }`}>
                      {getResponseActionLabel(r.action)}
                    </span>
                  </div>
                ))}
              </div>
            </Card>
          )}
        </div>

        {/* Sidebar — right 4 cols */}
        <div className="lg:col-span-4 space-y-6">
          {/* Map */}
          {report.latitude && report.longitude ? (
            <div className="rounded-xl overflow-hidden border border-outline-variant/10 shadow-spotlight">
              <LocationMap latitude={report.latitude} longitude={report.longitude} />
            </div>
          ) : (
            <Card className="flex flex-col items-center justify-center h-64 text-on-surface-variant">
              <span className="material-symbols-outlined text-3xl mb-2">map</span>
              <p className="text-sm">{t("detail.noGps")}</p>
            </Card>
          )}

          {/* Quick stats */}
          <Card className="bg-surface-container">
            <h3 className="font-headline text-lg mb-4">{t("detail.summary")}</h3>
            <div className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-on-surface-variant">{t("detail.status")}</span>
                <span className="font-semibold capitalize text-on-surface">{getStatusLabel(report.status)}</span>
              </div>
              <div className="h-px bg-outline-variant/15" />
              <div className="flex justify-between">
                <span className="text-on-surface-variant">{t("detail.category")}</span>
                <span className="font-medium capitalize text-on-surface">{getCategoryLabel(report.category)}</span>
              </div>
              <div className="h-px bg-outline-variant/15" />
              <div className="flex justify-between">
                <span className="text-on-surface-variant">{t("detail.severity")}</span>
                <span className="font-medium capitalize text-on-surface">{getSeverityLabel(report.severity)}</span>
              </div>
              <div className="h-px bg-outline-variant/15" />
              <div className="flex justify-between">
                <span className="text-on-surface-variant">{t("detail.escalatedLabel")}</span>
                <span className="font-medium text-on-surface">{report.is_escalated ? t("detail.yes") : t("detail.no")}</span>
              </div>
            </div>
          </Card>
        </div>
      </div>
    </AppShell>
  );
}

import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { LocationMap } from "@/components/maps/location-map";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

/**
 * Phase 1 — Citizen report detail page.
 * Aegis-styled bento layout: incident info card, images gallery,
 * status history timeline, and location map sidebar.
 */

type StatusHistory = {
  id: string;
  status?: string;
  new_status?: string;
  note?: string;
  notes?: string;
  created_at: string;
};
type Report = {
  id: string; description: string; category: string; severity: string;
  status: string; address?: string; latitude?: number; longitude?: number;
  is_escalated: boolean; image_urls?: string[]; created_at: string; updated_at: string;
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
  const [report, setReport] = useState<Report | null>(null);
  const [history, setHistory] = useState<StatusHistory[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  function fetchReport(showLoader = true) {
    if (!reportId) {
      return Promise.resolve();
    }
    if (showLoader) {
      setLoading(true);
    }

    return apiRequest<{ report: Report; status_history: StatusHistory[] }>(`/api/reports/${reportId}`)
      .then((res) => {
        setReport(res.report);
        setHistory(res.status_history);
        setError(null);
      })
      .catch((err) => {
        setError(err instanceof Error ? err.message : "Failed to load report.");
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
      <AppShell subtitle="Report details" title="Loading...">
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl animate-pulse">hourglass_empty</span>
        </Card>
      </AppShell>
    );
  }

  if (error || !report) {
    return (
      <AppShell subtitle="Report details" title="Error">
        <Card className="py-16 text-center text-error">{error ?? "Report not found."}</Card>
      </AppShell>
    );
  }

  const style = statusStyles[report.status] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };

  return (
    <AppShell subtitle="Report details" title={`Report #${report.id.slice(0, 8)}`}>
      {/* Back link */}
      <div className="mb-6">
        <Link to="/citizen" className="inline-flex items-center gap-1 text-sm text-on-surface-variant hover:text-on-surface transition-colors">
          <span className="material-symbols-outlined text-[16px]">arrow_back</span>
          Back to reports
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
                  <h2 className="font-headline text-2xl text-on-surface">Incident Details</h2>
                  <p className="text-[10px] uppercase tracking-widest text-on-surface-variant mt-0.5">
                    Submitted {new Date(report.created_at).toLocaleString()}
                  </p>
                </div>
              </div>
              <span className={`rounded-md px-3 py-1.5 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                {report.status}
              </span>
            </div>

            <p className="mt-6 text-on-surface leading-relaxed">{report.description}</p>

            <div className="mt-6 flex flex-wrap gap-2">
              <span className="rounded bg-surface-container-highest px-3 py-1 text-xs font-medium capitalize text-on-surface-variant">
                {report.category.replace("_", " ")}
              </span>
              <span className="rounded bg-surface-container-highest px-3 py-1 text-xs capitalize text-on-surface-variant">
                {report.severity}
              </span>
              {report.is_escalated && (
                <span className="rounded bg-error-container/30 px-3 py-1 text-xs font-semibold text-error">
                  <span className="material-symbols-outlined text-[12px] align-middle mr-1">warning</span>
                  Escalated
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
              <h3 className="font-headline text-xl mb-4">Attached Evidence</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                {report.image_urls.map((url, i) => (
                  <img key={i} src={url} alt={`Report image ${i + 1}`}
                    className="rounded-lg border border-outline-variant/10 object-cover aspect-square" />
                ))}
              </div>
            </Card>
          )}

          {/* Status history timeline */}
          <Card>
            <h3 className="font-headline text-xl mb-6">Status History</h3>
            {history.length === 0 ? (
              <p className="text-sm text-on-surface-variant">No status updates yet.</p>
            ) : (
              <div className="space-y-4">
                {history.map((h) => {
                  const historyStatus = h.new_status ?? h.status ?? "pending";
                  const historyNote = h.notes ?? h.note;
                  const hs = statusStyles[historyStatus] ?? {
                    bg: "bg-surface-container-highest",
                    text: "text-on-surface-variant",
                  };
                  return (
                    <div key={h.id} className="flex gap-4 border-l-[3px] border-outline-variant/20 pl-5 relative">
                      <div className="absolute -left-[7px] top-0 w-3 h-3 rounded-full bg-surface-container-highest border-2 border-outline-variant" />
                      <div>
                        <span className={`inline-block rounded-md px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-widest ${hs.bg} ${hs.text}`}>
                          {historyStatus}
                        </span>
                        {historyNote && <p className="mt-1 text-sm text-on-surface-variant">{historyNote}</p>}
                        <p className="mt-0.5 text-[10px] uppercase tracking-wider text-outline">
                          {new Date(h.created_at).toLocaleString()}
                        </p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </Card>
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
              <p className="text-sm">No GPS coordinates available</p>
            </Card>
          )}

          {/* Quick stats */}
          <Card className="bg-surface-container">
            <h3 className="font-headline text-lg mb-4">Report Summary</h3>
            <div className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-on-surface-variant">Status</span>
                <span className="font-semibold capitalize text-on-surface">{report.status}</span>
              </div>
              <div className="h-px bg-outline-variant/15" />
              <div className="flex justify-between">
                <span className="text-on-surface-variant">Category</span>
                <span className="font-medium capitalize text-on-surface">{report.category.replace("_", " ")}</span>
              </div>
              <div className="h-px bg-outline-variant/15" />
              <div className="flex justify-between">
                <span className="text-on-surface-variant">Severity</span>
                <span className="font-medium capitalize text-on-surface">{report.severity}</span>
              </div>
              <div className="h-px bg-outline-variant/15" />
              <div className="flex justify-between">
                <span className="text-on-surface-variant">Escalated</span>
                <span className="font-medium text-on-surface">{report.is_escalated ? "Yes" : "No"}</span>
              </div>
            </div>
          </Card>
        </div>
      </div>
    </AppShell>
  );
}

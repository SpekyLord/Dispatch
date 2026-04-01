// Department incident board — lists routed reports with status filters and accept/decline actions.

import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { Button } from "@/components/ui/button";
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
  address?: string;
  created_at: string;
  is_escalated: boolean;
  visible_via: "primary" | "escalation";
  current_response?: { action: string } | null;
  response_summary: { accepted: number; declined: number; pending: number };
};

// Status badge colour map
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

export function DepartmentReportsPage() {
  const accessToken = useSessionStore((state) => state.accessToken);
  const [reports, setReports] = useState<DeptReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("");

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
  useEffect(() => { fetchReports(); }, [statusFilter, categoryFilter]);

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

  return (
    <AppShell subtitle="Incident response" title="Incident Board">
      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-8">
        <select
          className="aegis-input w-auto min-w-[140px]"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
        >
          <option value="">All statuses</option>
          <option value="pending">Pending</option>
          <option value="accepted">Accepted</option>
          <option value="responding">Responding</option>
          <option value="resolved">Resolved</option>
        </select>
        <select
          className="aegis-input w-auto min-w-[140px]"
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
        >
          <option value="">All categories</option>
          <option value="fire">Fire</option>
          <option value="flood">Flood</option>
          <option value="earthquake">Earthquake</option>
          <option value="road_accident">Road Accident</option>
          <option value="medical">Medical</option>
          <option value="structural">Structural</option>
          <option value="other">Other</option>
        </select>
        <Button variant="ghost" onClick={() => { void fetchReports(); }}>
          <span className="material-symbols-outlined text-[16px] mr-1">refresh</span>
          Refresh
        </Button>
        <span className="ml-auto text-xs text-on-surface-variant">
          {reports.length} report{reports.length !== 1 ? "s" : ""}
        </span>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading reports...
        </Card>
      ) : reports.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">inbox</span>
          <p className="text-on-surface-variant">No reports match the current filters.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {reports.map((r) => {
            const style = statusStyles[r.status] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
            const sevStyle = severityColors[r.severity] ?? "text-on-surface-variant bg-surface-container";
            const ownAction = r.current_response?.action;

            return (
              <Link key={r.id} to={`/department/reports/${r.id}`}>
                <Card className="hover:shadow-glass transition-all hover:-translate-y-0.5 cursor-pointer">
                  <div className="flex gap-4">
                    {/* Category icon */}
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                      <span className="material-symbols-outlined">{categoryIcons[r.category] ?? "emergency"}</span>
                    </div>

                    <div className="flex-grow min-w-0">
                      <div className="flex items-start justify-between gap-3">
                        <h3 className="text-sm font-semibold text-on-surface truncate">{r.title || r.description}</h3>
                        <div className="flex items-center gap-2 shrink-0">
                          {r.is_escalated && (
                            <span className="rounded-md bg-red-100 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-red-800">
                              Escalated
                            </span>
                          )}
                          <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                            {r.status}
                          </span>
                        </div>
                      </div>

                      {/* Meta row */}
                      <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
                        <span className="rounded bg-surface-container-highest px-2 py-0.5 font-medium capitalize text-on-surface-variant">
                          {r.category.replace("_", " ")}
                        </span>
                        <span className={`rounded px-2 py-0.5 font-medium capitalize ${sevStyle}`}>
                          {r.severity}
                        </span>
                        {r.visible_via === "escalation" && (
                          <span className="text-[10px] text-orange-700 font-semibold uppercase">via escalation</span>
                        )}
                        {ownAction && (
                          <span className={`rounded px-2 py-0.5 text-[10px] font-bold uppercase ${
                            ownAction === "accepted" ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"
                          }`}>
                            You {ownAction}
                          </span>
                        )}
                      </div>

                      {/* Response summary */}
                      <div className="mt-2 flex items-center gap-3 text-[10px] text-on-surface-variant">
                        <span>{r.response_summary.accepted} accepted</span>
                        <span>{r.response_summary.declined} declined</span>
                        <span>{r.response_summary.pending} pending</span>
                        <span className="ml-auto">{new Date(r.created_at).toLocaleString()}</span>
                      </div>
                    </div>
                  </div>
                </Card>
              </Link>
            );
          })}
        </div>
      )}
    </AppShell>
  );
}

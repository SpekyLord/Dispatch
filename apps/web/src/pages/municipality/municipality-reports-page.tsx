// Municipality reports page — filterable list of all system incident reports.

import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

type Report = {
  id: string;
  title?: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  is_escalated: boolean;
  created_at: string;
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

const severityColors: Record<string, string> = {
  low: "text-green-700 bg-green-100",
  medium: "text-yellow-800 bg-yellow-100",
  high: "text-orange-800 bg-orange-100",
  critical: "text-red-800 bg-red-100",
};

export function MunicipalityReportsPage() {
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("");
  const [escalationFilter, setEscalationFilter] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");

  function fetchReports() {
    setLoading(true);
    // Build query params from active filters
    const params = new URLSearchParams();
    if (statusFilter) params.set("status", statusFilter);
    if (categoryFilter) params.set("category", categoryFilter);
    if (escalationFilter) params.set("is_escalated", escalationFilter);
    if (dateFrom) params.set("date_from", dateFrom);
    if (dateTo) params.set("date_to", dateTo);
    const qs = params.toString();

    apiRequest<{ reports: Report[] }>(`/api/municipality/reports${qs ? `?${qs}` : ""}`)
      .then((res) => setReports(res.reports))
      .catch(() => setReports([]))
      .finally(() => setLoading(false));
  }

  // Re-fetch when any filter changes
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { fetchReports(); }, [statusFilter, categoryFilter, escalationFilter, dateFrom, dateTo]);

  return (
    <AppShell subtitle="System-wide incident overview" title="All Reports">
      {/* Filter bar */}
      <div className="flex flex-wrap items-center gap-3 mb-8">
        <select className="aegis-input w-auto min-w-[140px]" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="pending">Pending</option>
          <option value="accepted">Accepted</option>
          <option value="responding">Responding</option>
          <option value="resolved">Resolved</option>
        </select>
        <select className="aegis-input w-auto min-w-[140px]" value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
          <option value="">All categories</option>
          <option value="fire">Fire</option>
          <option value="flood">Flood</option>
          <option value="earthquake">Earthquake</option>
          <option value="road_accident">Road Accident</option>
          <option value="medical">Medical</option>
          <option value="structural">Structural</option>
          <option value="other">Other</option>
        </select>
        <select className="aegis-input w-auto min-w-[140px]" value={escalationFilter} onChange={(e) => setEscalationFilter(e.target.value)}>
          <option value="">All escalation</option>
          <option value="true">Escalated</option>
          <option value="false">Not escalated</option>
        </select>
        {/* Date range inputs */}
        <input type="date" className="aegis-input w-auto" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} placeholder="From" title="From date" />
        <input type="date" className="aegis-input w-auto" value={dateTo} onChange={(e) => setDateTo(e.target.value)} placeholder="To" title="To date" />
        <Button variant="ghost" onClick={() => { fetchReports(); }}>
          <span className="material-symbols-outlined text-[16px] mr-1">refresh</span>
          Refresh
        </Button>
        <span className="ml-auto text-xs text-on-surface-variant">
          {reports.length} report{reports.length !== 1 ? "s" : ""}
        </span>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl mb-4 block animate-pulse">hourglass_empty</span>
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

            return (
              <Link key={r.id} to={`/municipality/reports/escalated`}>
                <Card className="hover:shadow-glass transition-all hover:-translate-y-0.5 cursor-pointer">
                  <div className="flex gap-4">
                    {/* Category icon */}
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                      <span className="material-symbols-outlined">{categoryIcons[r.category] ?? "emergency"}</span>
                    </div>

                    <div className="flex-grow min-w-0">
                      <div className="flex items-start justify-between gap-3">
                        <h3 className="text-sm font-semibold text-on-surface truncate">
                          {r.title || r.description}
                        </h3>
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

                      {/* Meta: category, severity, timestamp */}
                      <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
                        <span className="rounded bg-surface-container-highest px-2 py-0.5 font-medium capitalize text-on-surface-variant">
                          {r.category.replace("_", " ")}
                        </span>
                        <span className={`rounded px-2 py-0.5 font-medium capitalize ${sevStyle}`}>
                          {r.severity}
                        </span>
                        <span className="ml-auto text-[10px] text-on-surface-variant">
                          {new Date(r.created_at).toLocaleString()}
                        </span>
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

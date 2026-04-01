// Municipality reports page — filterable list of all system incident reports.

import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";
import { useLocale } from "@/lib/i18n/locale-context";

type Report = {
  id: string;
  title?: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  is_escalated: boolean;
  is_mesh_origin?: boolean;
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
  const { t, getCategoryLabel, getSeverityLabel, getStatusLabel } = useLocale();
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
    <AppShell subtitle={t("reports.subtitle")} title={t("reports.title")}>
      {/* Filter bar */}
      <div className="flex flex-wrap items-center gap-3 mb-8">
        <select aria-label={t("detail.status")} className="aegis-input w-auto min-w-[140px]" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">{t("reports.filter.allStatuses")}</option>
          <option value="pending">{getStatusLabel("pending")}</option>
          <option value="accepted">{getStatusLabel("accepted")}</option>
          <option value="responding">{getStatusLabel("responding")}</option>
          <option value="resolved">{getStatusLabel("resolved")}</option>
        </select>
        <select aria-label={t("detail.category")} className="aegis-input w-auto min-w-[140px]" value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
          <option value="">{t("reports.filter.allCategories")}</option>
          <option value="fire">{getCategoryLabel("fire")}</option>
          <option value="flood">{getCategoryLabel("flood")}</option>
          <option value="earthquake">{getCategoryLabel("earthquake")}</option>
          <option value="road_accident">{getCategoryLabel("road_accident")}</option>
          <option value="medical">{getCategoryLabel("medical")}</option>
          <option value="structural">{getCategoryLabel("structural")}</option>
          <option value="other">{getCategoryLabel("other")}</option>
        </select>
        <select aria-label={t("detail.escalatedLabel")} className="aegis-input w-auto min-w-[140px]" value={escalationFilter} onChange={(e) => setEscalationFilter(e.target.value)}>
          <option value="">{t("reports.filter.allEscalation")}</option>
          <option value="true">{t("reports.filter.escalated")}</option>
          <option value="false">{t("reports.filter.notEscalated")}</option>
        </select>
        {/* Date range inputs */}
        <input type="date" className="aegis-input w-auto" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} placeholder={t("reports.filter.fromDate")} title={t("reports.filter.fromDate")} />
        <input type="date" className="aegis-input w-auto" value={dateTo} onChange={(e) => setDateTo(e.target.value)} placeholder={t("reports.filter.toDate")} title={t("reports.filter.toDate")} />
        <Button variant="ghost" onClick={() => { fetchReports(); }}>
          <span className="material-symbols-outlined text-[16px] mr-1">refresh</span>
          {t("reports.refresh")}
        </Button>
        <span className="ml-auto text-xs text-on-surface-variant">
          {t("reports.count", { count: reports.length })}
        </span>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl mb-4 block animate-pulse">hourglass_empty</span>
          {t("reports.loading")}
        </Card>
      ) : reports.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">inbox</span>
          <p className="text-on-surface-variant">{t("reports.empty")}</p>
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
                          {r.is_mesh_origin && (
                            <span className="rounded-md bg-cyan-100 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-cyan-800">
                              {t("reports.meshBadge")}
                            </span>
                          )}
                          {r.is_escalated && (
                            <span className="rounded-md bg-red-100 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-red-800">
                              {t("reports.escalatedBadge")}
                            </span>
                          )}
                          <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                            {getStatusLabel(r.status)}
                          </span>
                        </div>
                      </div>

                      {/* Meta: category, severity, timestamp */}
                      <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
                        <span className="rounded bg-surface-container-highest px-2 py-0.5 font-medium capitalize text-on-surface-variant">
                          {getCategoryLabel(r.category)}
                        </span>
                        <span className={`rounded px-2 py-0.5 font-medium capitalize ${sevStyle}`}>
                          {getSeverityLabel(r.severity)}
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

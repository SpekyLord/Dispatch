import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

/**
 * Phase 1 — Citizen home / report list.
 * Aegis-styled dashboard with report cards, status badges, and a FAB-style
 * "New Report" action in the page header.
 */

type Report = {
  id: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string;
  created_at: string;
  image_urls?: string[];
};

/* Phase 1 status colour mapping — matches Aegis palette */
const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]" },
  accepted: { bg: "bg-tertiary-container", text: "text-[#3a4e6a]" },
  responding: { bg: "bg-[#e5e2de]", text: "text-[#52524f]" },
  resolved: { bg: "bg-[#d4edda]", text: "text-[#155724]" },
};

/* Material icon per report category */
const categoryIcons: Record<string, string> = {
  fire: "local_fire_department",
  flood: "water_drop",
  earthquake: "vibration",
  road_accident: "car_crash",
  medical: "medical_services",
  structural: "domain_disabled",
  other: "emergency",
};

export function CitizenHomePage() {
  const [reports, setReports] = useState<Report[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiRequest<{ reports: Report[] }>("/api/reports")
      .then((res) => setReports(res.reports))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  return (
    <AppShell subtitle="Citizen dashboard" title="My Reports">
      {/* Action bar */}
      <div className="flex items-center justify-between mb-8">
        <p className="text-sm text-on-surface-variant">
          {reports.length === 0 && !loading
            ? "You have not submitted any reports yet."
            : `${reports.length} report${reports.length !== 1 ? "s" : ""} on file`}
        </p>
        <Link to="/citizen/report/new">
          <Button variant="secondary">
            <span className="material-symbols-outlined text-[16px] mr-2">add</span>
            New Report
          </Button>
        </Link>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl mb-4 block animate-pulse">hourglass_empty</span>
          Loading reports...
        </Card>
      ) : reports.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">description</span>
          <p className="text-on-surface-variant">No reports submitted yet. Create your first report.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {reports.map((r) => {
            const style = statusStyles[r.status] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
            return (
              <Link key={r.id} to={`/citizen/report/${r.id}`}>
                <Card className="hover:shadow-glass transition-all hover:-translate-y-0.5 cursor-pointer">
                  <div className="flex gap-4">
                    {/* Category icon */}
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                      <span className="material-symbols-outlined">{categoryIcons[r.category] ?? "emergency"}</span>
                    </div>

                    {/* Content */}
                    <div className="flex-grow min-w-0">
                      <div className="flex items-start justify-between gap-3">
                        <h3 className="text-sm font-semibold text-on-surface truncate">{r.description}</h3>
                        <span className={`shrink-0 rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                          {r.status}
                        </span>
                      </div>
                      <div className="mt-2 flex flex-wrap gap-2 text-xs">
                        <span className="rounded bg-surface-container-highest px-2 py-0.5 font-medium capitalize text-on-surface-variant">
                          {r.category.replace("_", " ")}
                        </span>
                        <span className="rounded bg-surface-container-highest px-2 py-0.5 capitalize text-on-surface-variant">
                          {r.severity}
                        </span>
                        {r.address && (
                          <span className="text-on-surface-variant truncate max-w-[200px]">
                            <span className="material-symbols-outlined text-[12px] align-middle mr-0.5">location_on</span>
                            {r.address}
                          </span>
                        )}
                      </div>
                      <p className="mt-1.5 text-[10px] uppercase tracking-wider text-outline">
                        {new Date(r.created_at).toLocaleString()}
                      </p>
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

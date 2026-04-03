import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type EscalatedReport = {
  id: string;
  title: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string;
  created_at: string;
  is_escalated: boolean;
  response_summary: { accepted: number; declined: number; pending: number };
};

const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]" },
  accepted: { bg: "bg-tertiary-container", text: "text-[#3a4e6a]" },
  responding: { bg: "bg-[#e5e2de]", text: "text-[#52524f]" },
  resolved: { bg: "bg-[#d4edda]", text: "text-[#155724]" },
};

const categoryLabels: Record<string, string> = {
  fire: "Fire",
  flood: "Flood",
  earthquake: "Earthquake",
  road_accident: "Road Accident",
  medical: "Medical",
  structural: "Structural",
  other: "Other",
};

function formatElapsed(createdAt: string) {
  const diffMs = Date.now() - new Date(createdAt).getTime();
  const totalMinutes = Math.max(Math.floor(diffMs / 60000), 0);
  if (totalMinutes < 1) {
    return "just now";
  }
  if (totalMinutes < 60) {
    return `${totalMinutes} min ago`;
  }
  const totalHours = Math.floor(totalMinutes / 60);
  if (totalHours < 24) {
    return `${totalHours} hr ago`;
  }
  const totalDays = Math.floor(totalHours / 24);
  return `${totalDays} day${totalDays === 1 ? "" : "s"} ago`;
}

export function MunicipalityEscalatedReportsPage() {
  const accessToken = useSessionStore((state) => state.accessToken);
  const [reports, setReports] = useState<EscalatedReport[]>([]);
  const [loading, setLoading] = useState(true);

  function fetchReports(showLoader = true) {
    if (showLoader) {
      setLoading(true);
    }

    return apiRequest<{ reports: EscalatedReport[] }>("/api/municipality/reports/escalated")
      .then((response) => setReports(response.reports))
      .catch(() => {})
      .finally(() => {
        if (showLoader) {
          setLoading(false);
        }
      });
  }

  useEffect(() => {
    queueMicrotask(() => {
      void fetchReports();
    });
  }, []);

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
  }, [accessToken]);

  return (
    <AppShell subtitle="Escalated emergencies" title="Municipality Escalations">
      <div className="mb-8 max-w-3xl">
        <p className="text-sm text-on-surface-variant">
          This Phase 2 view is intentionally focused on unresolved escalated incidents only. It is meant
          to surface unattended emergencies quickly without pulling the full analytics dashboard forward.
        </p>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading escalated incidents...
        </Card>
      ) : reports.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">task_alt</span>
          <p className="text-on-surface-variant">No unresolved escalated incidents right now.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {reports.map((report) => {
            const statusStyle = statusStyles[report.status] ?? {
              bg: "bg-surface-container-highest",
              text: "text-on-surface-variant",
            };

            return (
              <Card key={report.id} className="border-[#f0c7b6]/40 bg-[#fffaf7]">
                <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded-md bg-red-100 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-red-800">
                        Escalated
                      </span>
                      <span
                        className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${statusStyle.bg} ${statusStyle.text}`}
                      >
                        {report.status}
                      </span>
                      <span className="rounded bg-surface-container-highest px-2 py-0.5 text-[10px] font-semibold uppercase tracking-widest text-on-surface-variant">
                        {categoryLabels[report.category] ?? report.category}
                      </span>
                      <span className="rounded bg-surface-container px-2 py-0.5 text-[10px] font-semibold uppercase tracking-widest text-on-surface-variant">
                        {report.severity}
                      </span>
                    </div>

                    <h2 className="mt-4 font-headline text-2xl text-on-surface">
                      {report.title || report.description}
                    </h2>
                    <p className="mt-2 text-sm leading-relaxed text-on-surface-variant">
                      {report.description}
                    </p>

                    {report.address && (
                      <p className="mt-3 text-xs text-on-surface-variant">
                        <span className="material-symbols-outlined mr-1 align-middle text-[14px]">location_on</span>
                        {report.address}
                      </p>
                    )}
                  </div>

                  <div className="grid min-w-[260px] gap-3 rounded-xl bg-surface p-4 shadow-sm">
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-on-surface-variant">Opened</span>
                      <span className="font-semibold text-on-surface">{formatElapsed(report.created_at)}</span>
                    </div>
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-on-surface-variant">Created</span>
                      <span className="text-on-surface">{new Date(report.created_at).toLocaleString()}</span>
                    </div>
                    <div className="h-px bg-outline-variant/15" />
                    <div className="grid grid-cols-3 gap-3 text-center">
                      <div className="rounded-lg bg-green-50 px-3 py-2">
                        <p className="text-lg font-semibold text-green-700">{report.response_summary.accepted}</p>
                        <p className="text-[10px] font-bold uppercase tracking-widest text-green-700">Accepted</p>
                      </div>
                      <div className="rounded-lg bg-red-50 px-3 py-2">
                        <p className="text-lg font-semibold text-red-700">{report.response_summary.declined}</p>
                        <p className="text-[10px] font-bold uppercase tracking-widest text-red-700">Declined</p>
                      </div>
                      <div className="rounded-lg bg-amber-50 px-3 py-2">
                        <p className="text-lg font-semibold text-amber-700">{report.response_summary.pending}</p>
                        <p className="text-[10px] font-bold uppercase tracking-widest text-amber-700">Pending</p>
                      </div>
                    </div>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </AppShell>
  );
}

// Municipality analytics dashboard — bento grid of metrics, category breakdown, department activity.

import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

type Analytics = {
  total_reports: number;
  by_status: Record<string, number>;
  avg_response_time_hours: number | null;
  by_category: Record<string, number>;
  department_activity: { name: string; accepts: number; declines: number }[];
  unattended_count: number;
};

// Status colour tokens reused across the app
const statusMeta: Record<string, { color: string; icon: string }> = {
  pending: { color: "#D97757", icon: "pending_actions" },
  accepted: { color: "#3a4e6a", icon: "check_circle" },
  responding: { color: "#52524f", icon: "local_shipping" },
  resolved: { color: "#155724", icon: "task_alt" },
};

export function MunicipalityAnalyticsPage() {
  const [data, setData] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);

  function fetchAnalytics() {
    setLoading(true);
    apiRequest<Analytics>("/api/municipality/analytics")
      .then(setData)
      .catch(() => setData(null))
      .finally(() => setLoading(false));
  }

  useEffect(() => {
    queueMicrotask(() => {
      fetchAnalytics();
    });
  }, []);

  if (loading) {
    return (
      <AppShell subtitle="Insights & metrics" title="Analytics">
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl animate-pulse">hourglass_empty</span>
        </Card>
      </AppShell>
    );
  }

  if (!data) {
    return (
      <AppShell subtitle="Insights & metrics" title="Analytics">
        <Card className="py-16 text-center text-on-surface-variant">Failed to load analytics.</Card>
      </AppShell>
    );
  }

  // Find the max category count for proportional bars
  const maxCategoryCount = Math.max(...Object.values(data.by_category), 1);

  return (
    <AppShell subtitle="Insights & metrics" title="Analytics">
      <div className="space-y-8">
        {/* Top metric cards */}
        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {/* Total reports */}
          <Card>
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                <span className="material-symbols-outlined">summarize</span>
              </div>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Total Reports</p>
            </div>
            <p className="text-4xl font-headline italic text-on-surface">{data.total_reports}</p>
          </Card>

          {/* Avg response time */}
          <Card>
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 rounded-lg bg-tertiary-container flex items-center justify-center text-tertiary">
                <span className="material-symbols-outlined">schedule</span>
              </div>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Avg Response</p>
            </div>
            <p className="text-4xl font-headline italic text-on-surface">
              {data.avg_response_time_hours != null ? `${data.avg_response_time_hours.toFixed(1)}h` : "N/A"}
            </p>
          </Card>

          {/* Unattended — highlighted if > 0 */}
          <Card className={data.unattended_count > 0 ? "bg-[#fff5ef] border-[#f4c7b7]/40" : ""}>
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 rounded-lg bg-[#ffdbd0] flex items-center justify-center text-[#89391e]">
                <span className="material-symbols-outlined">warning</span>
              </div>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Unattended</p>
            </div>
            <p className="text-4xl font-headline italic text-on-surface">{data.unattended_count}</p>
          </Card>

          {/* Resolved */}
          <Card>
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 rounded-lg bg-[#d4edda] flex items-center justify-center text-[#155724]">
                <span className="material-symbols-outlined">task_alt</span>
              </div>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Resolved</p>
            </div>
            <p className="text-4xl font-headline italic text-on-surface">{data.by_status["resolved"] ?? 0}</p>
          </Card>
        </div>

        {/* Reports by status */}
        <Card>
          <h3 className="font-headline text-xl mb-6">Reports by Status</h3>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {Object.entries(statusMeta).map(([status, meta]) => (
              <div key={status} className="flex items-center gap-3">
                <span className="material-symbols-outlined text-[20px]" style={{ color: meta.color }}>{meta.icon}</span>
                <div>
                  <p className="text-2xl font-headline italic text-on-surface">{data.by_status[status] ?? 0}</p>
                  <p className="text-[10px] uppercase tracking-widest text-on-surface-variant font-bold capitalize">{status}</p>
                </div>
              </div>
            ))}
          </div>
        </Card>

        {/* Category breakdown — horizontal bars */}
        <Card>
          <h3 className="font-headline text-xl mb-6">Category Breakdown</h3>
          <div className="space-y-3">
            {Object.entries(data.by_category).map(([category, count]) => (
              <div key={category}>
                <div className="flex justify-between text-sm mb-1">
                  <span className="capitalize text-on-surface">{category.replace("_", " ")}</span>
                  <span className="text-on-surface-variant font-medium">{count}</span>
                </div>
                {/* CSS percentage bar */}
                <div className="h-2 rounded-full bg-surface-container-highest overflow-hidden">
                  <div
                    className="h-full rounded-full bg-[#D97757] transition-all duration-500"
                    style={{ width: `${(count / maxCategoryCount) * 100}%` }}
                  />
                </div>
              </div>
            ))}
            {Object.keys(data.by_category).length === 0 && (
              <p className="text-sm text-on-surface-variant italic">No category data yet.</p>
            )}
          </div>
        </Card>

        {/* Department activity */}
        <Card>
          <h3 className="font-headline text-xl mb-6">Department Activity</h3>
          {data.department_activity.length === 0 ? (
            <p className="text-sm text-on-surface-variant italic">No department activity recorded.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-outline-variant/15">
                    <th className="text-left py-2 text-[10px] uppercase tracking-widest text-on-surface-variant font-bold">Department</th>
                    <th className="text-right py-2 text-[10px] uppercase tracking-widest text-on-surface-variant font-bold">Accepts</th>
                    <th className="text-right py-2 text-[10px] uppercase tracking-widest text-on-surface-variant font-bold">Declines</th>
                  </tr>
                </thead>
                <tbody>
                  {data.department_activity.map((dept) => (
                    <tr key={dept.name} className="border-b border-outline-variant/10 last:border-0">
                      <td className="py-2 text-on-surface">{dept.name}</td>
                      <td className="py-2 text-right text-green-700 font-medium">{dept.accepts}</td>
                      <td className="py-2 text-right text-red-700 font-medium">{dept.declines}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>

        <div className="flex justify-end">
          <Button variant="ghost" onClick={fetchAnalytics}>
            <span className="material-symbols-outlined text-[16px] mr-1">refresh</span>
            Refresh Data
          </Button>
        </div>
      </div>
    </AppShell>
  );
}

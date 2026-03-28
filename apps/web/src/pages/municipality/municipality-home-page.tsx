import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

/**
 * Phase 1 — Municipality overview dashboard.
 * Aegis-styled bento cards: pending verification count, total departments,
 * and an analytics placeholder (Phase 3).
 */

type Department = { id: string; name: string; type: string; verification_status: string };

export function MunicipalityHomePage() {
  const [pendingCount, setPendingCount] = useState(0);
  const [totalCount, setTotalCount] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      apiRequest<{ departments: Department[] }>("/api/municipality/departments/pending"),
      apiRequest<{ departments: Department[] }>("/api/municipality/departments"),
    ])
      .then(([pending, all]) => { setPendingCount(pending.departments.length); setTotalCount(all.departments.length); })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  return (
    <AppShell subtitle="Administrative dashboard" title="Regional Stability">
      <div className="grid gap-6 md:grid-cols-12">
        {/* Pending verification card */}
        <Card className="md:col-span-4">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
              <span className="material-symbols-outlined">pending_actions</span>
            </div>
            <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
              Pending Verification
            </p>
          </div>
          <p className="text-5xl font-headline italic text-on-surface mb-6">
            {loading ? "..." : pendingCount}
          </p>
          <Link to="/municipality/verification">
            <Button variant="secondary" className="w-full">Review Queue</Button>
          </Link>
        </Card>

        {/* Total departments card */}
        <Card className="md:col-span-4">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-lg bg-tertiary-container flex items-center justify-center text-tertiary">
              <span className="material-symbols-outlined">domain</span>
            </div>
            <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
              Total Departments
            </p>
          </div>
          <p className="text-5xl font-headline italic text-on-surface mb-6">
            {loading ? "..." : totalCount}
          </p>
          <Link to="/municipality/departments">
            <Button variant="outline" className="w-full">View All</Button>
          </Link>
        </Card>

        {/* Analytics placeholder — Phase 3 */}
        <Card className="md:col-span-4 bg-surface-container">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-lg bg-surface-container-highest flex items-center justify-center text-on-surface-variant">
              <span className="material-symbols-outlined">analytics</span>
            </div>
            <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
              Analytics
            </p>
          </div>
          <p className="text-sm text-on-surface-variant leading-relaxed italic mt-2">
            Analytics dashboard with incident trends, department performance, and community resilience
            metrics will be available in Phase 3.
          </p>
        </Card>

        <Card className="md:col-span-12 bg-[#fff5ef] border-[#f4c7b7]/40">
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-[11px] font-bold uppercase tracking-widest text-[#B25A3B]">
                Phase 2 Escalations
              </p>
              <h2 className="mt-2 font-headline text-2xl text-on-surface">Unattended Incident Queue</h2>
              <p className="mt-2 max-w-2xl text-sm text-on-surface-variant">
                Review escalated incidents that still need attention. This stays intentionally narrow in
                Phase 2 so municipality users can focus on unattended emergencies before the full reports
                dashboard lands in Phase 3.
              </p>
            </div>
            <Link to="/municipality/reports/escalated">
              <Button variant="secondary">Open Escalations</Button>
            </Link>
          </div>
        </Card>
      </div>
    </AppShell>
  );
}

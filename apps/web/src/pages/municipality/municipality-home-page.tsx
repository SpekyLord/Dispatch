import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";
import { useLocale } from "@/lib/i18n/locale-context";

// Municipality overview dashboard — bento cards for key metrics and quick links.

type Department = { id: string; name: string; type: string; verification_status: string };

export function MunicipalityHomePage() {
  const { t } = useLocale();
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

        {/* Analytics card — links to Phase 3 dashboard */}
        <Card className="md:col-span-4">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-lg bg-surface-container-highest flex items-center justify-center text-[#D97757]">
              <span className="material-symbols-outlined">analytics</span>
            </div>
            <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
              {t("analytics.title")}
            </p>
          </div>
          <p className="text-sm text-on-surface-variant leading-relaxed mt-2 mb-6">
            Response metrics, category trends, and department performance.
          </p>
          <Link to="/municipality/analytics">
            <Button variant="outline" className="w-full">View Analytics</Button>
          </Link>
        </Card>

        {/* Quick links row */}
        <Card className="md:col-span-4">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
              <span className="material-symbols-outlined">summarize</span>
            </div>
            <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
              {t("reports.title")}
            </p>
          </div>
          <p className="text-sm text-on-surface-variant leading-relaxed mt-2 mb-6">
            System-wide incident reports with filters and search.
          </p>
          <Link to="/municipality/reports">
            <Button variant="outline" className="w-full">Browse Reports</Button>
          </Link>
        </Card>

        <Card className="md:col-span-4">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-lg bg-tertiary-container flex items-center justify-center text-tertiary">
              <span className="material-symbols-outlined">assessment</span>
            </div>
            <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
              {t("assessments.title")}
            </p>
          </div>
          <p className="text-sm text-on-surface-variant leading-relaxed mt-2 mb-6">
            Damage assessments submitted by field departments.
          </p>
          <Link to="/municipality/assessments">
            <Button variant="outline" className="w-full">View Assessments</Button>
          </Link>
        </Card>

        <Card className="md:col-span-12 bg-[#fff5ef] border-[#f4c7b7]/40">
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-[11px] font-bold uppercase tracking-widest text-[#B25A3B]">
                Escalations
              </p>
              <h2 className="mt-2 font-headline text-2xl text-on-surface">Unattended Incident Queue</h2>
              <p className="mt-2 max-w-2xl text-sm text-on-surface-variant">
                Review escalated incidents that still need attention from departments.
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

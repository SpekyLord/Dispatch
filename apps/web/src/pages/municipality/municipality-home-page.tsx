import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

type Department = {
  id: string;
  name: string;
  type: string;
  verification_status: string;
  contact_number?: string;
  address?: string;
  created_at: string;
};

export function MunicipalityHomePage() {
  const [pendingCount, setPendingCount] = useState(0);
  const [totalCount, setTotalCount] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      apiRequest<{ departments: Department[] }>("/api/municipality/departments/pending"),
      apiRequest<{ departments: Department[] }>("/api/municipality/departments"),
    ])
      .then(([pending, all]) => {
        setPendingCount(pending.departments.length);
        setTotalCount(all.departments.length);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  return (
    <AppShell subtitle="Administrative dashboard" title="Municipality Overview">
      <div className="grid gap-6 md:grid-cols-3">
        <Card>
          <p className="text-sm font-semibold uppercase tracking-[0.22em] text-accent">
            Pending verification
          </p>
          <p className="mt-2 text-4xl font-semibold">{loading ? "…" : pendingCount}</p>
          <Link to="/municipality/verification" className="mt-4 inline-block">
            <Button>Review Queue</Button>
          </Link>
        </Card>

        <Card>
          <p className="text-sm font-semibold uppercase tracking-[0.22em] text-accent">
            Total departments
          </p>
          <p className="mt-2 text-4xl font-semibold">{loading ? "…" : totalCount}</p>
          <Link to="/municipality/departments" className="mt-4 inline-block">
            <Button variant="outline">View All</Button>
          </Link>
        </Card>

        <Card>
          <p className="text-sm font-semibold uppercase tracking-[0.22em] text-muted-foreground">
            Analytics
          </p>
          <p className="mt-2 text-lg text-muted-foreground">
            Analytics dashboard will be available in Phase 3.
          </p>
        </Card>
      </div>
    </AppShell>
  );
}

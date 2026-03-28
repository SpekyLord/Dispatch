import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

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

const statusColors: Record<string, string> = {
  pending: "bg-yellow-100 text-yellow-800",
  accepted: "bg-blue-100 text-blue-800",
  responding: "bg-purple-100 text-purple-800",
  resolved: "bg-green-100 text-green-800",
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
      <div className="mb-6 flex items-center justify-between">
        <p className="text-muted-foreground">
          {reports.length === 0 && !loading
            ? "You have not submitted any reports yet."
            : `${reports.length} report${reports.length !== 1 ? "s" : ""}`}
        </p>
        <Link to="/citizen/report/new">
          <Button>New Report</Button>
        </Link>
      </div>

      {loading ? (
        <Card className="py-10 text-center text-muted-foreground">Loading reports…</Card>
      ) : (
        <div className="space-y-3">
          {reports.map((r) => (
            <Link key={r.id} to={`/citizen/report/${r.id}`}>
              <Card className="transition-transform hover:-translate-y-0.5">
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{r.description}</p>
                    <div className="mt-1.5 flex flex-wrap gap-2 text-xs text-muted-foreground">
                      <span className="rounded bg-muted px-2 py-0.5 capitalize">{r.category.replace("_", " ")}</span>
                      <span className="rounded bg-muted px-2 py-0.5 capitalize">{r.severity}</span>
                      {r.address && <span className="truncate">{r.address}</span>}
                    </div>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-3 py-1 text-xs font-semibold capitalize ${statusColors[r.status] ?? "bg-gray-100 text-gray-800"}`}
                  >
                    {r.status}
                  </span>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">
                  {new Date(r.created_at).toLocaleString()}
                </p>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </AppShell>
  );
}

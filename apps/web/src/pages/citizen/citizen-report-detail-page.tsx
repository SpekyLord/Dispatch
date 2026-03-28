import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { LocationMap } from "@/components/maps/location-map";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

type StatusHistory = {
  id: string;
  status: string;
  note?: string;
  created_at: string;
};

type Report = {
  id: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string;
  latitude?: number;
  longitude?: number;
  is_escalated: boolean;
  image_urls?: string[];
  created_at: string;
  updated_at: string;
};

const statusColors: Record<string, string> = {
  pending: "bg-yellow-100 text-yellow-800",
  accepted: "bg-blue-100 text-blue-800",
  responding: "bg-purple-100 text-purple-800",
  resolved: "bg-green-100 text-green-800",
};

export function CitizenReportDetailPage() {
  const { reportId } = useParams<{ reportId: string }>();
  const [report, setReport] = useState<Report | null>(null);
  const [history, setHistory] = useState<StatusHistory[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!reportId) return;
    apiRequest<{ report: Report; status_history: StatusHistory[] }>(`/api/reports/${reportId}`)
      .then((res) => {
        setReport(res.report);
        setHistory(res.status_history);
      })
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load report."))
      .finally(() => setLoading(false));
  }, [reportId]);

  if (loading) {
    return (
      <AppShell subtitle="Report details" title="Loading…">
        <Card className="py-10 text-center text-muted-foreground">Loading report…</Card>
      </AppShell>
    );
  }

  if (error || !report) {
    return (
      <AppShell subtitle="Report details" title="Error">
        <Card className="py-10 text-center text-red-600">{error ?? "Report not found."}</Card>
      </AppShell>
    );
  }

  return (
    <AppShell subtitle="Report details" title={`Report #${report.id.slice(0, 8)}`}>
      <div className="mb-4">
        <Link to="/citizen">
          <Button variant="outline" className="text-sm">
            ← Back to reports
          </Button>
        </Link>
      </div>

      <div className="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
        <div className="space-y-4">
          <Card>
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold">Incident Details</h2>
                <p className="mt-1 text-xs text-muted-foreground">
                  Submitted {new Date(report.created_at).toLocaleString()}
                </p>
              </div>
              <span
                className={`shrink-0 rounded-full px-3 py-1 text-xs font-semibold capitalize ${statusColors[report.status] ?? "bg-gray-100 text-gray-800"}`}
              >
                {report.status}
              </span>
            </div>

            <p className="mt-4">{report.description}</p>

            <div className="mt-4 flex flex-wrap gap-2 text-xs">
              <span className="rounded bg-muted px-2.5 py-1 font-medium capitalize">
                {report.category.replace("_", " ")}
              </span>
              <span className="rounded bg-muted px-2.5 py-1 capitalize">{report.severity}</span>
              {report.is_escalated && (
                <span className="rounded bg-red-100 px-2.5 py-1 font-medium text-red-700">
                  Escalated
                </span>
              )}
            </div>

            {report.address && (
              <p className="mt-3 text-sm text-muted-foreground">📍 {report.address}</p>
            )}
          </Card>

          {/* Images */}
          {report.image_urls && report.image_urls.length > 0 && (
            <Card>
              <h3 className="mb-3 font-medium">Attached Photos</h3>
              <div className="grid grid-cols-2 gap-2 md:grid-cols-3">
                {report.image_urls.map((url, i) => (
                  <img
                    key={i}
                    src={url}
                    alt={`Report image ${i + 1}`}
                    className="rounded-lg border border-border object-cover aspect-square"
                  />
                ))}
              </div>
            </Card>
          )}

          {/* Status History */}
          <Card>
            <h3 className="mb-3 font-medium">Status History</h3>
            {history.length === 0 ? (
              <p className="text-sm text-muted-foreground">No status updates yet.</p>
            ) : (
              <div className="space-y-3">
                {history.map((h) => (
                  <div
                    key={h.id}
                    className="flex items-start gap-3 border-l-2 border-border pl-4"
                  >
                    <div>
                      <span
                        className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-semibold capitalize ${statusColors[h.status] ?? "bg-gray-100 text-gray-800"}`}
                      >
                        {h.status}
                      </span>
                      {h.note && <p className="mt-1 text-sm text-muted-foreground">{h.note}</p>}
                      <p className="mt-0.5 text-xs text-muted-foreground">
                        {new Date(h.created_at).toLocaleString()}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>

        {/* Map */}
        <div>
          {report.latitude && report.longitude ? (
            <LocationMap latitude={report.latitude} longitude={report.longitude} />
          ) : (
            <Card className="flex h-64 items-center justify-center text-sm text-muted-foreground">
              No GPS coordinates available
            </Card>
          )}
        </div>
      </div>
    </AppShell>
  );
}

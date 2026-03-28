// Department report detail — view report info, accept/decline, update status, response roster.

import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

type Report = {
  id: string;
  title: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address?: string;
  created_at: string;
  image_urls?: string[];
  is_escalated: boolean;
};

type StatusEntry = {
  id: string;
  old_status: string | null;
  new_status: string;
  notes?: string;
  created_at: string;
};

type RosterEntry = {
  department_id: string;
  department_name: string;
  department_type: string;
  state: string;
  decline_reason?: string | null;
  notes?: string | null;
  responded_at?: string | null;
  is_requesting_department: boolean;
};

const statusStyles: Record<string, { bg: string; text: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]" },
  accepted: { bg: "bg-tertiary-container", text: "text-[#3a4e6a]" },
  responding: { bg: "bg-[#e5e2de]", text: "text-[#52524f]" },
  resolved: { bg: "bg-[#d4edda]", text: "text-[#155724]" },
};

const rosterStateStyles: Record<string, string> = {
  accepted: "bg-green-100 text-green-800",
  declined: "bg-red-100 text-red-800",
  pending: "bg-yellow-100 text-yellow-800",
};

export function DepartmentReportDetailPage() {
  const { reportId } = useParams<{ reportId: string }>();
  const [report, setReport] = useState<Report | null>(null);
  const [history, setHistory] = useState<StatusEntry[]>([]);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [declineReason, setDeclineReason] = useState("");
  const [notes, setNotes] = useState("");
  const [showDeclineForm, setShowDeclineForm] = useState(false);

  // Fetch report, status history, and response roster
  function fetchAll() {
    if (!reportId) return;
    setLoading(true);
    Promise.all([
      apiRequest<{ report: Report; status_history: StatusEntry[] }>(`/api/reports/${reportId}`),
      apiRequest<{ report: Report; responses: RosterEntry[] }>(`/api/departments/reports/${reportId}/responses`),
    ])
      .then(([detail, rosterRes]) => {
        setReport(detail.report);
        setHistory(detail.status_history);
        setRoster(rosterRes.responses);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }

  useEffect(() => { fetchAll(); }, [reportId]); // eslint-disable-line react-hooks/exhaustive-deps

  // Accept report
  async function handleAccept() {
    setActionLoading(true); setError(null);
    try {
      await apiRequest(`/api/departments/reports/${reportId}/accept`, {
        method: "POST",
        body: JSON.stringify({ notes: notes.trim() || undefined }),
      });
      setNotes("");
      fetchAll();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Action failed.");
    } finally { setActionLoading(false); }
  }

  // Decline report
  async function handleDecline() {
    if (!declineReason.trim()) { setError("Decline reason is required."); return; }
    setActionLoading(true); setError(null);
    try {
      await apiRequest(`/api/departments/reports/${reportId}/decline`, {
        method: "POST",
        body: JSON.stringify({ decline_reason: declineReason.trim(), notes: notes.trim() || undefined }),
      });
      setDeclineReason(""); setNotes(""); setShowDeclineForm(false);
      fetchAll();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Action failed.");
    } finally { setActionLoading(false); }
  }

  // Update status (responding/resolved)
  async function handleStatusUpdate(newStatus: string) {
    setActionLoading(true); setError(null);
    try {
      await apiRequest(`/api/departments/reports/${reportId}/status`, {
        method: "PUT",
        body: JSON.stringify({ status: newStatus, notes: notes.trim() || undefined }),
      });
      setNotes("");
      fetchAll();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Action failed.");
    } finally { setActionLoading(false); }
  }

  if (loading) {
    return (
      <AppShell subtitle="Report detail" title="Loading...">
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl animate-pulse">hourglass_empty</span>
        </Card>
      </AppShell>
    );
  }

  if (!report) {
    return (
      <AppShell subtitle="Report detail" title="Not Found">
        <Card className="py-16 text-center text-on-surface-variant">Report not found.</Card>
      </AppShell>
    );
  }

  const style = statusStyles[report.status] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
  const ownResponse = roster.find((r) => r.is_requesting_department);
  const hasAccepted = ownResponse?.state === "accepted";
  const hasResponded = ownResponse != null && ownResponse.state !== "pending";
  const isOpen = report.status !== "resolved";

  return (
    <AppShell subtitle="Report detail" title={report.title || "Incident Report"}>
      <Link to="/department/reports" className="text-sm text-[#D97757] hover:underline mb-6 inline-flex items-center gap-1">
        <span className="material-symbols-outlined text-[16px]">arrow_back</span>
        Back to Board
      </Link>

      {error && (
        <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error mb-6">{error}</div>
      )}

      <div className="grid gap-6 md:grid-cols-12">
        {/* Left column — report info */}
        <div className="md:col-span-7 space-y-6">
          <Card>
            <div className="flex items-start justify-between gap-3 mb-4">
              <div className="flex items-center gap-2">
                <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                  {report.status}
                </span>
                {report.is_escalated && (
                  <span className="rounded-md bg-red-100 px-2 py-0.5 text-[10px] font-bold uppercase text-red-800">Escalated</span>
                )}
              </div>
              <span className="text-[10px] uppercase tracking-wider text-outline">{new Date(report.created_at).toLocaleString()}</span>
            </div>

            <h2 className="font-headline text-2xl text-on-surface mb-3">{report.title}</h2>
            <p className="text-sm text-on-surface-variant leading-relaxed">{report.description}</p>

            <div className="mt-4 flex flex-wrap gap-2 text-xs">
              <span className="rounded bg-surface-container-highest px-2 py-0.5 font-medium capitalize">{report.category.replace("_", " ")}</span>
              <span className="rounded bg-surface-container-highest px-2 py-0.5 capitalize">{report.severity}</span>
              {report.address && (
                <span className="flex items-center gap-0.5 text-on-surface-variant">
                  <span className="material-symbols-outlined text-[12px]">location_on</span>
                  {report.address}
                </span>
              )}
            </div>
          </Card>

          {/* Images */}
          {report.image_urls && report.image_urls.length > 0 && (
            <Card>
              <h3 className="font-headline text-lg text-on-surface mb-3">Photos</h3>
              <div className="flex gap-3 overflow-x-auto">
                {report.image_urls.map((url, i) => (
                  <img key={i} src={url} alt={`Evidence ${i + 1}`} className="h-40 rounded-lg object-cover border border-outline-variant/10" />
                ))}
              </div>
            </Card>
          )}

          {/* Status history */}
          <Card>
            <h3 className="font-headline text-lg text-on-surface mb-4">Status History</h3>
            {history.length === 0 ? (
              <p className="text-sm text-on-surface-variant">No status changes recorded.</p>
            ) : (
              <div className="space-y-3">
                {history.map((entry) => {
                  const entryStyle = statusStyles[entry.new_status] ?? { bg: "bg-surface-container", text: "text-on-surface-variant" };
                  return (
                    <div key={entry.id} className="flex items-start gap-3">
                      <div className={`mt-0.5 w-2 h-2 rounded-full shrink-0 ${entryStyle.bg}`} />
                      <div className="min-w-0">
                        <div className="flex items-center gap-2 text-xs">
                          <span className="font-semibold capitalize text-on-surface">{entry.new_status}</span>
                          <span className="text-outline">{new Date(entry.created_at).toLocaleString()}</span>
                        </div>
                        {entry.notes && <p className="text-xs text-on-surface-variant mt-0.5">{entry.notes}</p>}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </Card>
        </div>

        {/* Right column — actions + roster */}
        <div className="md:col-span-5 space-y-6">
          {/* Action panel */}
          {isOpen && (
            <Card className="bg-surface-container">
              <h3 className="font-headline text-lg text-on-surface mb-4">Actions</h3>

              {!hasResponded ? (
                <>
                  <div className="mb-3">
                    <label className="aegis-label">Notes (optional)</label>
                    <textarea className="aegis-input min-h-[60px]" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Add notes..." />
                  </div>
                  <div className="flex gap-3">
                    <Button variant="secondary" disabled={actionLoading} onClick={handleAccept}>
                      <span className="material-symbols-outlined text-[16px] mr-1">check_circle</span>
                      Accept
                    </Button>
                    <Button variant="outline" disabled={actionLoading} onClick={() => setShowDeclineForm(true)}>
                      <span className="material-symbols-outlined text-[16px] mr-1">cancel</span>
                      Decline
                    </Button>
                  </div>

                  {showDeclineForm && (
                    <div className="mt-4 p-4 rounded-lg bg-surface-container-lowest border border-outline-variant/10">
                      <label className="aegis-label">Decline Reason (required)</label>
                      <textarea className="aegis-input min-h-[60px] mb-3" value={declineReason} onChange={(e) => setDeclineReason(e.target.value)} placeholder="Why are you declining?" />
                      <div className="flex gap-2">
                        <Button disabled={actionLoading} onClick={handleDecline}>Confirm Decline</Button>
                        <Button variant="ghost" onClick={() => setShowDeclineForm(false)}>Cancel</Button>
                      </div>
                    </div>
                  )}
                </>
              ) : hasAccepted ? (
                <>
                  <p className="text-sm text-on-surface-variant mb-3">You accepted this report. Update status:</p>
                  <div className="mb-3">
                    <label className="aegis-label">Notes (optional)</label>
                    <textarea className="aegis-input min-h-[60px]" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Add notes..." />
                  </div>
                  <div className="flex gap-3">
                    {report.status === "accepted" && (
                      <Button variant="secondary" disabled={actionLoading} onClick={() => handleStatusUpdate("responding")}>
                        <span className="material-symbols-outlined text-[16px] mr-1">directions_run</span>
                        Mark Responding
                      </Button>
                    )}
                    {report.status === "responding" && (
                      <Button variant="secondary" disabled={actionLoading} onClick={() => handleStatusUpdate("resolved")}>
                        <span className="material-symbols-outlined text-[16px] mr-1">task_alt</span>
                        Mark Resolved
                      </Button>
                    )}
                  </div>
                </>
              ) : (
                <p className="text-sm text-on-surface-variant italic">You have already declined this report.</p>
              )}
            </Card>
          )}

          {/* Response roster */}
          <Card>
            <h3 className="font-headline text-lg text-on-surface mb-4">Department Responses</h3>
            {roster.length === 0 ? (
              <p className="text-sm text-on-surface-variant">No departments have been notified yet.</p>
            ) : (
              <div className="space-y-3">
                {roster.map((r) => (
                  <div key={r.department_id} className="flex items-center justify-between p-3 rounded-lg bg-surface-container">
                    <div>
                      <p className="text-sm font-semibold text-on-surface">
                        {r.department_name}
                        {r.is_requesting_department && <span className="text-[10px] ml-1 text-[#D97757]">(you)</span>}
                      </p>
                      <p className="text-xs text-on-surface-variant capitalize">{r.department_type}</p>
                      {r.decline_reason && <p className="text-xs text-error mt-0.5">Reason: {r.decline_reason}</p>}
                    </div>
                    <span className={`rounded-md px-2 py-0.5 text-[10px] font-bold uppercase ${rosterStateStyles[r.state] ?? "bg-surface-container-highest text-on-surface-variant"}`}>
                      {r.state}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      </div>
    </AppShell>
  );
}

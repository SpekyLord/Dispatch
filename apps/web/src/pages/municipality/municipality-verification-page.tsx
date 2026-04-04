import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

/**
 * Phase 1 — Municipality verification queue.
 * Aegis-styled list of pending departments with approve/reject actions.
 * Reject requires a mandatory reason input.
 */

type Department = {
  id: string; user_id: string; name: string; type: string;
  verification_status: string; rejection_reason?: string | null;
  contact_number?: string | null; address?: string | null;
  area_of_responsibility?: string | null; created_at: string;
};

const typeLabels: Record<string, string> = {
  fire: "Fire (BFP)", police: "Police (PNP)", medical: "Medical",
  disaster: "MDRRMO", rescue: "Rescue", other: "Other",
};

const typeIcons: Record<string, string> = {
  fire: "local_fire_department", police: "shield", medical: "medical_services",
  disaster: "storm", rescue: "health_and_safety", other: "domain",
};

export function MunicipalityVerificationPage() {
  const [departments, setDepartments] = useState<Department[]>([]);
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [rejectionInputs, setRejectionInputs] = useState<Record<string, string>>({});
  const [showRejectForm, setShowRejectForm] = useState<string | null>(null);

  function fetchPending() {
    setLoading(true);
    setFetchError(null);
    apiRequest<{ departments: Department[] }>("/api/municipality/departments/pending")
      .then((res) => setDepartments(res.departments))
      .catch((err) => setFetchError(err instanceof Error ? err.message : "Failed to load departments."))
      .finally(() => setLoading(false));
  }

  useEffect(() => { fetchPending(); }, []);

  async function handleApprove(deptId: string) {
    setActionLoading(deptId);
    setActionError(null);
    try {
      await apiRequest(`/api/municipality/departments/${deptId}/verify`, {
        method: "PUT", body: JSON.stringify({ action: "approved" }),
      });
      setDepartments((prev) => prev.filter((d) => d.id !== deptId));
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to approve department.");
    } finally { setActionLoading(null); }
  }

  async function handleReject(deptId: string) {
    const reason = (rejectionInputs[deptId] || "").trim();
    if (!reason) return;
    setActionLoading(deptId);
    setActionError(null);
    try {
      await apiRequest(`/api/municipality/departments/${deptId}/verify`, {
        method: "PUT", body: JSON.stringify({ action: "rejected", rejection_reason: reason }),
      });
      setDepartments((prev) => prev.filter((d) => d.id !== deptId));
      setShowRejectForm(null);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to reject department.");
    } finally { setActionLoading(null); }
  }

  return (
    <AppShell subtitle="Department verification" title="Verification Queue">
      {actionError && (
        <div className="mb-6 rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error flex items-center gap-2">
          <span className="material-symbols-outlined text-[16px]">error</span>
          {actionError}
        </div>
      )}

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots sizeClassName="h-5 w-5" />
        </Card>
      ) : fetchError ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-error mb-4 block">cloud_off</span>
          <p className="text-error mb-4">{fetchError}</p>
          <Button variant="ghost" onClick={fetchPending}>Retry</Button>
        </Card>
      ) : departments.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">task_alt</span>
          <p className="text-on-surface-variant">No departments pending verification.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {departments.map((dept) => (
            <Card key={dept.id}>
              <div className="flex items-start justify-between gap-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                    <span className="material-symbols-outlined">{typeIcons[dept.type] ?? "domain"}</span>
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-on-surface">{dept.name}</h3>
                    <span className="text-[10px] font-bold uppercase tracking-widest text-on-surface-variant">
                      {typeLabels[dept.type] ?? dept.type}
                    </span>
                  </div>
                </div>
                <span className="rounded-md bg-[#ffdbd0] px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest text-[#89391e]">
                  Pending
                </span>
              </div>

              <div className="mt-4 grid gap-3 text-sm text-on-surface-variant md:grid-cols-2">
                {dept.contact_number && (
                  <div className="flex items-center gap-2">
                    <span className="material-symbols-outlined text-[14px]">call</span>
                    {dept.contact_number}
                  </div>
                )}
                {dept.address && (
                  <div className="flex items-center gap-2">
                    <span className="material-symbols-outlined text-[14px]">location_on</span>
                    {dept.address}
                  </div>
                )}
                {dept.area_of_responsibility && (
                  <div className="flex items-center gap-2 md:col-span-2">
                    <span className="material-symbols-outlined text-[14px]">map</span>
                    {dept.area_of_responsibility}
                  </div>
                )}
                <div className="flex items-center gap-2">
                  <span className="material-symbols-outlined text-[14px]">calendar_today</span>
                  Applied {new Date(dept.created_at).toLocaleDateString()}
                </div>
              </div>

              <div className="mt-6 flex flex-wrap gap-3 border-t border-outline-variant/10 pt-4">
                <Button onClick={() => handleApprove(dept.id)} disabled={actionLoading === dept.id}>
                  {actionLoading === dept.id ? "Processing..." : "Approve"}
                </Button>

                {showRejectForm === dept.id ? (
                  <div className="flex flex-1 gap-2">
                    <input
                      type="text"
                      className="aegis-input flex-1"
                      placeholder="Reason for rejection (required)"
                      value={rejectionInputs[dept.id] ?? ""}
                      onChange={(e) => setRejectionInputs((prev) => ({ ...prev, [dept.id]: e.target.value }))}
                    />
                    <Button
                      variant="outline"
                      className="border-error/30 text-error hover:bg-error-container/10"
                      onClick={() => handleReject(dept.id)}
                      disabled={actionLoading === dept.id || !(rejectionInputs[dept.id] || "").trim()}
                    >
                      Confirm
                    </Button>
                    <Button variant="ghost" onClick={() => setShowRejectForm(null)}>Cancel</Button>
                  </div>
                ) : (
                  <Button
                    variant="outline"
                    className="border-error/30 text-error hover:bg-error-container/10"
                    onClick={() => setShowRejectForm(dept.id)}
                    disabled={actionLoading === dept.id}
                  >
                    Reject
                  </Button>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}
    </AppShell>
  );
}

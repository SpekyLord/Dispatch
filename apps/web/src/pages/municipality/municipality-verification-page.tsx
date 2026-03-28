import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

type Department = {
  id: string;
  user_id: string;
  name: string;
  type: string;
  verification_status: string;
  rejection_reason?: string | null;
  contact_number?: string | null;
  address?: string | null;
  area_of_responsibility?: string | null;
  created_at: string;
};

const typeLabels: Record<string, string> = {
  fire: "Fire (BFP)",
  police: "Police (PNP)",
  medical: "Medical",
  disaster: "Disaster Response (MDRRMO)",
  rescue: "Rescue",
  other: "Other",
};

export function MunicipalityVerificationPage() {
  const [departments, setDepartments] = useState<Department[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [rejectionInputs, setRejectionInputs] = useState<Record<string, string>>({});
  const [showRejectForm, setShowRejectForm] = useState<string | null>(null);

  function fetchPending() {
    setLoading(true);
    apiRequest<{ departments: Department[] }>("/api/municipality/departments/pending")
      .then((res) => setDepartments(res.departments))
      .catch(() => {})
      .finally(() => setLoading(false));
  }

  useEffect(() => {
    fetchPending();
  }, []);

  async function handleApprove(deptId: string) {
    setActionLoading(deptId);
    try {
      await apiRequest(`/api/municipality/departments/${deptId}/verify`, {
        method: "PUT",
        body: JSON.stringify({ action: "approved" }),
      });
      setDepartments((prev) => prev.filter((d) => d.id !== deptId));
    } catch {
      // error handled silently
    } finally {
      setActionLoading(null);
    }
  }

  async function handleReject(deptId: string) {
    const reason = (rejectionInputs[deptId] || "").trim();
    if (!reason) return;
    setActionLoading(deptId);
    try {
      await apiRequest(`/api/municipality/departments/${deptId}/verify`, {
        method: "PUT",
        body: JSON.stringify({ action: "rejected", rejection_reason: reason }),
      });
      setDepartments((prev) => prev.filter((d) => d.id !== deptId));
      setShowRejectForm(null);
    } catch {
      // error handled silently
    } finally {
      setActionLoading(null);
    }
  }

  return (
    <AppShell subtitle="Department verification" title="Verification Queue">
      {loading ? (
        <Card className="py-10 text-center text-muted-foreground">Loading…</Card>
      ) : departments.length === 0 ? (
        <Card className="py-10 text-center text-muted-foreground">
          No departments pending verification.
        </Card>
      ) : (
        <div className="space-y-4">
          {departments.map((dept) => (
            <Card key={dept.id}>
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h3 className="text-lg font-semibold">{dept.name}</h3>
                  <span className="mt-1 inline-block rounded bg-accent/10 px-2.5 py-0.5 text-xs font-semibold text-accent">
                    {typeLabels[dept.type] ?? dept.type}
                  </span>
                </div>
                <span className="shrink-0 rounded-full bg-yellow-100 px-3 py-1 text-xs font-semibold text-yellow-800">
                  Pending
                </span>
              </div>

              <div className="mt-3 grid gap-2 text-sm text-muted-foreground md:grid-cols-2">
                {dept.contact_number && (
                  <p>
                    <span className="font-medium text-foreground">Contact:</span>{" "}
                    {dept.contact_number}
                  </p>
                )}
                {dept.address && (
                  <p>
                    <span className="font-medium text-foreground">Address:</span> {dept.address}
                  </p>
                )}
                {dept.area_of_responsibility && (
                  <p className="md:col-span-2">
                    <span className="font-medium text-foreground">Area:</span>{" "}
                    {dept.area_of_responsibility}
                  </p>
                )}
                <p>
                  <span className="font-medium text-foreground">Applied:</span>{" "}
                  {new Date(dept.created_at).toLocaleDateString()}
                </p>
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  onClick={() => handleApprove(dept.id)}
                  disabled={actionLoading === dept.id}
                >
                  {actionLoading === dept.id ? "Processing…" : "Approve"}
                </Button>
                {showRejectForm === dept.id ? (
                  <div className="flex flex-1 gap-2">
                    <input
                      type="text"
                      className="flex-1 rounded-lg border border-border bg-white px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                      placeholder="Reason for rejection (required)"
                      value={rejectionInputs[dept.id] ?? ""}
                      onChange={(e) =>
                        setRejectionInputs((prev) => ({ ...prev, [dept.id]: e.target.value }))
                      }
                    />
                    <Button
                      variant="outline"
                      className="border-red-300 text-red-600 hover:bg-red-50"
                      onClick={() => handleReject(dept.id)}
                      disabled={
                        actionLoading === dept.id || !(rejectionInputs[dept.id] || "").trim()
                      }
                    >
                      Confirm Reject
                    </Button>
                    <Button variant="ghost" onClick={() => setShowRejectForm(null)}>
                      Cancel
                    </Button>
                  </div>
                ) : (
                  <Button
                    variant="outline"
                    className="border-red-300 text-red-600 hover:bg-red-50"
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

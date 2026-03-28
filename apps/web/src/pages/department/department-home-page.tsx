import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore, type DepartmentInfo } from "@/lib/auth/session-store";

/**
 * Phase 1 — Department home page.
 * Shows different Aegis-styled views based on verification status:
 *  - pending:  hourglass icon + awaiting message
 *  - rejected: alert card + edit/resubmit form
 *  - approved: verified badge + department profile + Phase 2 placeholder
 */

export function DepartmentHomePage() {
  const department = useSessionStore((s) => s.department);
  const setDepartment = useSessionStore((s) => s.setDepartment);
  const [loading, setLoading] = useState(!department);
  const [editMode, setEditMode] = useState(false);

  useEffect(() => {
    apiRequest<{ department: DepartmentInfo }>("/api/departments/profile")
      .then((res) => setDepartment(res.department))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading) {
    return (
      <AppShell subtitle="Department" title="Loading...">
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl animate-pulse">hourglass_empty</span>
        </Card>
      </AppShell>
    );
  }

  if (!department) {
    return (
      <AppShell subtitle="Department" title="No Department Profile">
        <Card className="py-16 text-center text-on-surface-variant">
          No department profile found. Contact the administrator.
        </Card>
      </AppShell>
    );
  }

  const status = department.verification_status;

  /* ── Pending view ── */
  if (status === "pending") {
    return (
      <AppShell subtitle="Awaiting verification" title="Department Registration">
        <Card className="mx-auto max-w-xl text-center py-12">
          <div className="inline-flex h-16 w-16 items-center justify-center rounded-full bg-[#ffdbd0] mb-6">
            <span className="material-symbols-outlined text-3xl text-secondary">hourglass_empty</span>
          </div>
          <h2 className="font-headline text-2xl text-on-surface">Awaiting Verification</h2>
          <p className="mt-3 text-on-surface-variant max-w-md mx-auto">
            Your department registration for <strong>{department.name}</strong> is pending
            municipality approval. Operational features unlock once approved.
          </p>
          <DeptDetails department={department} />
        </Card>
      </AppShell>
    );
  }

  /* ── Rejected view ── */
  if (status === "rejected") {
    return (
      <AppShell subtitle="Verification rejected" title="Department Registration">
        <DepartmentRejectedView
          department={department}
          onUpdated={(d) => setDepartment(d)}
          editMode={editMode}
          setEditMode={setEditMode}
        />
      </AppShell>
    );
  }

  /* ── Approved view ── */
  return (
    <AppShell subtitle="Responder operations" title={department.name}>
      <div className="grid gap-6 md:grid-cols-12">
        <Card className="md:col-span-5">
          <span className="inline-flex items-center gap-1.5 rounded-md bg-[#d4edda] px-3 py-1 text-[10px] font-bold uppercase tracking-widest text-[#155724]">
            <span className="material-symbols-outlined text-[14px]">verified</span>
            Verified
          </span>
          <h2 className="mt-4 font-headline text-2xl text-on-surface">Department Profile</h2>
          <DeptDetails department={department} />
        </Card>

        <Card className="md:col-span-7 bg-surface-container">
          <h2 className="font-headline text-2xl text-on-surface mb-2">Quick Actions</h2>
          <div className="grid gap-3 sm:grid-cols-2">
            <Link to="/department/reports">
              <div className="flex items-center gap-3 p-4 rounded-lg bg-surface-container-lowest hover:shadow-glass transition-all cursor-pointer">
                <span className="material-symbols-outlined text-secondary">assignment</span>
                <div>
                  <p className="text-sm font-semibold text-on-surface">Incident Board</p>
                  <p className="text-xs text-on-surface-variant">View and respond to reports</p>
                </div>
              </div>
            </Link>
            <Link to="/department/posts/new">
              <div className="flex items-center gap-3 p-4 rounded-lg bg-surface-container-lowest hover:shadow-glass transition-all cursor-pointer">
                <span className="material-symbols-outlined text-secondary">campaign</span>
                <div>
                  <p className="text-sm font-semibold text-on-surface">Create Post</p>
                  <p className="text-xs text-on-surface-variant">Publish an announcement</p>
                </div>
              </div>
            </Link>
            <Link to="/notifications">
              <div className="flex items-center gap-3 p-4 rounded-lg bg-surface-container-lowest hover:shadow-glass transition-all cursor-pointer">
                <span className="material-symbols-outlined text-secondary">notifications</span>
                <div>
                  <p className="text-sm font-semibold text-on-surface">Notifications</p>
                  <p className="text-xs text-on-surface-variant">Check alerts and updates</p>
                </div>
              </div>
            </Link>
            <Link to="/feed">
              <div className="flex items-center gap-3 p-4 rounded-lg bg-surface-container-lowest hover:shadow-glass transition-all cursor-pointer">
                <span className="material-symbols-outlined text-secondary">newspaper</span>
                <div>
                  <p className="text-sm font-semibold text-on-surface">Community Feed</p>
                  <p className="text-xs text-on-surface-variant">Browse public announcements</p>
                </div>
              </div>
            </Link>
          </div>
        </Card>
      </div>
    </AppShell>
  );
}

/* ── Shared department details block ── */
function DeptDetails({ department }: { department: DepartmentInfo }) {
  return (
    <div className="mt-6 rounded-lg bg-surface-container p-5 text-left text-sm space-y-2">
      <div className="flex justify-between">
        <span className="text-on-surface-variant">Type</span>
        <span className="font-medium text-on-surface capitalize">{department.type}</span>
      </div>
      {department.contact_number && (
        <div className="flex justify-between">
          <span className="text-on-surface-variant">Contact</span>
          <span className="font-medium text-on-surface">{department.contact_number}</span>
        </div>
      )}
      {department.address && (
        <div className="flex justify-between">
          <span className="text-on-surface-variant">Address</span>
          <span className="font-medium text-on-surface">{department.address}</span>
        </div>
      )}
      {department.area_of_responsibility && (
        <div className="flex justify-between">
          <span className="text-on-surface-variant">Area</span>
          <span className="font-medium text-on-surface">{department.area_of_responsibility}</span>
        </div>
      )}
    </div>
  );
}

/* ── Rejected view with edit/resubmit form ── */
function DepartmentRejectedView({
  department, onUpdated, editMode, setEditMode,
}: {
  department: DepartmentInfo; onUpdated: (d: DepartmentInfo) => void;
  editMode: boolean; setEditMode: (v: boolean) => void;
}) {
  const [name, setName] = useState(department.name);
  const [contactNumber, setContactNumber] = useState(department.contact_number ?? "");
  const [address, setAddress] = useState(department.address ?? "");
  const [area, setArea] = useState(department.area_of_responsibility ?? "");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleResubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true); setError(null);
    try {
      const res = await apiRequest<{ department: DepartmentInfo }>("/api/departments/profile", {
        method: "PUT",
        body: JSON.stringify({ name, contact_number: contactNumber, address, area_of_responsibility: area }),
      });
      onUpdated(res.department);
      setEditMode(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update.");
    } finally { setLoading(false); }
  }

  return (
    <Card className="mx-auto max-w-xl">
      <div className="text-center mb-6">
        <div className="inline-flex h-16 w-16 items-center justify-center rounded-full bg-error-container/20 mb-4">
          <span className="material-symbols-outlined text-3xl text-error">close</span>
        </div>
        <h2 className="font-headline text-2xl text-on-surface">Registration Rejected</h2>
      </div>

      {department.rejection_reason && (
        <div className="rounded-md bg-error-container/15 border border-error/15 px-4 py-3 text-sm text-error mb-6">
          <span className="font-semibold">Reason:</span> {department.rejection_reason}
        </div>
      )}

      {editMode ? (
        <form className="space-y-4" onSubmit={handleResubmit}>
          {error && (
            <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error">{error}</div>
          )}
          <div>
            <label className="aegis-label">Organization Name</label>
            <input type="text" className="aegis-input" placeholder="Organization name"
              value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div>
            <label className="aegis-label">Contact Number</label>
            <input type="text" className="aegis-input" placeholder="Contact number"
              value={contactNumber} onChange={(e) => setContactNumber(e.target.value)} />
          </div>
          <div>
            <label className="aegis-label">Address</label>
            <input type="text" className="aegis-input" placeholder="Address"
              value={address} onChange={(e) => setAddress(e.target.value)} />
          </div>
          <div>
            <label className="aegis-label">Area of Responsibility</label>
            <input type="text" className="aegis-input" placeholder="Area of responsibility"
              value={area} onChange={(e) => setArea(e.target.value)} />
          </div>
          <div className="flex gap-3 pt-2">
            <Button type="submit" disabled={loading}>
              {loading ? "Submitting..." : "Resubmit for Verification"}
            </Button>
            <Button type="button" variant="outline" onClick={() => setEditMode(false)}>Cancel</Button>
          </div>
        </form>
      ) : (
        <div className="text-center">
          <p className="text-sm text-on-surface-variant mb-6">
            Update your department details and resubmit for verification.
          </p>
          <Button variant="secondary" onClick={() => setEditMode(true)}>
            <span className="material-symbols-outlined text-[16px] mr-2">edit</span>
            Edit & Resubmit
          </Button>
        </div>
      )}
    </Card>
  );
}

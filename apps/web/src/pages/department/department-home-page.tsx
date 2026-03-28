import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore, type DepartmentInfo } from "@/lib/auth/session-store";

export function DepartmentHomePage() {
  const department = useSessionStore((s) => s.department);
  const setDepartment = useSessionStore((s) => s.setDepartment);
  const [loading, setLoading] = useState(!department);
  const [editMode, setEditMode] = useState(false);

  // Fetch fresh department data
  useEffect(() => {
    apiRequest<{ department: DepartmentInfo }>("/api/departments/profile")
      .then((res) => setDepartment(res.department))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading) {
    return (
      <AppShell subtitle="Department" title="Loading…">
        <Card className="py-10 text-center text-muted-foreground">Loading department data…</Card>
      </AppShell>
    );
  }

  if (!department) {
    return (
      <AppShell subtitle="Department" title="No Department Profile">
        <Card className="py-10 text-center text-muted-foreground">
          No department profile found. Contact the administrator.
        </Card>
      </AppShell>
    );
  }

  const status = department.verification_status;

  if (status === "pending") {
    return (
      <AppShell subtitle="Awaiting verification" title="Department Registration">
        <Card className="mx-auto max-w-xl text-center">
          <div className="mb-4 inline-flex h-16 w-16 items-center justify-center rounded-full bg-yellow-100 text-2xl">
            ⏳
          </div>
          <h2 className="text-xl font-semibold">Awaiting Verification</h2>
          <p className="mt-2 text-muted-foreground">
            Your department registration for <strong>{department.name}</strong> is pending
            municipality approval. You will be able to access operational features once approved.
          </p>
          <div className="mt-6 rounded-lg bg-muted/50 p-4 text-left text-sm">
            <p><span className="font-medium">Type:</span> {department.type}</p>
            {department.contact_number && (
              <p><span className="font-medium">Contact:</span> {department.contact_number}</p>
            )}
            {department.address && (
              <p><span className="font-medium">Address:</span> {department.address}</p>
            )}
            {department.area_of_responsibility && (
              <p><span className="font-medium">Area:</span> {department.area_of_responsibility}</p>
            )}
          </div>
        </Card>
      </AppShell>
    );
  }

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

  // Approved
  return (
    <AppShell subtitle="Responder operations" title={department.name}>
      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <span className="inline-block rounded-full bg-green-100 px-3 py-1 text-xs font-semibold text-green-800">
            Verified
          </span>
          <h2 className="mt-3 text-xl font-semibold">Department Profile</h2>
          <div className="mt-3 space-y-1 text-sm text-muted-foreground">
            <p><span className="font-medium text-foreground">Type:</span> {department.type}</p>
            {department.contact_number && (
              <p><span className="font-medium text-foreground">Contact:</span> {department.contact_number}</p>
            )}
            {department.address && (
              <p><span className="font-medium text-foreground">Address:</span> {department.address}</p>
            )}
          </div>
        </Card>

        <Card>
          <h2 className="text-xl font-semibold">Incident Board</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            The department incident board with accept/decline actions will be available in Phase 2.
          </p>
        </Card>
      </div>
    </AppShell>
  );
}

function DepartmentRejectedView({
  department,
  onUpdated,
  editMode,
  setEditMode,
}: {
  department: DepartmentInfo;
  onUpdated: (d: DepartmentInfo) => void;
  editMode: boolean;
  setEditMode: (v: boolean) => void;
}) {
  const [name, setName] = useState(department.name);
  const [contactNumber, setContactNumber] = useState(department.contact_number ?? "");
  const [address, setAddress] = useState(department.address ?? "");
  const [area, setArea] = useState(department.area_of_responsibility ?? "");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleResubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await apiRequest<{ department: DepartmentInfo }>("/api/departments/profile", {
        method: "PUT",
        body: JSON.stringify({
          name,
          contact_number: contactNumber,
          address,
          area_of_responsibility: area,
        }),
      });
      onUpdated(res.department);
      setEditMode(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Card className="mx-auto max-w-xl">
      <div className="mb-4 inline-flex h-16 w-16 items-center justify-center rounded-full bg-red-100 text-2xl">
        ✕
      </div>
      <h2 className="text-xl font-semibold">Registration Rejected</h2>
      {department.rejection_reason && (
        <div className="mt-3 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          <span className="font-medium">Reason:</span> {department.rejection_reason}
        </div>
      )}

      {editMode ? (
        <form className="mt-4 space-y-3" onSubmit={handleResubmit}>
          {error && (
            <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}
          <input
            type="text"
            className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm"
            placeholder="Organization name"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <input
            type="text"
            className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm"
            placeholder="Contact number"
            value={contactNumber}
            onChange={(e) => setContactNumber(e.target.value)}
          />
          <input
            type="text"
            className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm"
            placeholder="Address"
            value={address}
            onChange={(e) => setAddress(e.target.value)}
          />
          <input
            type="text"
            className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm"
            placeholder="Area of responsibility"
            value={area}
            onChange={(e) => setArea(e.target.value)}
          />
          <div className="flex gap-2">
            <Button type="submit" disabled={loading}>
              {loading ? "Submitting…" : "Resubmit for Verification"}
            </Button>
            <Button type="button" variant="outline" onClick={() => setEditMode(false)}>
              Cancel
            </Button>
          </div>
        </form>
      ) : (
        <div className="mt-4">
          <p className="text-sm text-muted-foreground">
            You can update your department details and resubmit for verification.
          </p>
          <Button className="mt-4" onClick={() => setEditMode(true)}>
            Edit & Resubmit
          </Button>
        </div>
      )}
    </Card>
  );
}

import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore, type DepartmentInfo } from "@/lib/auth/session-store";

/**
 * Department home page.
 * Shows different views based on verification status:
 *  - pending: awaiting approval message
 *  - rejected: edit and resubmit form
 *  - approved: placeholder dashboard layout
 */

export function DepartmentHomePage() {
  const department = useSessionStore((s) => s.department);
  const setDepartment = useSessionStore((s) => s.setDepartment);
  const [loading, setLoading] = useState(!department);
  const [editMode, setEditMode] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  useEffect(() => {
    apiRequest<{ department: DepartmentInfo }>("/api/departments/profile")
      .then((res) => setDepartment(res.department))
      .catch((err) => setFetchError(err instanceof Error ? err.message : "Failed to load department profile."))
      .finally(() => setLoading(false));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading) {
    return (
      <AppShell subtitle="Department" title="Loading...">
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots sizeClassName="h-5 w-5" />
        </Card>
      </AppShell>
    );
  }

  if (!department) {
    return (
      <AppShell subtitle="Department" title={fetchError ? "Error" : "No Department Profile"}>
        <Card className="py-16 text-center">
          {fetchError ? (
            <>
              <span className="material-symbols-outlined mb-4 block text-5xl text-error">cloud_off</span>
              <p className="text-error">{fetchError}</p>
            </>
          ) : (
            <p className="text-on-surface-variant">No department profile found. Contact the administrator.</p>
          )}
        </Card>
      </AppShell>
    );
  }

  const status = department.verification_status;

  if (status === "pending") {
    return (
      <AppShell subtitle="Awaiting verification" title="Department Registration">
        <Card className="mx-auto max-w-xl py-12 text-center">
          <div className="mb-6 inline-flex h-16 w-16 items-center justify-center rounded-full bg-[#ffdbd0]">
            <span className="material-symbols-outlined text-3xl text-secondary">hourglass_empty</span>
          </div>
          <h2 className="font-headline text-2xl text-on-surface">Awaiting Verification</h2>
          <p className="mx-auto mt-3 max-w-md text-on-surface-variant">
            Your department registration for <strong>{department.name}</strong> is pending municipality approval.
            Operational features unlock once approved.
          </p>
          <DeptDetails department={department} />
        </Card>
      </AppShell>
    );
  }

  if (status === "rejected") {
    return (
      <AppShell subtitle="Verification rejected" title="Department Registration">
        <DepartmentRejectedView
          department={department}
          editMode={editMode}
          onUpdated={(d) => setDepartment(d)}
          setEditMode={setEditMode}
        />
      </AppShell>
    );
  }

  return (
    <AppShell hidePageHeading subtitle="Responder operations" title={department.name}>
      <DepartmentDashboard department={department} />
    </AppShell>
  );
}

type ReportSummary = {
  id: string;
  title?: string;
  description?: string;
  status: string;
  category?: string;
  created_at?: string;
};

function DepartmentDashboard({ department }: { department: DepartmentInfo }) {
  const [reports, setReports] = useState<ReportSummary[]>([]);
  const [reportsLoading, setReportsLoading] = useState(true);

  useEffect(() => {
    apiRequest<{ reports: ReportSummary[] }>("/api/departments/reports")
      .then((res) => setReports(res.reports))
      .catch(() => {})
      .finally(() => setReportsLoading(false));
  }, []);

  const pendingCount = reports.filter((r) => r.status === "pending").length;
  const activeCount = reports.filter((r) => r.status === "accepted" || r.status === "responding").length;
  const resolvedCount = reports.filter((r) => r.status === "resolved").length;
  const recentReports = reports.slice(0, 4);

  const dashboardActions = [
    {
      title: "Incident Board",
      description: "Review routed incidents and dispatch activity.",
      icon: "assignment",
      to: "/department/reports",
      accent: "bg-[#f3d5c7] text-[#9d4f2c]",
    },
    {
      title: "Create Post",
      description: "Share advisories and public coordination updates.",
      icon: "edit_square",
      to: "/department/news-feed?compose=1",
      accent: "bg-[#ece7df] text-[#62554c]",
    },
    {
      title: "Notifications",
      description: "Track fresh alerts and time-sensitive changes.",
      icon: "notifications",
      to: "/notifications",
      accent: "bg-[#f6ecde] text-[#92653d]",
    },
    {
      title: "Community Feed",
      description: "Browse local announcements across agencies.",
      icon: "public",
      to: "/feed",
      accent: "bg-[#e6ebe4] text-[#48624d]",
    },
  ] as const;

  return (
    <div className="space-y-6">
      <section className="overflow-hidden rounded-[28px] border border-[#e7d8cd] bg-[#f7efe6] shadow-[0_28px_80px_rgba(101,66,40,0.12)]">
        <div className="relative isolate overflow-hidden rounded-[28px] bg-[linear-gradient(118deg,#50372c_0%,#7c5744_26%,#b76f47_62%,#d27d4d_100%)] px-6 py-8 text-white sm:px-8 sm:py-10">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_18%_18%,rgba(255,242,234,0.1),transparent_30%),linear-gradient(180deg,rgba(255,255,255,0.03),rgba(255,255,255,0))]" />
          <div className="absolute inset-y-0 right-0 w-[34%] bg-[linear-gradient(90deg,rgba(255,224,204,0.02),rgba(255,244,236,0.09))]" />
          <div className="absolute -right-6 top-0 h-full w-[28%] bg-[linear-gradient(180deg,rgba(255,228,213,0.06),rgba(255,255,255,0.012))] blur-3xl" />
          <div className="relative max-w-3xl">
            <p className="text-[11px] font-bold uppercase tracking-[0.32em] text-white/62">
              Department Dashboard
            </p>
            <h1 className="mt-3 font-headline text-4xl leading-none sm:text-5xl">{department.name}</h1>
            <p className="mt-3 max-w-2xl text-sm leading-6 text-white/74 sm:text-base">
              {reports.length > 0
                ? `${reports.length} total incident${reports.length === 1 ? "" : "s"} assigned — ${pendingCount} pending, ${activeCount} active, ${resolvedCount} resolved.`
                : "No incidents assigned yet. New reports will appear here."}
            </p>
          </div>
        </div>
      </section>

      <section className="grid gap-6 xl:grid-cols-[280px_minmax(0,1fr)]">
        <div className="space-y-6">
          <DepartmentProfileRail department={department} />
          <ReportStatsCard pending={pendingCount} active={activeCount} resolved={resolvedCount} total={reports.length} loading={reportsLoading} />
        </div>

        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2">
            {dashboardActions.map((action) => (
              <Link key={action.title} to={action.to}>
                <Card className="h-full rounded-[22px] border-[#eadfd5] bg-[#fffaf5] p-5 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-[0_20px_45px_rgba(112,78,50,0.12)]">
                  <div className={`inline-flex h-11 w-11 items-center justify-center rounded-2xl ${action.accent}`}>
                    <span className="material-symbols-outlined text-[20px]">{action.icon}</span>
                  </div>
                  <p className="mt-4 text-xs font-bold uppercase tracking-[0.24em] text-[#a28370]">Quick Access</p>
                  <h2 className="mt-2 text-lg font-semibold text-on-surface">{action.title}</h2>
                  <p className="mt-2 text-sm leading-6 text-on-surface-variant">{action.description}</p>
                </Card>
              </Link>
            ))}
          </div>

          <Card className="rounded-[24px] border-[#eadfd5] bg-[#fffaf5] p-6">
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-[11px] font-bold uppercase tracking-[0.3em] text-[#b36a47]">Recent Incidents</p>
                <h2 className="mt-2 font-headline text-2xl text-on-surface">Assigned reports</h2>
              </div>
              <Link to="/department/reports" className="text-[11px] font-bold uppercase tracking-[0.26em] text-[#c08564] hover:underline">
                View all
              </Link>
            </div>

            <div className="mt-6 space-y-5">
              {reportsLoading ? (
                <div className="py-8 text-center"><LoadingDots sizeClassName="h-4 w-4" /></div>
              ) : recentReports.length === 0 ? (
                <p className="py-4 text-center text-sm text-on-surface-variant italic">No incidents assigned yet.</p>
              ) : (
                recentReports.map((report, index) => (
                  <Link key={report.id} to={`/department/reports/${report.id}`} className={`block ${index < recentReports.length - 1 ? "border-b border-[#eee2d8] pb-5" : ""}`}>
                    <div className="flex items-start justify-between gap-4">
                      <div>
                        <h3 className="text-lg font-medium text-on-surface">{report.title || report.description || "Untitled report"}</h3>
                        <div className="mt-1 flex items-center gap-2">
                          <span className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-bold uppercase ${statusStyle(report.status)}`}>
                            {report.status}
                          </span>
                          {report.category && (
                            <span className="text-xs text-on-surface-variant capitalize">{report.category.replace(/_/g, " ")}</span>
                          )}
                        </div>
                      </div>
                      <span className="shrink-0 text-[11px] font-bold uppercase tracking-[0.24em] text-[#b7a193]">
                        {formatTimeAgo(report.created_at)}
                      </span>
                    </div>
                  </Link>
                ))
              )}
            </div>
          </Card>
        </div>
      </section>
    </div>
  );
}

function statusStyle(status: string): string {
  switch (status) {
    case "pending": return "bg-[#ffdbd0] text-[#89391e]";
    case "accepted": return "bg-[#d0e4f7] text-[#2c4a6a]";
    case "responding": return "bg-[#e5e5e0] text-[#52524f]";
    case "resolved": return "bg-[#d4edda] text-[#155724]";
    default: return "bg-[#eee] text-[#666]";
  }
}

function formatTimeAgo(iso?: string): string {
  if (!iso) return "";
  try {
    const diff = Date.now() - new Date(iso).getTime();
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) return "just now";
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  } catch { return ""; }
}

function ReportStatsCard({ pending, active, resolved, total, loading }: { pending: number; active: number; resolved: number; total: number; loading: boolean }) {
  if (loading) {
    return (
      <Card className="rounded-[24px] border-[#eadfd5] bg-[#f4efe6] p-5">
        <div className="py-4 text-center"><LoadingDots sizeClassName="h-4 w-4" /></div>
      </Card>
    );
  }
  const stats = [
    { label: "Pending", value: pending, color: "#D97757" },
    { label: "Active", value: active, color: "#3a4e6a" },
    { label: "Resolved", value: resolved, color: "#155724" },
    { label: "Total", value: total, color: "#62554c" },
  ];
  return (
    <Card className="rounded-[24px] border-[#eadfd5] bg-[#f4efe6] p-5">
      <div className="flex items-center gap-2">
        <span className="material-symbols-outlined text-[14px] text-[#7c8c64]">monitoring</span>
        <p className="text-[11px] font-bold uppercase tracking-[0.26em] text-[#7c8c64]">Incident Overview</p>
      </div>
      <div className="mt-5 space-y-4">
        {stats.map((item) => (
          <div key={item.label} className="rounded-[18px] border border-[#e7dbcf] bg-[#fffaf5] px-4 py-3">
            <div className="flex items-center justify-between gap-4">
              <span className="text-sm text-[#6f625b]">{item.label}</span>
              <span className="text-sm font-semibold" style={{ color: item.color }}>{item.value}</span>
            </div>
          </div>
        ))}
      </div>
    </Card>
  );
}

function DeptDetails({ department }: { department: DepartmentInfo }) {
  return (
    <div className="mt-6 space-y-4 rounded-[20px] border border-[#eadfd5] bg-[#fffaf5] p-5 text-left">
      <DetailRow label="Type" value={formatDepartmentType(department.type)} />
      {department.contact_number ? <DetailRow label="Contact" value={department.contact_number} /> : null}
      {department.address ? <DetailRow label="Address" value={department.address} /> : null}
      {department.area_of_responsibility ? (
        <DetailRow label="Area" value={department.area_of_responsibility} />
      ) : null}
    </div>
  );
}

function DepartmentProfileRail({ department }: { department: DepartmentInfo }) {
  const profileImage = department.profile_picture || department.profile_photo;
  const coverageChips = (department.area_of_responsibility || "District 1")
    .split(/[,\n/]+/)
    .map((value) => value.trim())
    .filter(Boolean)
    .slice(0, 2);

  return (
    <Card className="rounded-[30px] border-[#e7d5c7] bg-[#fffdfa] p-6 shadow-[0_18px_40px_rgba(132,94,59,0.08)]">
      <div className="flex items-start justify-between gap-3">
        <div className="flex flex-col gap-3">
          <p className="text-[10px] font-black uppercase tracking-[0.12em] text-[#5d3d2c]">
            Department Profile
          </p>

          <div className="flex items-center gap-3.5">
          {profileImage ? (
            <img
              alt={department.name}
              className="h-12 w-12 rounded-full object-cover shadow-[0_10px_20px_rgba(0,0,0,0.14)]"
              src={profileImage}
            />
          ) : (
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[linear-gradient(180deg,#55291b_0%,#241714_100%)] text-white shadow-[0_10px_20px_rgba(0,0,0,0.14)]">
              <span className="material-symbols-outlined text-[20px]">local_fire_department</span>
            </div>
          )}

            <div>
            <h2 className="mt-1 max-w-[7.5rem] font-headline text-[1.5rem] leading-[0.94] text-[#221814]">
              {department.name}
            </h2>
            </div>
          </div>
        </div>

        <span className="mt-1 inline-flex h-6 w-6 items-center justify-center rounded-full border border-[#eccdbb] text-[#bf7347]">
          <span className="material-symbols-outlined text-[12px]">target</span>
        </span>
      </div>

      <div className="mt-6 grid grid-cols-2 gap-5">
        <div>
          <p className="text-[10px] font-extrabold uppercase tracking-[0.08em] text-[#684836]">Registry ID</p>
          <p className="mt-1 text-[12px] font-semibold uppercase tracking-[0.16em] text-[#4f392d]">
            {formatRegistryDisplayId(department.id)}
          </p>
        </div>
        <div>
          <p className="text-[10px] font-extrabold uppercase tracking-[0.08em] text-[#684836]">Status</p>
          <p className="mt-1 text-[12px] font-bold uppercase tracking-[0.08em] text-[#9c4f28]">
            Active Agency
          </p>
        </div>
      </div>

      <div className="mt-7 divide-y divide-[#eee2d7]">
        <ProfileInfoRow
          icon="business"
          label="Agency Type"
          value={formatDepartmentType(department.type)}
        />
        <ProfileInfoRow
          icon="location_on"
          label="Official Address"
          value={department.address || "Agham Road, Bagong Pag-asa, Quezon City"}
        />
        <ProfileInfoRow
          icon="call"
          label="Contact Terminal"
          value={department.contact_number || "(02) 8426-0219"}
        />
        <ProfileCoverageRow chips={coverageChips} />
      </div>

      <div className="mt-10 border-t border-[#f3e8df] pt-5">
        <div className="flex items-center gap-2 text-[#b49a89]">
          <span className="material-symbols-outlined text-[14px]">badge</span>
          <p className="text-[8px] font-bold uppercase tracking-[0.26em]">BFP Registry Seal</p>
        </div>
      </div>
    </Card>
  );
}



function ProfileInfoRow({
  icon,
  label,
  value,
}: {
  icon: string;
  label: string;
  value: string;
}) {
  return (
    <div className="grid grid-cols-[22px_minmax(0,1fr)] gap-4 py-4 first:pt-0 last:pb-0">
      <span className="material-symbols-outlined mt-0.5 text-[15px] text-[#c8b3a3]">{icon}</span>
      <div>
        <p className="text-[10px] font-extrabold uppercase tracking-[0.08em] text-[#684836]">{label}</p>
        <p className="mt-2 text-[13px] leading-6 text-[#3f3028]">
          {value}
        </p>
      </div>
    </div>
  );
}

function ProfileCoverageRow({ chips }: { chips: string[] }) {
  return (
    <div className="grid grid-cols-[22px_minmax(0,1fr)] gap-4 py-4 first:pt-0 last:pb-0">
      <span className="material-symbols-outlined mt-0.5 text-[15px] text-[#c8b3a3]">globe</span>
      <div>
        <p className="text-[10px] font-extrabold uppercase tracking-[0.08em] text-[#684836]">Area Coverage</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {chips.map((chip) => (
            <span
              key={chip}
              className="rounded-full bg-[#f4e9df] px-2.5 py-1 text-[9px] font-bold uppercase tracking-[0.16em] text-[#7c604f]"
            >
              {chip}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <span className="text-sm text-[#8b7b71]">{label}</span>
      <span className="max-w-[60%] text-right text-sm font-medium text-on-surface">{value}</span>
    </div>
  );
}

function formatDepartmentType(value?: string | null) {
  if (!value) {
    return "Department";
  }

  return value
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}


function formatRegistryDisplayId(id: string) {
  const compact = id.replace(/-/g, "").toUpperCase();
  if (compact.length <= 9) {
    return compact || "8842-DRR-BFP";
  }

  return `${compact.slice(0, 4)}-${compact.slice(4, 7)}-${compact.slice(7, 10)}`;
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
        body: JSON.stringify({ name, contact_number: contactNumber, address, area_of_responsibility: area }),
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
      <div className="mb-6 text-center">
        <div className="mb-4 inline-flex h-16 w-16 items-center justify-center rounded-full bg-error-container/20">
          <span className="material-symbols-outlined text-3xl text-error">close</span>
        </div>
        <h2 className="font-headline text-2xl text-on-surface">Registration Rejected</h2>
      </div>

      {department.rejection_reason && (
        <div className="mb-6 rounded-md border border-error/15 bg-error-container/15 px-4 py-3 text-sm text-error">
          <span className="font-semibold">Reason:</span> {department.rejection_reason}
        </div>
      )}

      {editMode ? (
        <form className="space-y-4" onSubmit={handleResubmit}>
          {error && (
            <div className="rounded-md border border-error/20 bg-error-container/20 px-4 py-3 text-sm text-error">
              {error}
            </div>
          )}
          <div>
            <label className="aegis-label">Organization Name</label>
            <input
              className="aegis-input"
              onChange={(e) => setName(e.target.value)}
              placeholder="Organization name"
              type="text"
              value={name}
            />
          </div>
          <div>
            <label className="aegis-label">Contact Number</label>
            <input
              className="aegis-input"
              onChange={(e) => setContactNumber(e.target.value)}
              placeholder="Contact number"
              type="text"
              value={contactNumber}
            />
          </div>
          <div>
            <label className="aegis-label">Address</label>
            <input
              className="aegis-input"
              onChange={(e) => setAddress(e.target.value)}
              placeholder="Address"
              type="text"
              value={address}
            />
          </div>
          <div>
            <label className="aegis-label">Area of Responsibility</label>
            <input
              className="aegis-input"
              onChange={(e) => setArea(e.target.value)}
              placeholder="Area of responsibility"
              type="text"
              value={area}
            />
          </div>
          <div className="flex gap-3 pt-2">
            <Button disabled={loading} type="submit">
              {loading ? "Submitting..." : "Resubmit for Verification"}
            </Button>
            <Button onClick={() => setEditMode(false)} type="button" variant="outline">
              Cancel
            </Button>
          </div>
        </form>
      ) : (
        <div className="text-center">
          <p className="mb-6 text-sm text-on-surface-variant">
            Update your department details and resubmit for verification.
          </p>
          <Button onClick={() => setEditMode(true)} variant="secondary">
            <span className="material-symbols-outlined mr-2 text-[16px]">edit</span>
            Edit & Resubmit
          </Button>
        </div>
      )}
    </Card>
  );
}

// Municipality profile — admin profile with quick system stats and profile editing.

import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";

type Department = { id: string; name: string; type: string; verification_status: string };

export function MunicipalityProfilePage() {
  const user = useSessionStore((s) => s.user);
  const updateUser = useSessionStore((s) => s.updateUser);

  const [fullName, setFullName] = useState(user?.full_name ?? "");
  const [phone, setPhone] = useState(user?.phone ?? "");
  const [saving, setSaving] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // System stats
  const [totalDepts, setTotalDepts] = useState(0);
  const [pendingDepts, setPendingDepts] = useState(0);
  const [statsLoading, setStatsLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      apiRequest<{ departments: Department[] }>("/api/municipality/departments"),
      apiRequest<{ departments: Department[] }>("/api/municipality/departments/pending"),
    ])
      .then(([all, pending]) => {
        setTotalDepts(all.departments.length);
        setPendingDepts(pending.departments.length);
      })
      .catch(() => {})
      .finally(() => setStatsLoading(false));
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    setError(null);
    setSuccess(false);
    try {
      const res = await apiRequest<{ profile: { full_name: string; phone: string } }>(
        "/api/users/profile",
        { method: "PUT", body: JSON.stringify({ full_name: fullName, phone }) },
      );
      updateUser({ full_name: res.profile.full_name, phone: res.profile.phone });
      setSuccess(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update profile.");
    } finally {
      setSaving(false);
    }
  }

  if (!user) {
    return (
      <AppShell subtitle="Profile" title="Not signed in">
        <Card className="py-16 text-center text-on-surface-variant">No active session.</Card>
      </AppShell>
    );
  }

  const displayName = user.full_name || "Municipal Administrator";
  const handle = user.email?.split("@")[0] ?? "admin";

  return (
    <AppShell subtitle="Municipality administrator profile" title="Profile">
      <div className="space-y-8 max-w-3xl mx-auto">
        {/* Profile header */}
        <Card>
          <div className="flex items-center gap-4 mb-6 pb-6 border-b border-outline-variant/10">
            <div className="w-16 h-16 rounded-full bg-secondary-container flex items-center justify-center">
              <span className="material-symbols-outlined text-secondary text-3xl">shield_person</span>
            </div>
            <div>
              <h2 className="text-xl font-headline text-on-surface">{displayName}</h2>
              <p className="text-sm text-on-surface-variant">@{handle}</p>
              <span className="inline-block mt-1 rounded-md bg-secondary-container px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-widest text-[#89391e]">
                Municipality Admin
              </span>
            </div>
          </div>

          {/* Quick stats */}
          <div className="grid grid-cols-2 gap-4 mb-6">
            <div className="rounded-xl bg-surface-container p-4 text-center">
              <span className="material-symbols-outlined text-secondary mb-1 block">domain</span>
              <p className="text-2xl font-headline text-on-surface">{statsLoading ? "..." : totalDepts}</p>
              <p className="text-xs text-on-surface-variant">Registered Departments</p>
            </div>
            <div className="rounded-xl bg-surface-container p-4 text-center">
              <span className="material-symbols-outlined text-[#d97757] mb-1 block">pending_actions</span>
              <p className="text-2xl font-headline text-on-surface">{statsLoading ? "..." : pendingDepts}</p>
              <p className="text-xs text-on-surface-variant">Pending Verification</p>
            </div>
          </div>
        </Card>

        {/* Edit form */}
        <Card>
          <h3 className="text-sm font-semibold text-on-surface mb-4">Edit Profile</h3>

          <form className="space-y-5" onSubmit={handleSubmit}>
            {error && (
              <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error">
                {error}
              </div>
            )}
            {success && (
              <div className="rounded-md bg-[#d4edda] border border-[#155724]/20 px-4 py-3 text-sm text-[#155724]">
                Profile updated successfully.
              </div>
            )}

            <div>
              <label className="aegis-label" htmlFor="profileName">Full Name</label>
              <input
                id="profileName"
                type="text"
                className="aegis-input"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
              />
            </div>

            <div>
              <label className="aegis-label" htmlFor="profilePhone">Phone Number</label>
              <input
                id="profilePhone"
                type="tel"
                className="aegis-input"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
              />
            </div>

            <div>
              <label className="aegis-label" htmlFor="profileEmail">Email</label>
              <input
                id="profileEmail"
                type="email"
                className="aegis-input opacity-60"
                value={user.email ?? ""}
                disabled
              />
              <p className="text-xs text-on-surface-variant mt-1">Email cannot be changed.</p>
            </div>

            <div className="pt-2">
              <Button type="submit" disabled={saving}>
                {saving ? "Saving..." : "Save Changes"}
              </Button>
            </div>
          </form>
        </Card>
      </div>
    </AppShell>
  );
}

import { useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";

/**
 * Phase 1 — Profile page.
 * Aegis-styled form for editing full name and phone number.
 */

export function ProfilePage() {
  const user = useSessionStore((s) => s.user);
  const updateUser = useSessionStore((s) => s.updateUser);

  const [fullName, setFullName] = useState(user?.full_name ?? "");
  const [phone, setPhone] = useState(user?.phone ?? "");
  const [saving, setSaving] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true); setError(null); setSuccess(false);
    try {
      const res = await apiRequest<{ profile: { full_name: string; phone: string } }>(
        "/api/users/profile", { method: "PUT", body: JSON.stringify({ full_name: fullName, phone }) },
      );
      updateUser({ full_name: res.profile.full_name, phone: res.profile.phone });
      setSuccess(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update profile.");
    } finally { setSaving(false); }
  }

  if (!user) {
    return (
      <AppShell subtitle="Profile" title="Not signed in">
        <Card className="py-16 text-center text-on-surface-variant">No active session.</Card>
      </AppShell>
    );
  }

  return (
    <AppShell subtitle="Manage your profile" title="Profile">
      <Card className="mx-auto max-w-lg">
        {/* User meta */}
        <div className="mb-6 pb-6 border-b border-outline-variant/10">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-full bg-surface-container-highest flex items-center justify-center">
              <span className="material-symbols-outlined text-on-surface-variant text-2xl">account_circle</span>
            </div>
            <div>
              <p className="text-sm text-on-surface-variant">{user.email}</p>
              <span className="inline-block mt-1 rounded-md bg-secondary-container px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-widest text-[#89391e]">
                {user.role}
              </span>
            </div>
          </div>
        </div>

        <form className="space-y-5" onSubmit={handleSubmit}>
          {error && (
            <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error">{error}</div>
          )}
          {success && (
            <div className="rounded-md bg-[#d4edda] border border-[#155724]/20 px-4 py-3 text-sm text-[#155724]">
              Profile updated successfully.
            </div>
          )}

          <div>
            <label className="aegis-label" htmlFor="profileName">Full Name</label>
            <input id="profileName" type="text" className="aegis-input"
              value={fullName} onChange={(e) => setFullName(e.target.value)} />
          </div>

          <div>
            <label className="aegis-label" htmlFor="profilePhone">Phone Number</label>
            <input id="profilePhone" type="tel" className="aegis-input"
              value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>

          <div className="pt-2">
            <Button type="submit" disabled={saving}>
              {saving ? "Saving..." : "Save Changes"}
            </Button>
          </div>
        </form>
      </Card>
    </AppShell>
  );
}

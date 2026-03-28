import { useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";

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
    setSaving(true);
    setError(null);
    setSuccess(false);

    try {
      const res = await apiRequest<{ profile: { full_name: string; phone: string } }>(
        "/api/users/profile",
        {
          method: "PUT",
          body: JSON.stringify({ full_name: fullName, phone }),
        },
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
        <Card className="py-10 text-center text-muted-foreground">No active session.</Card>
      </AppShell>
    );
  }

  return (
    <AppShell subtitle="Manage your profile" title="Profile">
      <Card className="mx-auto max-w-lg">
        <div className="mb-4">
          <p className="text-sm text-muted-foreground">{user.email}</p>
          <span className="mt-1 inline-block rounded-full bg-accent/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-accent">
            {user.role}
          </span>
        </div>

        <form className="space-y-4" onSubmit={handleSubmit}>
          {error && (
            <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}
          {success && (
            <div className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-700">
              Profile updated successfully.
            </div>
          )}

          <div className="space-y-1.5">
            <label className="text-sm font-medium" htmlFor="profileName">
              Full name
            </label>
            <input
              id="profileName"
              type="text"
              className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-sm font-medium" htmlFor="profilePhone">
              Phone number
            </label>
            <input
              id="profilePhone"
              type="tel"
              className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
            />
          </div>

          <Button type="submit" disabled={saving}>
            {saving ? "Saving…" : "Save Changes"}
          </Button>
        </form>
      </Card>
    </AppShell>
  );
}

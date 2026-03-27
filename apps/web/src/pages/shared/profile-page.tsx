import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { useSessionStore } from "@/lib/auth/session-store";

export function ProfilePage() {
  const user = useSessionStore((state) => state.user);

  return (
    <AppShell subtitle="Shared authenticated route" title="Profile shell">
      <Card className="space-y-3">
        <p className="text-sm font-semibold uppercase tracking-[0.22em] text-accent">
          Authenticated placeholder
        </p>
        <p className="text-muted-foreground">
          {user
            ? `Signed in as ${user.email}. This route is intentionally shared across roles and will receive real profile forms in Phase 1.`
            : "No active session."}
        </p>
      </Card>
    </AppShell>
  );
}

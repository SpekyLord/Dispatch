import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";

/**
 * Phase 1 — Feed page placeholder.
 * Will contain verified-department announcements in Phase 2.
 */

export function FeedPage() {
  return (
    <AppShell subtitle="Public information" title="Community Feed">
      <Card className="py-16 text-center">
        <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">newspaper</span>
        <h3 className="font-headline text-xl text-on-surface mb-2">Coming in Phase 2</h3>
        <p className="text-sm text-on-surface-variant max-w-md mx-auto leading-relaxed">
          Verified-department announcements, safety alerts, situational reports, and
          community updates will appear here once department operations are live.
        </p>
      </Card>
    </AppShell>
  );
}

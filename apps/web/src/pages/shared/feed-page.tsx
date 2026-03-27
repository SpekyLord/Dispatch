import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";

export function FeedPage() {
  return (
    <AppShell subtitle="Public information foundation" title="Public feed placeholder">
      <Card>
        <p className="text-sm text-muted-foreground">
          Verified-department announcements, filters, and detail pages land in Phase 2. This view
          already owns the public route and visual treatment for that future work.
        </p>
      </Card>
    </AppShell>
  );
}

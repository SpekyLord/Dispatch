import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";

export function DepartmentHomePage() {
  return (
    <AppShell subtitle="Responder shell" title="Department operations foundation">
      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <h2 className="text-xl font-semibold">Phase 2 board ownership</h2>
          <p className="mt-3 text-sm text-muted-foreground">
            This shell will receive the category-filtered incident board, accept or decline actions,
            and inter-department visibility in the next product phase.
          </p>
        </Card>
        <Card>
          <h2 className="text-xl font-semibold">Phase 2 publishing ownership</h2>
          <p className="mt-3 text-sm text-muted-foreground">
            Verified-department posts, in-app notifications, and report status updates will attach
            to this area without changing the surrounding app frame.
          </p>
        </Card>
      </div>
    </AppShell>
  );
}

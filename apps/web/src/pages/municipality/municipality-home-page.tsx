import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";

export function MunicipalityHomePage() {
  return (
    <AppShell subtitle="Administrative shell" title="Municipality oversight foundation">
      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <h2 className="text-xl font-semibold">Verification workflow placeholder</h2>
          <p className="mt-3 text-sm text-muted-foreground">
            Department approval, rejection, and queue review will plug into this route in Phase 1.
          </p>
        </Card>
        <Card>
          <h2 className="text-xl font-semibold">Analytics and incident oversight placeholder</h2>
          <p className="mt-3 text-sm text-muted-foreground">
            System-wide report visibility and analytics land in Phases 2 and 3, but the shell and
            guard are already in place now.
          </p>
        </Card>
      </div>
    </AppShell>
  );
}

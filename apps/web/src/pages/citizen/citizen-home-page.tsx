import { AppShell } from "@/components/layout/app-shell";
import { LocationMap } from "@/components/maps/location-map";
import { Card } from "@/components/ui/card";

export function CitizenHomePage() {
  return (
    <AppShell subtitle="Citizen experience shell" title="Citizen dashboard foundation">
      <div className="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
        <Card className="space-y-3">
          <h2 className="text-xl font-semibold">Future citizen tasks</h2>
          <ul className="space-y-3 text-sm text-muted-foreground">
            <li>Report incident form with media, map pinning, and category selection.</li>
            <li>Report history and live status tracking.</li>
            <li>Read-only public feed browsing for official updates.</li>
          </ul>
        </Card>
        <LocationMap />
      </div>
    </AppShell>
  );
}

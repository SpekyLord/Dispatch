import { Card } from "@/components/ui/card";

export function RegisterPage() {
  return (
    <div className="mx-auto flex min-h-screen max-w-3xl items-center px-6 py-12">
      <Card className="w-full">
        <p className="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
          Registration placeholder
        </p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight">
          Citizen and department onboarding starts in Phase 1
        </h1>
        <p className="mt-3 text-muted-foreground">
          This placeholder route ensures the app shell, navigation, and auth route grouping are in
          place before the real registration forms arrive.
        </p>
      </Card>
    </div>
  );
}

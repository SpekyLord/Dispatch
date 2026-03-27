import { useNavigate } from "react-router-dom";

import { Card } from "@/components/ui/card";
import { useSessionStore, type AppRole } from "@/lib/auth/session-store";

const roles: AppRole[] = ["citizen", "department", "municipality"];

export function LoginPage() {
  const navigate = useNavigate();
  const signInAs = useSessionStore((state) => state.signInAs);

  return (
    <div className="mx-auto flex min-h-screen max-w-3xl items-center px-6 py-12">
      <Card className="w-full">
        <p className="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
          Phase 0 auth shell
        </p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight">Role-aware entry points</h1>
        <p className="mt-3 text-muted-foreground">
          Authentication is implemented in Phase 1. For Phase 0, these buttons simulate the role
          shells and verify the protected-route wiring.
        </p>
        <div className="mt-8 grid gap-3 md:grid-cols-3">
          {roles.map((role) => (
            <button
              key={role}
              className="rounded-[1rem] border border-border bg-white px-4 py-5 text-left transition-colors hover:bg-muted"
              onClick={() => {
                signInAs(role);
                navigate(`/${role}`);
              }}
              type="button"
            >
              <span className="text-xs font-semibold uppercase tracking-[0.22em] text-accent">
                Continue as
              </span>
              <p className="mt-3 text-lg font-semibold capitalize">{role}</p>
            </button>
          ))}
        </div>
      </Card>
    </div>
  );
}

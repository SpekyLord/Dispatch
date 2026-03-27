import { Link } from "react-router-dom";

import { Card } from "@/components/ui/card";

const roleLinks = [
  { label: "Citizen shell", to: "/citizen", summary: "Report intake, feed, and status views." },
  { label: "Department shell", to: "/department", summary: "Responder board, posts, and status actions." },
  { label: "Municipality shell", to: "/municipality", summary: "Verification, oversight, and analytics foundation." },
];

export function LandingPage() {
  return (
    <div className="mx-auto flex min-h-screen max-w-6xl flex-col justify-center px-6 py-12">
      <div className="grid gap-10 lg:grid-cols-[1.4fr_1fr]">
        <div className="space-y-6">
          <p className="text-sm font-semibold uppercase tracking-[0.28em] text-primary">
            Emergency platform foundation
          </p>
          <h1 className="max-w-3xl text-5xl font-semibold leading-tight tracking-tight">
            Dispatch now has its first working platform shell for web, mobile, API, and Supabase.
          </h1>
          <p className="max-w-2xl text-lg text-muted-foreground">
            Phase 0 is about durable structure: route guards, service wrappers, schema contracts,
            realtime hooks, and role-specific placeholders that later phases can fill without
            rewiring the project.
          </p>
          <div className="flex flex-wrap gap-3">
            <Link
              className="rounded-full bg-primary px-5 py-3 text-sm font-semibold text-primary-foreground"
              to="/auth/login"
            >
              Open auth shell
            </Link>
            <Link className="rounded-full border border-border px-5 py-3 text-sm font-semibold" to="/feed">
              View public feed shell
            </Link>
          </div>
        </div>
        <Card className="space-y-4 bg-white/95">
          <p className="text-sm font-semibold uppercase tracking-[0.24em] text-accent">
            Ready for Phase 1
          </p>
          {roleLinks.map((link) => (
            <Link
              key={link.to}
              className="block rounded-[1rem] border border-border/80 p-4 transition-transform hover:-translate-y-1 hover:bg-muted/70"
              to={link.to}
            >
              <h2 className="text-lg font-semibold">{link.label}</h2>
              <p className="mt-2 text-sm text-muted-foreground">{link.summary}</p>
            </Link>
          ))}
        </Card>
      </div>
    </div>
  );
}

import { Link } from "react-router-dom";

export function NotFoundPage() {
  return (
    <div className="mx-auto flex min-h-screen max-w-2xl flex-col items-center justify-center px-6 text-center">
      <p className="text-sm font-semibold uppercase tracking-[0.28em] text-primary">404</p>
      <h1 className="mt-3 text-4xl font-semibold tracking-tight">Route shell not found</h1>
      <p className="mt-3 text-muted-foreground">
        This app is still in its foundation phase, so unowned routes intentionally bounce back to
        the core shells.
      </p>
      <Link className="mt-6 rounded-full bg-primary px-5 py-3 text-sm font-semibold text-white" to="/">
        Return home
      </Link>
    </div>
  );
}

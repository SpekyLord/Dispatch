import { Link } from "react-router-dom";

/**
 * Phase 1 — 404 not-found page.
 * Aegis-styled minimal error page.
 */

export function NotFoundPage() {
  return (
    <div className="min-h-screen bg-surface flex flex-col items-center justify-center px-6 text-center">
      <span className="text-secondary text-xs font-bold tracking-[0.2em] uppercase mb-4">404</span>
      <h1 className="font-headline italic text-5xl text-on-surface mb-4">Route Not Found</h1>
      <p className="text-on-surface-variant max-w-md leading-relaxed mb-8">
        The page you are looking for does not exist or has been moved.
        Return to the main dashboard to continue.
      </p>
      <Link
        to="/"
        className="bg-gradient-to-br from-[#5f5e5c] to-[#535250] text-[#faf7f3] px-6 py-3 rounded-md text-sm font-semibold tracking-widest uppercase shadow-md hover:opacity-95 active:scale-[0.98] transition-all"
      >
        Return Home
      </Link>
    </div>
  );
}

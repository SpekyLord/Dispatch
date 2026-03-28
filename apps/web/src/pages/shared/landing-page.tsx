import { Link } from "react-router-dom";

/**
 * Phase 1 — Landing page.
 * Aegis-styled hero with serif headline, trust badges, and CTA buttons
 * for sign-in and registration.
 */

export function LandingPage() {
  return (
    <div className="min-h-screen bg-surface flex flex-col">
      {/* Top bar */}
      <header className="bg-surface-container w-full">
        <div className="flex justify-between items-center w-full px-12 py-6 max-w-[1440px] mx-auto">
          <span className="text-2xl font-headline italic text-on-surface">Dispatch</span>
          <nav className="hidden md:flex items-center gap-8">
            <Link to="/feed" className="text-on-surface-variant hover:text-on-surface transition-colors text-sm font-medium">Feed</Link>
            <Link to="/auth/login" className="text-on-surface-variant hover:text-on-surface transition-colors text-sm font-medium">Sign In</Link>
          </nav>
        </div>
      </header>

      {/* Hero */}
      <main className="flex-grow flex items-center justify-center px-6 py-20 relative overflow-hidden">
        <div className="absolute top-[-10%] left-[-5%] w-[40%] h-[60%] bg-surface-container opacity-40 blur-[120px] rounded-full pointer-events-none" />
        <div className="absolute bottom-[-10%] right-[-5%] w-[30%] h-[50%] bg-secondary-container opacity-20 blur-[100px] rounded-full pointer-events-none" />

        <div className="max-w-4xl w-full relative z-10 text-center">
          <span className="text-secondary text-xs font-bold tracking-[0.2em] uppercase mb-6 block">
            Emergency Response Platform
          </span>
          <h1 className="font-headline italic text-5xl md:text-7xl leading-tight text-on-surface mb-8">
            Cultivating resilience through community-driven response.
          </h1>
          <p className="max-w-2xl mx-auto text-lg text-on-surface-variant leading-relaxed mb-12">
            Dispatch connects citizens, departments, and municipalities in a unified
            crisis coordination platform. Report incidents, verify responders, and
            track real-time status updates.
          </p>

          <div className="flex flex-wrap justify-center gap-4 mb-16">
            <Link
              to="/auth/register"
              className="bg-gradient-to-br from-[#5f5e5c] to-[#535250] text-[#faf7f3] px-8 py-4 rounded-md text-sm font-semibold tracking-widest uppercase shadow-lg hover:opacity-95 active:scale-[0.98] transition-all"
            >
              Get Started
            </Link>
            <Link
              to="/auth/login"
              className="border border-outline-variant/30 bg-surface-container-lowest px-8 py-4 rounded-md text-sm font-semibold text-on-surface hover:bg-surface-container transition-all"
            >
              Sign In
            </Link>
          </div>

          {/* Trust badges */}
          <div className="flex flex-wrap justify-center gap-8">
            {[
              { icon: "groups", label: "Citizens" },
              { icon: "local_fire_department", label: "Departments" },
              { icon: "account_balance", label: "Municipality" },
            ].map((item) => (
              <div key={item.label} className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-surface-container-highest flex items-center justify-center">
                  <span className="material-symbols-outlined text-secondary scale-75">{item.icon}</span>
                </div>
                <span className="text-sm font-medium text-on-surface-variant">{item.label}</span>
              </div>
            ))}
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-surface-container border-t border-outline-variant/15">
        <div className="w-full px-12 py-8 flex flex-col md:flex-row justify-between items-center max-w-[1440px] mx-auto">
          <div className="font-headline italic text-on-surface mb-4 md:mb-0">Dispatch</div>
          <div className="text-[10px] uppercase tracking-widest text-on-surface-variant">
            &copy; 2026 Dispatch. Community-driven crisis management.
          </div>
        </div>
      </footer>
    </div>
  );
}

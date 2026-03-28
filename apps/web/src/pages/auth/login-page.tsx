import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";

import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";

/**
 * Phase 1 — Login page.
 * Split layout matching the Relief Registry auth screens:
 * left branding panel (serif headline + trust badges) + right form panel.
 */

type LoginResponse = {
  access_token: string;
  refresh_token: string;
  user: {
    id: string;
    email: string;
    role: "citizen" | "department" | "municipality";
    full_name?: string | null;
  };
  department?: {
    id: string;
    user_id: string;
    name: string;
    type: string;
    verification_status: "pending" | "approved" | "rejected";
    rejection_reason?: string | null;
    contact_number?: string | null;
    address?: string | null;
    area_of_responsibility?: string | null;
  } | null;
};

const roleHomePaths: Record<string, string> = {
  citizen: "/citizen",
  department: "/department",
  municipality: "/municipality",
};

export function LoginPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const setSession = useSessionStore((s) => s.setSession);

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const from = (location.state as { from?: string })?.from;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const res = await apiRequest<LoginResponse>("/api/auth/login", {
        method: "POST",
        body: JSON.stringify({ email, password }),
      });

      setSession({
        user: {
          id: res.user.id,
          email: res.user.email,
          role: res.user.role,
          full_name: res.user.full_name,
        },
        accessToken: res.access_token,
        refreshToken: res.refresh_token,
        department: res.department ?? null,
      });

      navigate(from ?? roleHomePaths[res.user.role] ?? "/");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex flex-col bg-surface">
      {/* Top bar */}
      <header className="bg-surface-container w-full">
        <div className="flex justify-between items-center w-full px-12 py-6 max-w-[1440px] mx-auto">
          <Link to="/" className="text-2xl font-headline italic text-on-surface">
            Dispatch
          </Link>
          <div className="flex items-center gap-4">
            <span className="material-symbols-outlined text-on-surface-variant cursor-pointer hover:text-on-surface transition-colors">
              help_outline
            </span>
            <span className="material-symbols-outlined text-on-surface-variant cursor-pointer hover:text-on-surface transition-colors">
              language
            </span>
          </div>
        </div>
      </header>

      {/* Main content */}
      <main className="flex-grow flex items-center justify-center py-20 px-6 relative overflow-hidden">
        {/* Background blurs */}
        <div className="absolute top-[-10%] left-[-5%] w-[40%] h-[60%] bg-surface-container opacity-40 blur-[120px] rounded-full pointer-events-none" />
        <div className="absolute bottom-[-10%] right-[-5%] w-[30%] h-[50%] bg-secondary-container opacity-20 blur-[100px] rounded-full pointer-events-none" />

        <div className="w-full max-w-4xl grid grid-cols-1 lg:grid-cols-12 gap-0 bg-surface-container-lowest shadow-spotlight rounded-lg overflow-hidden relative z-10">
          {/* Left branding side */}
          <div className="lg:col-span-5 bg-surface-container p-10 lg:p-14 flex flex-col justify-between border-r border-outline-variant/10">
            <div>
              <span className="text-secondary text-xs font-bold tracking-[0.2em] uppercase mb-4 block">
                Dispatch Protocol
              </span>
              <h1 className="text-4xl lg:text-5xl font-headline italic leading-tight text-on-surface mb-6">
                Ethos & <em>Ink.</em>
              </h1>
              <p className="text-on-surface-variant leading-relaxed">
                Accessing Dispatch ensures an organized and systematic approach to crisis
                coordination and institutional resilience.
              </p>
            </div>
            <div className="mt-12 lg:mt-0 space-y-6">
              <div className="flex items-center gap-4">
                <div className="w-10 h-10 rounded-full bg-surface-container-highest flex items-center justify-center">
                  <span className="material-symbols-outlined text-secondary scale-75">shield_with_heart</span>
                </div>
                <span className="text-sm font-medium text-on-surface-variant">Secure & Encrypted</span>
              </div>
              <div className="flex items-center gap-4">
                <div className="w-10 h-10 rounded-full bg-surface-container-highest flex items-center justify-center">
                  <span className="material-symbols-outlined text-secondary scale-75">verified_user</span>
                </div>
                <span className="text-sm font-medium text-on-surface-variant">Validated Institutions</span>
              </div>
            </div>
          </div>

          {/* Right form side */}
          <div className="lg:col-span-7 p-10 lg:p-14">
            <div className="mb-10 flex justify-between items-end">
              <div>
                <h2 className="text-2xl font-headline text-on-surface mb-2">Welcome Back</h2>
                <p className="text-sm text-on-surface-variant">Identify yourself to continue.</p>
              </div>
              <Link
                className="text-xs font-bold text-secondary tracking-wider uppercase underline underline-offset-4 hover:text-on-secondary-container transition-colors"
                to="/auth/register"
              >
                Register
              </Link>
            </div>

            <form className="space-y-6" onSubmit={handleSubmit}>
              {/* Error alert */}
              {error && (
                <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error">
                  <span className="font-semibold">Authentication Failed</span>
                  <p className="mt-0.5 text-xs">{error}</p>
                </div>
              )}

              <div>
                <label className="aegis-label" htmlFor="email">Institutional Email</label>
                <input
                  id="email"
                  type="email"
                  required
                  className="aegis-input"
                  placeholder="name@dispatch.org"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </div>

              <div>
                <div className="flex justify-between items-center mb-2">
                  <label className="aegis-label !mb-0" htmlFor="password">Security Credentials</label>
                  <button type="button" className="text-xs text-secondary hover:underline">
                    Forgot password?
                  </button>
                </div>
                <input
                  id="password"
                  type="password"
                  required
                  className="aegis-input"
                  placeholder="••••••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                />
              </div>

              <div className="pt-4">
                <button
                  type="submit"
                  disabled={loading}
                  className="w-full bg-gradient-to-br from-[#5f5e5c] to-[#535250] text-[#faf7f3] py-4 rounded-md font-medium text-sm tracking-widest uppercase hover:opacity-95 active:scale-[0.98] transition-all shadow-lg shadow-[#5f5e5c]/10 disabled:opacity-50"
                >
                  {loading ? "Signing in..." : "Sign In to Dispatch"}
                </button>
              </div>
            </form>

            <div className="mt-8 text-center">
              <p className="text-xs text-on-surface-variant uppercase tracking-wider mb-3">New practitioner?</p>
              <Link
                to="/auth/register"
                className="block w-full border border-outline-variant/30 rounded-md py-3 text-sm font-medium text-on-surface hover:bg-surface-container transition-all"
              >
                Register an Account
              </Link>
            </div>

            <p className="mt-6 text-center text-[10px] text-on-surface-variant leading-relaxed">
              By proceeding, you acknowledge this is a monitored system.
              <br />
              Authorized access only under Protocol 12-B.
            </p>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-surface-container border-t border-outline-variant/15">
        <div className="w-full px-12 py-8 flex flex-col md:flex-row justify-between items-center max-w-[1440px] mx-auto">
          <div className="font-headline italic text-on-surface mb-4 md:mb-0">Dispatch</div>
          <div className="text-[10px] font-body uppercase tracking-widest text-on-surface-variant text-center md:text-right">
            &copy; 2026 Dispatch. Community-driven crisis management.
          </div>
        </div>
      </footer>
    </div>
  );
}

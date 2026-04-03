import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";

import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";

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

type LoginRouteState = {
  from?: string;
  message?: string;
};

const roleHomePaths: Record<string, string> = {
  citizen: "/citizen",
  department: "/department",
  municipality: "/municipality",
};

const trustPoints = [
  "Live report routing and department response threads",
  "Offline mesh relay and survivor signal awareness",
  "Warm dispatch dashboard styling aligned with the feed experience",
] as const;

export function LoginPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const setSession = useSessionStore((state) => state.setSession);
  const routeState = (location.state as LoginRouteState | null) ?? {};

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const response = await apiRequest<LoginResponse>("/api/auth/login", {
        method: "POST",
        body: JSON.stringify({ email, password }),
      });

      setSession({
        user: {
          id: response.user.id,
          email: response.user.email,
          role: response.user.role,
          full_name: response.user.full_name,
        },
        accessToken: response.access_token,
        refreshToken: response.refresh_token,
        department: response.department ?? null,
      });

      navigate(routeState.from ?? roleHomePaths[response.user.role] ?? "/");
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Login failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(217,141,99,0.18),_transparent_32%),linear-gradient(180deg,#fcf7f2_0%,#f6eee6_100%)] text-on-surface">
      <div className="mx-auto flex min-h-screen w-full max-w-[1440px] flex-col px-6 py-6 lg:px-10">
        <header className="flex items-center justify-between rounded-[28px] border border-[#ecd8cf] bg-[#fff8f3]/90 px-6 py-4 shadow-[0_18px_40px_rgba(161,75,47,0.08)] backdrop-blur">
          <div>
            <Link className="font-headline text-3xl italic text-on-surface" to="/">
              Dispatch
            </Link>
            <p className="text-[11px] font-bold uppercase tracking-[0.24em] text-[#a14b2f]">
              Field Access Portal
            </p>
          </div>
          <div className="flex items-center gap-3">
            <Link
              className="rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-4 py-2 text-xs font-bold uppercase tracking-[0.2em] text-[#7b6b62] transition-colors hover:bg-[#f2e7de]"
              to="/feed"
            >
              View Feed
            </Link>
            <Link
              className="rounded-full bg-[#a14b2f] px-4 py-2 text-xs font-bold uppercase tracking-[0.2em] text-white transition-colors hover:bg-[#89391e]"
              to="/auth/register"
            >
              Register
            </Link>
          </div>
        </header>

        <main className="flex flex-1 items-center py-8 lg:py-10">
          <div className="grid w-full gap-6 lg:grid-cols-[1.1fr_0.9fr]">
            <section className="relative overflow-hidden rounded-[36px] border border-[#d7b19b] bg-[linear-gradient(145deg,#bf6e49_0%,#d98d63_42%,#f0d6c5_100%)] px-7 py-8 text-white shadow-[0_28px_60px_rgba(122,58,37,0.22)] lg:px-10 lg:py-10">
              <div className="absolute right-[-60px] top-[-40px] h-52 w-52 rounded-full bg-white/12 blur-2xl" />
              <div className="absolute bottom-[-70px] left-[-30px] h-56 w-56 rounded-full bg-[#5e768b]/25 blur-3xl" />
              <div className="relative max-w-xl">
                <div className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-2 text-[11px] font-bold uppercase tracking-[0.24em] text-white/90">
                  <span className="material-symbols-outlined text-[16px]">cell_tower</span>
                  Connected Response Network
                </div>
                <h1 className="mt-6 font-headline text-5xl italic leading-[0.92] lg:text-6xl">
                  Stay on the same page as the field feed.
                </h1>
                <p className="mt-5 max-w-lg text-base leading-7 text-white/86">
                  Sign in to coordinate reports, responder updates, mesh-aware maps, and survivor-locator workflows from the same warm command surface.
                </p>

                <div className="mt-8 grid gap-3">
                  {trustPoints.map((point) => (
                    <div
                      key={point}
                      className="flex items-start gap-3 rounded-[24px] border border-white/14 bg-[#fff8f3]/12 px-4 py-4 backdrop-blur-sm"
                    >
                      <span className="material-symbols-outlined mt-0.5 text-[18px] text-white/90">
                        task_alt
                      </span>
                      <p className="text-sm leading-6 text-white/88">{point}</p>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            <section className="rounded-[36px] border border-[#ecd8cf] bg-[#fff8f3] p-7 shadow-[0_26px_50px_rgba(104,79,67,0.12)] lg:p-9">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-[11px] font-bold uppercase tracking-[0.24em] text-[#a14b2f]">
                    Authentication
                  </p>
                  <h2 className="mt-3 font-headline text-4xl leading-none text-on-surface">
                    Welcome back
                  </h2>
                  <p className="mt-3 text-sm leading-6 text-on-surface-variant">
                    Enter your credentials to continue into Dispatch.
                  </p>
                </div>
                <div className="hidden rounded-[22px] border border-[#ecd8cf] bg-[#f7efe7] px-4 py-3 text-right sm:block">
                  <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-[#a14b2f]">
                    Sign-in route
                  </p>
                  <p className="mt-1 text-sm font-semibold text-on-surface">Auth / Login</p>
                </div>
              </div>

              {routeState.message ? (
                <div className="mt-6 rounded-[22px] border border-[#d7ccb9] bg-[#f7efe7] px-4 py-4 text-sm leading-6 text-[#6f625b]">
                  {routeState.message}
                </div>
              ) : null}

              {error ? (
                <div className="mt-6 rounded-[22px] border border-[#d8b7aa] bg-[#fff1e9] px-4 py-4 text-sm leading-6 text-[#89391e]">
                  <p className="font-semibold">Authentication failed</p>
                  <p className="mt-1">{error}</p>
                </div>
              ) : null}

              <form className="mt-6 space-y-5" onSubmit={handleSubmit}>
                <div>
                  <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="email">
                    Email address
                  </label>
                  <input
                    id="email"
                    type="email"
                    required
                    className="aegis-input"
                    placeholder="name@dispatch.org"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                  />
                </div>

                <div>
                  <div className="mb-2 flex items-center justify-between gap-4">
                    <label className="text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="password">
                      Security Credentials
                    </label>
                    <span className="text-[11px] font-bold uppercase tracking-[0.16em] text-[#a14b2f]">
                      Protected session
                    </span>
                  </div>
                  <input
                    id="password"
                    type="password"
                    required
                    className="aegis-input"
                    placeholder="••••••••••••"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                  />
                </div>

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full rounded-[18px] bg-[#a14b2f] px-5 py-4 text-sm font-bold uppercase tracking-[0.22em] text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {loading ? "Signing in..." : "Sign In to Dispatch"}
                </button>
              </form>

              <div className="mt-6 rounded-[24px] border border-[#ecd8cf] bg-[#f7efe7] px-5 py-4">
                <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                  Need an account?
                </p>
                <p className="mt-2 text-sm leading-6 text-[#6f625b]">
                  Register as a citizen or department and land directly in the same response-ready interface.
                </p>
                <Link
                  className="mt-4 inline-flex items-center gap-2 rounded-full border border-[#d7ccb9] bg-white px-4 py-2 text-xs font-bold uppercase tracking-[0.2em] text-[#6f625b] transition-colors hover:bg-[#fff8f3]"
                  to="/auth/register"
                >
                  Create account
                  <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
                </Link>
              </div>
            </section>
          </div>
        </main>
      </div>
    </div>
  );
}


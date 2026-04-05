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
      setError(
        caughtError instanceof Error ? caughtError.message : "Login failed.",
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(217,141,99,0.18),_transparent_32%),linear-gradient(180deg,#fcf7f2_0%,#f6eee6_100%)] text-on-surface">
      <div className="mx-auto flex min-h-screen w-full max-w-[1480px] flex-col px-6 py-6 lg:px-10">
        <header className="flex items-center justify-between rounded-[28px] border border-[#ecd8cf] bg-[#fff8f3]/90 px-6 py-4 shadow-[0_18px_40px_rgba(161,75,47,0.08)] backdrop-blur">
          <div>
            <Link
              className="font-headline text-3xl italic text-on-surface"
              to="/"
            >
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

        <main className="flex flex-1 items-center py-8 lg:py-12">
          <div className="w-full rounded-[42px] border border-[#ead8cc]/90 bg-[linear-gradient(180deg,rgba(255,248,243,0.78)_0%,rgba(247,239,231,0.97)_100%)] p-4 shadow-[0_32px_72px_rgba(120,82,58,0.12)] backdrop-blur-sm lg:p-5">
            <div className="grid gap-4 lg:grid-cols-[1.05fr_0.95fr]">
              <section className="relative overflow-hidden rounded-[34px] border border-[#d7b19b] bg-[linear-gradient(150deg,#b76745_0%,#d48760_34%,#edc7ae_100%)] px-6 py-6 text-white shadow-[0_28px_60px_rgba(122,58,37,0.18)] lg:min-h-[640px] lg:px-8 lg:py-8">
                <div className="absolute inset-y-0 left-0 w-1/2 bg-[radial-gradient(circle_at_left,rgba(112,56,35,0.28),transparent_70%)]" />
                <div className="absolute right-[-70px] top-[-40px] h-52 w-52 rounded-full bg-white/12 blur-2xl" />
                <div className="absolute bottom-[-90px] left-[18%] h-56 w-56 rounded-full bg-[#fff4ea]/12 blur-3xl" />

                <div className="relative flex h-full flex-col">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div className="inline-flex items-center gap-2 rounded-full border border-white/18 bg-white/10 px-4 py-2 text-[11px] font-bold uppercase tracking-[0.24em] text-white/92">
                      <span className="material-symbols-outlined text-[16px]">
                        cell_tower
                      </span>
                      Connected Response Network
                    </div>

                    <Link
                      className="inline-flex items-center gap-2 rounded-full border border-white/16 bg-white/10 px-4 py-2 text-[11px] font-bold uppercase tracking-[0.2em] text-white/88 transition-colors hover:bg-white/16"
                      to="/"
                    >
                      Back to website
                      <span className="material-symbols-outlined text-[15px]">
                        arrow_outward
                      </span>
                    </Link>
                  </div>

                  <div className="mt-10 max-w-[31rem]">
                    <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-white/72">
                      Warm sign-in surface
                    </p>
                    <h1 className="mt-4 font-headline text-[3.4rem] italic leading-[0.9] text-white lg:text-[4.25rem]">
                      Stay on the same page as the field feed.
                    </h1>
                    <p className="mt-5 max-w-lg text-base leading-7 text-white/84">
                      Sign in to coordinate reports, responder updates,
                      mesh-aware maps, and survivor-locator workflows from the
                      same warm command surface.
                    </p>
                  </div>

                  <div className="mt-8 rounded-[28px] border border-white/16 bg-[linear-gradient(180deg,rgba(255,248,243,0.16)_0%,rgba(255,248,243,0.06)_100%)] p-4 backdrop-blur-sm">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded-full border border-white/16 bg-white/10 px-3 py-1 text-[10px] font-bold uppercase tracking-[0.2em] text-white/80">
                        Route sync
                      </span>
                      <span className="rounded-full border border-white/16 bg-white/10 px-3 py-1 text-[10px] font-bold uppercase tracking-[0.2em] text-white/80">
                        Mesh aware
                      </span>
                      <span className="rounded-full border border-white/16 bg-white/10 px-3 py-1 text-[10px] font-bold uppercase tracking-[0.2em] text-white/80">
                        Survivor locator
                      </span>
                    </div>

                    <div className="mt-4 space-y-3">
                      {trustPoints.map((point, index) => (
                        <div
                          key={point}
                          className="flex items-center gap-3 rounded-[22px] border border-white/14 bg-[#fff8f3]/10 px-4 py-3.5"
                        >
                          <span className="flex h-8 w-8 items-center justify-center rounded-full bg-white/14 text-sm font-bold text-white/90">
                            {index + 1}
                          </span>
                          <p className="text-sm leading-6 text-white/88">
                            {point}
                          </p>
                        </div>
                      ))}
                    </div>
                  </div>

                  <div className="mt-6 flex gap-2">
                    <span className="h-1.5 w-12 rounded-full bg-white/90" />
                    <span className="h-1.5 w-12 rounded-full bg-white/34" />
                    <span className="h-1.5 w-12 rounded-full bg-white/20" />
                  </div>
                </div>
              </section>

              <section className="rounded-[34px] border border-[#ecd8cf] bg-[#fffaf6] p-5 shadow-[0_24px_48px_rgba(104,79,67,0.1)] lg:p-7">
                <div className="flex h-full flex-col">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <p className="text-[11px] font-bold uppercase tracking-[0.24em] text-[#a14b2f]">
                        Authentication
                      </p>
                      <h2 className="mt-3 font-headline text-[2.9rem] leading-[0.92] text-on-surface">
                        Welcome back
                      </h2>
                      <p className="mt-3 max-w-md text-sm leading-6 text-on-surface-variant">
                        Enter your credentials to continue into Dispatch.
                      </p>
                    </div>

                    <div className="hidden rounded-[22px] border border-[#ecd8cf] bg-[#f7efe7] px-4 py-3 text-right sm:block">
                      <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-[#a14b2f]">
                        Sign-in route
                      </p>
                      <p className="mt-1 text-sm font-semibold text-on-surface">
                        Auth / Login
                      </p>
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

                  <form className="mt-6" onSubmit={handleSubmit}>
                    <div className="rounded-[28px] border border-[#efe2d7] bg-[linear-gradient(180deg,#faf4ee_0%,#f6eee6_100%)] p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.55)] sm:p-5">
                      <div className="space-y-5">
                        <div>
                          <label
                            className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]"
                            htmlFor="email"
                          >
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
                            <label
                              className="text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]"
                              htmlFor="password"
                            >
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
                            placeholder="************"
                            value={password}
                            onChange={(event) =>
                              setPassword(event.target.value)
                            }
                          />
                        </div>

                        <button
                          type="submit"
                          disabled={loading}
                          className="w-full rounded-[18px] bg-[#a14b2f] px-5 py-4 text-sm font-bold uppercase tracking-[0.22em] text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-60"
                        >
                          {loading ? "Signing in..." : "Sign In to Dispatch"}
                        </button>
                      </div>
                    </div>
                  </form>

                  <div className="mt-5 rounded-[24px] border border-[#ecd8cf] bg-[#f7efe7] px-5 py-4 sm:px-6">
                    <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                      Need an account?
                    </p>
                    <p className="mt-2 max-w-lg text-sm leading-6 text-[#6f625b]">
                      Register as a citizen or department and land directly in
                      the same response-ready interface.
                    </p>
                    <Link
                      className="mt-4 inline-flex items-center gap-2 rounded-full border border-[#d7ccb9] bg-white px-4 py-2 text-xs font-bold uppercase tracking-[0.2em] text-[#6f625b] transition-colors hover:bg-[#fff8f3]"
                      to="/auth/register"
                    >
                      Create account
                      <span className="material-symbols-outlined text-[16px]">
                        arrow_forward
                      </span>
                    </Link>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

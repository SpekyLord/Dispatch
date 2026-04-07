import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";

import { DispatchLogo } from "@/components/branding/dispatch-logo";
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

const loginHighlights = [
  "Resume live report routing and department response threads",
  "Keep mesh-aware status and field coordination in the same session",
  "Return to the same warm response surface after sign-in",
] as const;

const provisioningSlides = [
  {
    alt: "Rescue responders digging through landslide debris.",
    src: "/auth-slides/bicol-front.jpg",
  },
  {
    alt: "Flood response team guiding evacuees through deep water.",
    src: "/auth-slides/typhoon-rai.jpg",
  },
  {
    alt: "Firefighters coordinating suppression efforts from an elevated platform.",
    src: "/auth-slides/fire-response.jpg",
  },
  {
    alt: "Medical responders preparing equipment from an emergency vehicle.",
    src: "/auth-slides/medical-response.jpg",
  },
] as const;

function createDeterministicRandom(seed: number) {
  let current = seed >>> 0;

  return () => {
    current = (current * 1664525 + 1013904223) >>> 0;
    return current / 4294967295;
  };
}

function buildStarShadow(
  seed: number,
  count: number,
  color: string,
  maxX = 2200,
  maxY = 1400,
  loopHeight = 1600,
) {
  const random = createDeterministicRandom(seed);

  return Array.from({ length: count }, () => {
    const x = Math.round(random() * maxX);
    const y = Math.round(random() * maxY);
    return [`${x}px ${y}px ${color}`, `${x}px ${y + loopHeight}px ${color}`];
  })
    .flat()
    .join(", ");
}

const loginStarLayers = [
  {
    animation: "loginStarsFloatA 52s linear infinite",
    blur: "drop-shadow(0 0 5px rgba(214,120,60,0.28))",
    opacity: 0.96,
    shadow: buildStarShadow(11, 220, "rgba(201,109,52,0.98)"),
    size: 1.8,
  },
  {
    animation: "loginStarsFloatB 78s linear infinite",
    blur: "drop-shadow(0 0 7px rgba(230,146,86,0.24))",
    opacity: 0.82,
    shadow: buildStarShadow(27, 140, "rgba(229,144,78,0.86)"),
    size: 2.6,
  },
  {
    animation: "loginStarsFloatC 108s linear infinite",
    blur: "drop-shadow(0 0 11px rgba(238,171,116,0.24))",
    opacity: 0.72,
    shadow: buildStarShadow(53, 88, "rgba(244,184,130,0.8)"),
    size: 3.6,
  },
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
  const [activeSlide, setActiveSlide] = useState(0);

  useEffect(() => {
    const interval = window.setInterval(() => {
      setActiveSlide((current) => (current + 1) % provisioningSlides.length);
    }, 12000);

    return () => window.clearInterval(interval);
  }, []);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const response = await apiRequest<LoginResponse>("/api/auth/login", {
        method: "POST",
        body: JSON.stringify({ email, password }),
      });

      const destination = routeState.from ?? roleHomePaths[response.user.role];
      if (!destination) {
        setError("Login succeeded but your account role is not recognised. Please try again.");
        return;
      }

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

      navigate(destination);
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : "Login failed.",
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="relative isolate min-h-screen overflow-hidden bg-[linear-gradient(180deg,#ffffff_0%,#fdf8f3_36%,#f7e6d8_68%,#efc3a6_100%)] text-on-surface">
      <style>{`
        @keyframes loginStarsFloatA {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }

        @keyframes loginStarsFloatB {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }

        @keyframes loginStarsFloatC {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }
      `}</style>

      <div aria-hidden="true" className="pointer-events-none absolute inset-0">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,rgba(255,255,255,0.72)_0%,rgba(255,255,255,0.14)_24%,transparent_52%)]" />
        {loginStarLayers.map((layer) => (
          <div
            key={layer.animation}
            className="absolute left-0 top-0"
            style={{
              animation: layer.animation,
              boxShadow: layer.shadow,
              filter: layer.blur,
              height: `${layer.size}px`,
              opacity: layer.opacity,
              width: `${layer.size}px`,
              willChange: "transform",
            }}
          />
        ))}
      </div>

      <div className="relative z-10 flex min-h-screen flex-col">
        <header className="bg-surface-container/90 backdrop-blur-sm">
          <div className="mx-auto flex w-full max-w-[1440px] items-center justify-between px-12 py-5">
            <Link to="/" aria-label="Dispatch home">
              <DispatchLogo className="h-12 w-[82px]" />
            </Link>
            <nav className="hidden items-center gap-8 md:flex">
              <Link
                to="/auth/login"
                className="text-sm font-medium text-on-surface-variant transition-colors hover:text-on-surface"
              >
                Sign In
              </Link>
            </nav>
          </div>
        </header>

        <main className="mx-auto flex w-full max-w-[1380px] flex-1 items-center px-5 py-6 lg:px-8 lg:py-8">
          <div className="w-full rounded-[38px] border border-[#ead9cd] bg-[linear-gradient(180deg,#fbf5ef_0%,#f7efe7_100%)] p-3.5 shadow-[0_14px_28px_-12px_rgba(56,36,27,0.28),0_18px_38px_-20px_rgba(56,36,27,0.24)] lg:p-3.5">
            <div className="grid gap-3.5 lg:grid-cols-[0.9fr_1.02fr]">
              <section className="relative overflow-hidden rounded-[28px] border border-white/10 bg-[#6d4639] px-5 py-5 text-white shadow-[0_22px_48px_rgba(49,27,19,0.18)] lg:min-h-[600px] lg:px-6 lg:py-6">
                <div className="absolute inset-0">
                  {provisioningSlides.map((slide, index) => (
                    <div
                      key={slide.src}
                      aria-hidden={index !== activeSlide}
                      className={`absolute inset-0 transition-opacity duration-[1800ms] ease-out ${
                        index === activeSlide ? "opacity-100" : "opacity-0"
                      }`}
                    >
                      <img
                        alt={slide.alt}
                        className="h-full w-full object-cover"
                        src={slide.src}
                      />
                    </div>
                  ))}
                </div>
                <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(45,28,22,0.28)_0%,rgba(57,34,27,0.48)_34%,rgba(49,29,23,0.74)_100%)]" />
                <div className="absolute inset-y-0 left-0 w-[58%] bg-[radial-gradient(circle_at_left,rgba(255,255,255,0.14),transparent_74%)]" />
                <div className="absolute right-[-80px] top-[-50px] h-56 w-56 rounded-full bg-white/10 blur-3xl" />
                <div className="absolute bottom-[-110px] left-[10%] h-60 w-60 rounded-full bg-[#f5d7c6]/12 blur-3xl" />

                <div className="relative flex h-full flex-col">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <DispatchLogo className="h-14 w-[92px] rounded-[20px]" />
                      <p className="mt-1 text-[9px] font-bold uppercase tracking-[0.24em] text-white/62">
                        Field Access Portal
                      </p>
                    </div>

                    <Link
                      className="inline-flex items-center gap-2 rounded-full border border-white/14 bg-white/10 px-3.5 py-1.5 text-[10px] font-bold uppercase tracking-[0.18em] text-white/82 transition-colors hover:bg-white/16"
                      to="/"
                    >
                      Back to website
                      <span className="material-symbols-outlined text-[15px]">
                        arrow_outward
                      </span>
                    </Link>
                  </div>

                  <div className="mt-auto pb-1 pt-10">
                    <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-white/70">
                      Provisioning flow
                    </p>
                    <h1 className="mt-3 max-w-[15ch] font-headline text-[2.5rem] italic leading-[0.92] text-white lg:text-[3.2rem]">
                      Return to the same response-ready surface.
                    </h1>
                    <p className="mt-3.5 max-w-[25rem] text-[14px] leading-6 text-white/82">
                      Sign in to continue report tracking, responder coordination,
                      live advisories, and the warm feed experience from one
                      unified access point.
                    </p>

                    <div className="mt-5 space-y-2.5">
                      {loginHighlights.map((highlight, index) => (
                        <div
                          key={highlight}
                          className="rounded-[20px] border border-white/20 bg-[linear-gradient(135deg,rgba(34,20,17,0.52)_0%,rgba(88,52,40,0.38)_46%,rgba(255,255,255,0.08)_100%)] px-3.5 py-3 shadow-[0_14px_30px_-18px_rgba(0,0,0,0.75)] backdrop-blur-md"
                        >
                          <div className="flex items-center gap-3">
                            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/24 bg-white/14 text-[10px] font-bold tracking-[0.18em] text-white/88">
                              {String(index + 1).padStart(2, "0")}
                            </div>
                            <p className="text-[13px] font-medium leading-[1.35rem] text-white/92">
                              {highlight}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>

                    <div className="mt-6 flex gap-2">
                      {provisioningSlides.map((slide, index) => (
                        <span
                          key={slide.src}
                          className={`h-1.5 w-12 rounded-full transition-all duration-500 ${
                            index === activeSlide
                              ? "bg-white/88"
                              : "bg-white/24"
                          }`}
                        />
                      ))}
                    </div>
                  </div>
                </div>
              </section>

              <section className="rounded-[28px] bg-[linear-gradient(180deg,#fbf5ef_0%,#f7efe7_100%)] p-[18px] text-[#2f221d] lg:p-5">
                <div className="flex h-full flex-col justify-center">
                  <div className="min-w-0">
                    <h2 className="text-center font-sans text-[2.1rem] font-semibold leading-[0.96] text-[#2f221d]">
                      Welcome back
                    </h2>
                    <p className="mt-2 text-center text-[13px] leading-5 text-[#6f625b]">
                      Enter your credentials to continue into Dispatch.
                    </p>
                  </div>

                  {routeState.message ? (
                    <div className="mt-4 rounded-[22px] border border-[#d7ccb9] bg-[#f7efe7] px-4 py-4 text-sm leading-6 text-[#6f625b]">
                      {routeState.message}
                    </div>
                  ) : null}

                  {error ? (
                    <div className="mt-4 rounded-[22px] border border-[#d08e77] bg-[#6d4134]/55 px-4 py-4 text-sm leading-6 text-[#ffe4d7]">
                      {error}
                    </div>
                  ) : null}

                  <form className="mt-4 space-y-3.5" onSubmit={handleSubmit}>
                    <div className="rounded-[22px] bg-[#f8f1ea] p-3.5 shadow-[0_10px_22px_-12px_rgba(120,78,58,0.18),0_5px_5px_0_#00000010] sm:p-4">
                      <div className="flex items-start gap-3">
                        <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-[#ead9cd] bg-[#fffdf9] text-[#a14b2f]">
                          <span className="material-symbols-outlined text-[18px]">
                            lock_person
                          </span>
                        </div>
                        <div>
                          <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                            Authentication
                          </p>
                          <p className="mt-1 text-sm leading-6 text-[#6f625b]">
                            Restore your secured session and step back into the
                            response workspace.
                          </p>
                        </div>
                      </div>

                      <div className="mt-3.5 space-y-3.5">
                        <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3.5">
                          <div className="flex items-center gap-3">
                            <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                              mail
                            </span>
                            <input
                              id="email"
                              type="email"
                              required
                              className="w-full border-0 bg-transparent p-0 text-[15px] text-[#2f221d] outline-none placeholder:text-[#c4aea3]"
                              placeholder="Email address"
                              value={email}
                              onChange={(event) => setEmail(event.target.value)}
                            />
                          </div>
                        </div>

                        <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3.5">
                          <div className="flex items-center gap-3">
                            <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                              lock
                            </span>
                            <input
                              id="password"
                              type="password"
                              required
                              className="w-full border-0 bg-transparent p-0 text-[15px] text-[#2f221d] outline-none placeholder:text-[#c4aea3]"
                              placeholder="Password"
                              value={password}
                              onChange={(event) =>
                                setPassword(event.target.value)
                              }
                            />
                          </div>
                        </div>
                      </div>
                    </div>

                    <button
                      type="submit"
                      disabled={loading}
                      className="w-full rounded-[18px] bg-[#a14b2f] px-5 py-4 text-sm font-bold uppercase tracking-[0.22em] text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      {loading ? "Signing in..." : "Sign In to Dispatch"}
                    </button>
                  </form>

                  <div className="mt-3.5 rounded-[22px] border border-[#ead9cd] bg-[linear-gradient(180deg,#f9f2eb_0%,#f6ede5_100%)] px-4 py-4 shadow-[0_10px_22px_-12px_rgba(120,78,58,0.18),0_5px_5px_0_#00000010] sm:px-5">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                      <div className="flex items-start gap-3">
                        <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-[#ead9cd] bg-[#fffdf9] text-[#a14b2f]">
                          <span className="material-symbols-outlined text-[18px]">
                            person_add
                          </span>
                        </div>
                        <div className="min-w-0">
                          <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                            Need an account?
                          </p>
                          <p className="mt-1 max-w-[28rem] text-sm leading-6 text-[#6f625b]">
                            Register as a citizen or department and step into
                            the same response-ready workspace.
                          </p>
                        </div>
                      </div>

                      <Link
                        className="inline-flex min-w-[176px] items-center justify-center gap-2 self-start whitespace-nowrap rounded-full border border-[#d7ccb9] bg-white px-5 py-2 text-xs font-bold uppercase tracking-[0.2em] text-[#6f625b] transition-colors hover:bg-[#fff8f3] sm:self-center"
                        to="/auth/register"
                      >
                        Create account
                        <span className="material-symbols-outlined text-[16px]">
                          arrow_forward
                        </span>
                      </Link>
                    </div>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </main>

        <footer className="bg-surface-container/90 backdrop-blur-sm">
          <div className="mx-auto flex w-full max-w-[1440px] items-center justify-between px-12 py-4 text-[11px] tracking-[0.22em] text-on-surface-variant">
            <DispatchLogo className="h-10 w-[68px]" />
            <span>© 2026 Dispatch. Community-driven crisis management.</span>
          </div>
        </footer>
      </div>
    </div>
  );
}

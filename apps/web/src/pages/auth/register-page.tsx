import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { DispatchLogo } from "@/components/branding/dispatch-logo";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore, type AppRole } from "@/lib/auth/session-store";

const DEPARTMENT_TYPES = [
  { value: "fire", label: "Fire (BFP)" },
  { value: "police", label: "Police (PNP)" },
  { value: "medical", label: "Medical" },
  { value: "disaster", label: "Disaster Response (MDRRMO)" },
  { value: "rescue", label: "Rescue" },
  { value: "other", label: "Other" },
];

type RegisterResponse = {
  user: {
    id: string;
    email: string;
    role: AppRole;
    full_name?: string | null;
  };
  department?: {
    id: string;
    user_id: string;
    name: string;
    type: string;
    verification_status: "pending" | "approved" | "rejected";
  } | null;
  access_token?: string | null;
  refresh_token?: string | null;
};

const roleCardMeta = {
  citizen: {
    icon: "person",
    description:
      "Create a citizen account for reporting, feed access, and mesh-aware monitoring.",
  },
  department: {
    icon: "apartment",
    description:
      "Include organization, type, contact, address, and area coverage for verification.",
  },
} as const;

const provisioningContent = {
  citizen: {
    body: "Open a resident-facing Dispatch account for reporting incidents, following live advisories, and staying connected to nearby response updates from the same warm feed surface.",
    highlights: [
      "Submit emergency reports and track their status from one account",
      "Follow advisories, alerts, and feed updates after sign-in",
      "Stay connected to mesh-aware status and responder activity",
    ],
    title: "Start citizen access with fast reporting and feed visibility.",
  },
  department: {
    body: "Create a responder-facing account for verified agencies so Dispatch can route incidents, carry agency details into review, and unlock operational tools after approval.",
    highlights: [
      "Send organization details forward for municipality verification",
      "Unlock dispatch, feed, and responder coordination after approval",
      "Keep agency contact, coverage, and routing context in one flow",
    ],
    title: "Prepare department access with verification-ready response context.",
  },
} as const;

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

const registerStarLayers = [
  {
    animation: "registerStarsFloatA 52s linear infinite",
    blur: "drop-shadow(0 0 5px rgba(214,120,60,0.28))",
    opacity: 0.96,
    shadow: buildStarShadow(11, 220, "rgba(201,109,52,0.98)"),
    size: 1.8,
  },
  {
    animation: "registerStarsFloatB 78s linear infinite",
    blur: "drop-shadow(0 0 7px rgba(230,146,86,0.24))",
    opacity: 0.82,
    shadow: buildStarShadow(27, 140, "rgba(229,144,78,0.86)"),
    size: 2.6,
  },
  {
    animation: "registerStarsFloatC 108s linear infinite",
    blur: "drop-shadow(0 0 11px rgba(238,171,116,0.24))",
    opacity: 0.72,
    shadow: buildStarShadow(53, 88, "rgba(244,184,130,0.8)"),
    size: 3.6,
  },
] as const;

export function RegisterPage() {
  const navigate = useNavigate();
  const setSession = useSessionStore((state) => state.setSession);

  const [role, setRole] = useState<"citizen" | "department">("citizen");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [orgName, setOrgName] = useState("");
  const [deptType, setDeptType] = useState("fire");
  const [contactNumber, setContactNumber] = useState("");
  const [address, setAddress] = useState("");
  const [areaOfResponsibility, setAreaOfResponsibility] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [activeSlide, setActiveSlide] = useState(0);
  const activeProvisioning = provisioningContent[role];

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
      const body: Record<string, string> = {
        email,
        password,
        role,
        full_name: fullName,
      };

      if (role === "department") {
        body.organization_name = orgName;
        body.department_type = deptType;
        body.contact_number = contactNumber;
        body.address = address;
        body.area_of_responsibility = areaOfResponsibility;
      }

      const response = await apiRequest<RegisterResponse>(
        "/api/auth/register",
        {
          method: "POST",
          body: JSON.stringify(body),
        },
      );

      if (response.access_token) {
        setSession({
          user: {
            id: response.user.id,
            email: response.user.email,
            role: response.user.role,
            full_name: response.user.full_name,
          },
          accessToken: response.access_token,
          refreshToken: response.refresh_token ?? undefined,
          department: response.department ?? null,
        });
        navigate(role === "department" ? "/department" : "/citizen");
        return;
      }

      navigate("/auth/login", {
        state: {
          message:
            "Registration successful. Check your email if confirmation is required, then sign in to continue.",
        },
      });
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Registration failed.",
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="relative isolate min-h-screen overflow-hidden bg-[linear-gradient(180deg,#ffffff_0%,#fdf8f3_36%,#f7e6d8_68%,#efc3a6_100%)] text-on-surface">
      <style>{`
        @keyframes registerStarsFloatA {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }

        @keyframes registerStarsFloatB {
          from {
            transform: translate3d(0, 0, 0);
          }
          to {
            transform: translate3d(0, -1600px, 0);
          }
        }

        @keyframes registerStarsFloatC {
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
        {registerStarLayers.map((layer) => (
          <div
            key={layer.animation}
            className="absolute left-0 top-0"
            style={{
              animation: layer.animation,
              boxShadow: layer.shadow,
              filter: layer.blur,
              height: `${layer.size}px`,
              opacity: layer.opacity,
              willChange: "transform",
              width: `${layer.size}px`,
            }}
          />
        ))}
      </div>

      <div className="relative z-10 flex min-h-screen flex-col">
        <header className="bg-surface-container/90 backdrop-blur-sm">
          <div className="mx-auto flex w-full max-w-[1440px] items-center justify-between px-12 py-5">
            <Link to="/" aria-label="Dispatch home">
              <DispatchLogo className="h-12 w-12" />
            </Link>
            <nav className="hidden items-center gap-8 md:flex">
              <Link
                to="/feed"
                className="text-sm font-medium text-on-surface-variant transition-colors hover:text-on-surface"
              >
                Feed
              </Link>
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
                      <DispatchLogo className="h-14 w-14 rounded-[20px]" />
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
                      {activeProvisioning.title}
                    </h1>
                    <p className="mt-3.5 max-w-[25rem] text-[14px] leading-6 text-white/82">
                      {activeProvisioning.body}
                    </p>

                    <div className="mt-5 space-y-2.5">
                      {activeProvisioning.highlights.map((highlight, index) => (
                        <div
                          key={highlight}
                          className="group rounded-[20px] border border-white/20 bg-[linear-gradient(135deg,rgba(34,20,17,0.52)_0%,rgba(88,52,40,0.38)_46%,rgba(255,255,255,0.08)_100%)] px-3.5 py-3 shadow-[0_14px_30px_-18px_rgba(0,0,0,0.75)] backdrop-blur-md"
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
                <div className="flex h-full flex-col">
                  <div className="min-w-0">
                    <h2 className="text-center font-sans text-[2.1rem] font-semibold leading-[0.96] text-[#2f221d]">
                      Create an account
                    </h2>
                    <p className="mt-2 text-center text-[13px] leading-5 text-[#6f625b]">
                      Already have an account?{" "}
                      <Link
                        className="font-semibold text-[#a14b2f] underline-offset-4 transition-colors hover:text-[#89391e] hover:underline"
                        to="/auth/login"
                      >
                        Log in
                      </Link>
                    </p>
                  </div>

                  {error ? (
                    <div className="mt-6 rounded-[22px] border border-[#d08e77] bg-[#6d4134]/55 px-4 py-4 text-sm leading-6 text-[#ffe4d7]">
                      {error}
                    </div>
                  ) : null}

                  <form className="mt-4 space-y-3.5" onSubmit={handleSubmit}>
                    <div className="rounded-[22px] bg-[#f8f1ea] p-3.5 shadow-[0_10px_22px_-12px_rgba(120,78,58,0.18),0_5px_5px_0_#00000010] sm:p-4">
                      <div className="flex items-start gap-3">
                        <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-[#ead9cd] bg-[#fffdf9] text-[#a14b2f]">
                          <span className="material-symbols-outlined text-[18px]">
                            dashboard_customize
                          </span>
                        </div>
                        <div>
                          <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                            Choose access
                          </p>
                          <p className="mt-1 text-sm leading-6 text-[#6f625b]">
                            Pick the route that matches how this account will
                            enter Dispatch.
                          </p>
                        </div>
                      </div>

                      <div className="mt-3.5 grid gap-3 sm:grid-cols-2">
                        {(["citizen", "department"] as const).map((value) => {
                          const isActive = role === value;

                          return (
                            <button
                              key={value}
                              type="button"
                              aria-pressed={isActive}
                              onClick={() => setRole(value)}
                              className={`rounded-[20px] border px-4 py-4 text-left transition-all ${
                                isActive
                                  ? "border-[#dca488] bg-[#fff8f3] text-[#2f221d] shadow-[0_10px_22px_-12px_rgba(0,0,0,0.45),0_5px_5px_0_#00000026]"
                                  : "border-[#ead9cd] bg-[#fffdf9] text-[#6f625b] hover:bg-[#fcf6f1]"
                              }`}
                            >
                              <div className="flex items-center gap-3">
                                <div
                                  className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl ${
                                    isActive
                                      ? "bg-[#f4dfd3] text-[#a14b2f]"
                                      : "bg-[#f4ebe4] text-[#b26848]"
                                  }`}
                                >
                                  <span className="material-symbols-outlined text-[18px]">
                                    {roleCardMeta[value].icon}
                                  </span>
                                </div>

                                <div className="min-w-0">
                                  <p
                                    className={`text-[11px] font-bold uppercase tracking-[0.22em] ${
                                      isActive
                                        ? "text-[#a14b2f]"
                                        : "text-[#b26848]"
                                    }`}
                                  >
                                    {value}
                                  </p>
                                </div>
                              </div>
                            </button>
                          );
                        })}
                      </div>
                    </div>

                    {role === "citizen" ? (
                      <div className="rounded-[24px] bg-[#f8f1ea] p-4 shadow-[0_10px_22px_-12px_rgba(120,78,58,0.18),0_5px_5px_0_#00000010] sm:p-5">
                        <div className="flex items-start gap-3">
                          <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-[#ead9cd] bg-[#fffdf9] text-[#a14b2f]">
                            <span className="material-symbols-outlined text-[18px]">
                              badge
                            </span>
                          </div>
                          <div>
                            <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                              Identity details
                            </p>
                            <p className="mt-1 text-sm leading-6 text-[#6f625b]">
                              Enter the core credentials used to provision
                              access.
                            </p>
                          </div>
                        </div>

                        <div className="mt-4 grid gap-4 md:grid-cols-2">
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]">
                            <div className="flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                person
                              </span>
                              <input
                                id="fullName"
                                type="text"
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="Full name"
                                value={fullName}
                                onChange={(event) =>
                                  setFullName(event.target.value)
                                }
                              />
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]">
                            <div className="flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                mail
                              </span>
                              <input
                                id="regEmail"
                                type="email"
                                required
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="Email address"
                                value={email}
                                onChange={(event) =>
                                  setEmail(event.target.value)
                                }
                              />
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)] md:col-span-2">
                            <div className="flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                lock
                              </span>
                              <input
                                id="regPassword"
                                type="password"
                                required
                                minLength={6}
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="Password"
                                value={password}
                                onChange={(event) =>
                                  setPassword(event.target.value)
                                }
                              />
                              <span className="material-symbols-outlined text-[18px] text-[#c4b1a4]">
                                visibility_off
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>
                    ) : null}

                    {role === "department" ? (
                      <div className="rounded-[24px] bg-[#f8f1ea] p-4 shadow-[0_10px_22px_-12px_rgba(120,78,58,0.18),0_5px_5px_0_#00000010] sm:p-5">
                        <div className="flex items-start gap-3">
                          <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-[#ead9cd] bg-[#fffdf9] text-[#a14b2f]">
                            <span className="material-symbols-outlined text-[18px]">
                              domain_verification
                            </span>
                          </div>
                          <div>
                            <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                              Department verification
                            </p>
                            <p className="mt-1 text-sm leading-6 text-[#6f625b]">
                              These details travel with the registration request
                              so municipality review has the full operating
                              context upfront.
                            </p>
                          </div>
                        </div>

                        <div className="mt-4 grid gap-4 md:grid-cols-2">
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)] md:col-span-2">
                            <label
                              className="block text-[11px] font-bold uppercase tracking-[0.2em] text-[#8f7568]"
                              htmlFor="orgName"
                            >
                              Organization name
                            </label>
                            <div className="mt-2 flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                apartment
                              </span>
                              <input
                                id="orgName"
                                type="text"
                                required
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="Bureau of Emergency Management"
                                value={orgName}
                                onChange={(event) =>
                                  setOrgName(event.target.value)
                                }
                              />
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]">
                            <div className="flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                mail
                              </span>
                              <input
                                id="regEmail"
                                type="email"
                                required
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="Email address"
                                value={email}
                                onChange={(event) =>
                                  setEmail(event.target.value)
                                }
                              />
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]">
                            <div className="flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                call
                              </span>
                              <input
                                id="contactNumber"
                                type="tel"
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="Contact number"
                                value={contactNumber}
                                onChange={(event) =>
                                  setContactNumber(event.target.value)
                                }
                              />
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)] md:col-span-2">
                            <div className="flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                lock
                              </span>
                              <input
                                id="regPassword"
                                type="password"
                                required
                                minLength={6}
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="Password"
                                value={password}
                                onChange={(event) =>
                                  setPassword(event.target.value)
                                }
                              />
                              <span className="material-symbols-outlined text-[18px] text-[#c4b1a4]">
                                visibility_off
                              </span>
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]">
                            <label
                              className="block text-[11px] font-bold uppercase tracking-[0.2em] text-[#8f7568]"
                              htmlFor="deptType"
                            >
                              Department type
                            </label>
                            <div className="mt-2 flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                category
                              </span>
                              <select
                                id="deptType"
                                className="min-w-0 flex-1 cursor-pointer appearance-none border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none"
                                value={deptType}
                                onChange={(event) =>
                                  setDeptType(event.target.value)
                                }
                              >
                                {DEPARTMENT_TYPES.map((departmentType) => (
                                  <option
                                    key={departmentType.value}
                                    value={departmentType.value}
                                    className="bg-[#fffdf9] text-[#2f221d]"
                                  >
                                    {departmentType.label}
                                  </option>
                                ))}
                              </select>
                              <span className="material-symbols-outlined text-[18px] text-[#c4b1a4]">
                                expand_more
                              </span>
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)]">
                            <label
                              className="block text-[11px] font-bold uppercase tracking-[0.2em] text-[#8f7568]"
                              htmlFor="areaResp"
                            >
                              Area of responsibility
                            </label>
                            <div className="mt-2 flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                public
                              </span>
                              <input
                                id="areaResp"
                                type="text"
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="North district"
                                value={areaOfResponsibility}
                                onChange={(event) =>
                                  setAreaOfResponsibility(event.target.value)
                                }
                              />
                            </div>
                          </div>
                          <div className="rounded-[20px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)] md:col-span-2">
                            <label
                              className="block text-[11px] font-bold uppercase tracking-[0.2em] text-[#8f7568]"
                              htmlFor="deptAddress"
                            >
                              Address
                            </label>
                            <div className="mt-2 flex items-center gap-3">
                              <span className="material-symbols-outlined text-[18px] text-[#b26848]">
                                location_on
                              </span>
                              <input
                                id="deptAddress"
                                type="text"
                                className="min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-[#2f221d] outline-none placeholder:text-[#b9a79b]"
                                placeholder="742 Field Command Avenue"
                                value={address}
                                onChange={(event) =>
                                  setAddress(event.target.value)
                                }
                              />
                            </div>
                          </div>
                        </div>
                      </div>
                    ) : null}

                    <div className="rounded-[24px] bg-[#f8f1ea] p-4 shadow-[0_10px_22px_-12px_rgba(120,78,58,0.18),0_5px_5px_0_#00000010] sm:p-5">
                      <button
                        type="submit"
                        disabled={loading}
                        className="inline-flex w-full items-center justify-center rounded-[10px] bg-[#a14b2f] px-5 py-3.5 text-sm font-medium text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-60"
                      >
                        {loading ? "Creating account..." : "Create account"}
                      </button>

                      {role === "citizen" ? (
                        <>
                          <div className="mt-4 flex items-center gap-3">
                            <span className="h-px flex-1 bg-[#e3d3c6]" />
                            <span className="text-[11px] text-[#9a8578]">
                              Or register with
                            </span>
                            <span className="h-px flex-1 bg-[#e3d3c6]" />
                          </div>

                          <div className="mt-4 grid gap-3 sm:grid-cols-2">
                            <button
                              type="button"
                              className="inline-flex items-center justify-center gap-3 rounded-[10px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 text-sm text-[#4a3a33] transition-colors hover:bg-[#fcf6f1]"
                            >
                              <span className="text-base font-semibold text-[#ea4335]">
                                G
                              </span>
                              Google
                            </button>
                            <button
                              type="button"
                              className="inline-flex items-center justify-center gap-3 rounded-[10px] border border-[#ead9cd] bg-[#fffdf9] px-4 py-3 text-sm text-[#4a3a33] transition-colors hover:bg-[#fcf6f1]"
                            >
                              <span className="material-symbols-outlined text-[18px] text-[#4a3a33]">
                                apple
                              </span>
                              Apple
                            </button>
                          </div>
                        </>
                      ) : null}
                    </div>
                  </form>
                </div>
              </section>
            </div>
          </div>
        </main>

        <footer className="border-t border-outline-variant/15 bg-surface-container/90 backdrop-blur-sm">
          <div className="mx-auto flex w-full max-w-[1440px] flex-col items-center justify-between px-12 py-7 md:flex-row">
            <div className="mb-4 md:mb-0">
              <DispatchLogo className="h-10 w-10" />
            </div>
            <div className="text-[10px] uppercase tracking-widest text-on-surface-variant">
              &copy; 2026 Dispatch. Community-driven crisis management.
            </div>
          </div>
        </footer>
      </div>
    </div>
  );
}

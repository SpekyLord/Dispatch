import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";

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

const registrationHighlights = [
  "Citizen intake with full report visibility",
  "Department onboarding with verification-aware routing",
  "Shared feed, mesh, and notification surfaces after sign-in",
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

      const response = await apiRequest<RegisterResponse>("/api/auth/register", {
        method: "POST",
        body: JSON.stringify(body),
      });

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
      setError(caughtError instanceof Error ? caughtError.message : "Registration failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top_right,_rgba(217,141,99,0.18),_transparent_30%),linear-gradient(180deg,#fcf7f2_0%,#f6eee6_100%)] text-on-surface">
      <div className="mx-auto flex min-h-screen w-full max-w-[1440px] flex-col px-6 py-6 lg:px-10">
        <header className="flex items-center justify-between rounded-[28px] border border-[#ecd8cf] bg-[#fff8f3]/90 px-6 py-4 shadow-[0_18px_40px_rgba(161,75,47,0.08)] backdrop-blur">
          <div>
            <Link className="font-headline text-3xl italic text-on-surface" to="/">
              Dispatch
            </Link>
            <p className="text-[11px] font-bold uppercase tracking-[0.24em] text-[#a14b2f]">
              Account Provisioning
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
              to="/auth/login"
            >
              Log in
            </Link>
          </div>
        </header>

        <main className="flex flex-1 items-center py-8 lg:py-10">
          <div className="grid w-full gap-6 lg:grid-cols-[1.08fr_0.92fr]">
            <section className="relative overflow-hidden rounded-[36px] border border-[#d7b19b] bg-[linear-gradient(155deg,#fff2ea_0%,#f0d7c7_36%,#cf825b_100%)] px-7 py-8 text-on-surface shadow-[0_28px_60px_rgba(122,58,37,0.15)] lg:px-10 lg:py-10">
              <div className="absolute right-[-70px] top-[-50px] h-56 w-56 rounded-full bg-white/35 blur-3xl" />
              <div className="absolute bottom-[-80px] left-[-20px] h-60 w-60 rounded-full bg-[#d98d63]/22 blur-3xl" />
              <div className="relative max-w-xl">
                <div className="inline-flex items-center gap-2 rounded-full border border-[#d7b19b] bg-white/55 px-4 py-2 text-[11px] font-bold uppercase tracking-[0.24em] text-[#a14b2f]">
                  <span className="material-symbols-outlined text-[16px]">verified_user</span>
                  Guided Onboarding
                </div>
                <h1 className="mt-6 font-headline text-5xl italic leading-[0.92] lg:text-6xl">
                  Build your Dispatch access with the same warm feed language.
                </h1>
                <p className="mt-5 max-w-lg text-base leading-7 text-[#5f4f46]">
                  Create a citizen or department account, carry the full verification context forward, and keep auth connected to the same backend response contract used by mobile.
                </p>

                <div className="mt-8 grid gap-3">
                  {registrationHighlights.map((highlight) => (
                    <div
                      key={highlight}
                      className="rounded-[24px] border border-[#d7b19b] bg-white/55 px-4 py-4 backdrop-blur-sm"
                    >
                      <p className="text-sm leading-6 text-[#5f4f46]">{highlight}</p>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            <section className="rounded-[36px] border border-[#ecd8cf] bg-[#fff8f3] p-7 shadow-[0_26px_50px_rgba(104,79,67,0.12)] lg:p-9">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-[11px] font-bold uppercase tracking-[0.24em] text-[#a14b2f]">
                    Registration
                  </p>
                  <h2 className="mt-3 font-headline text-4xl leading-none text-on-surface">
                    Create account
                  </h2>
                  <p className="mt-3 text-sm leading-6 text-on-surface-variant">
                    Choose your role and fill the fields required for access routing.
                  </p>
                </div>
                <div className="hidden rounded-[22px] border border-[#ecd8cf] bg-[#f7efe7] px-4 py-3 text-right sm:block">
                  <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-[#a14b2f]">
                    Roles
                  </p>
                  <p className="mt-1 text-sm font-semibold text-on-surface">Citizen / Department</p>
                </div>
              </div>

              {error ? (
                <div className="mt-6 rounded-[22px] border border-[#d8b7aa] bg-[#fff1e9] px-4 py-4 text-sm leading-6 text-[#89391e]">
                  {error}
                </div>
              ) : null}

              <form className="mt-6 space-y-6" onSubmit={handleSubmit}>
                <div>
                  <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]">
                    Account type
                  </label>
                  <div className="grid gap-3 sm:grid-cols-2">
                    {(["citizen", "department"] as const).map((value) => (
                      <button
                        key={value}
                        type="button"
                        onClick={() => setRole(value)}
                        className={`rounded-[20px] border px-4 py-4 text-left transition-colors ${
                          role === value
                            ? "border-[#a14b2f] bg-[#fff1e9] text-on-surface"
                            : "border-[#ecd8cf] bg-[#f7efe7] text-[#6f625b] hover:bg-[#f2e7de]"
                        }`}
                      >
                        <p className="text-[11px] font-bold uppercase tracking-[0.2em] text-[#a14b2f]">
                          {value}
                        </p>
                        <p className="mt-2 text-sm leading-6">
                          {value === "department"
                            ? "Include organization, type, contact, address, and area coverage for verification."
                            : "Create a citizen account for reporting, feed access, and mesh-aware monitoring."}
                        </p>
                      </button>
                    ))}
                  </div>
                </div>

                <div className="grid gap-5 md:grid-cols-2">
                  <div>
                    <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="fullName">
                      Full name
                    </label>
                    <input
                      id="fullName"
                      type="text"
                      className="aegis-input"
                      placeholder="Juan Dela Cruz"
                      value={fullName}
                      onChange={(event) => setFullName(event.target.value)}
                    />
                  </div>
                  <div>
                    <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="regEmail">
                      Email address
                    </label>
                    <input
                      id="regEmail"
                      type="email"
                      required
                      className="aegis-input"
                      placeholder="j.doe@dispatch.org"
                      value={email}
                      onChange={(event) => setEmail(event.target.value)}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="regPassword">
                      Password
                    </label>
                    <input
                      id="regPassword"
                      type="password"
                      required
                      minLength={6}
                      className="aegis-input"
                      placeholder="••••••••••••"
                      value={password}
                      onChange={(event) => setPassword(event.target.value)}
                    />
                  </div>
                </div>

                {role === "department" ? (
                  <div className="rounded-[28px] border border-[#ecd8cf] bg-[#f7efe7] p-5">
                    <div className="mb-4">
                      <p className="text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f]">
                        Department verification fields
                      </p>
                      <p className="mt-2 text-sm leading-6 text-[#6f625b]">
                        These values are sent directly to the backend so municipality review can approve or reject the department profile without missing context.
                      </p>
                    </div>
                    <div className="grid gap-5 md:grid-cols-2">
                      <div>
                        <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="orgName">
                          Organization name
                        </label>
                        <input
                          id="orgName"
                          type="text"
                          required
                          className="aegis-input"
                          placeholder="Bureau of Emergency Management"
                          value={orgName}
                          onChange={(event) => setOrgName(event.target.value)}
                        />
                      </div>
                      <div>
                        <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="deptType">
                          Department type
                        </label>
                        <select
                          id="deptType"
                          className="aegis-input cursor-pointer"
                          value={deptType}
                          onChange={(event) => setDeptType(event.target.value)}
                        >
                          {DEPARTMENT_TYPES.map((departmentType) => (
                            <option key={departmentType.value} value={departmentType.value}>
                              {departmentType.label}
                            </option>
                          ))}
                        </select>
                      </div>
                      <div>
                        <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="contactNumber">
                          Contact number
                        </label>
                        <input
                          id="contactNumber"
                          type="tel"
                          className="aegis-input"
                          placeholder="+63 9XX XXX XXXX"
                          value={contactNumber}
                          onChange={(event) => setContactNumber(event.target.value)}
                        />
                      </div>
                      <div>
                        <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="areaResp">
                          Area of responsibility
                        </label>
                        <input
                          id="areaResp"
                          type="text"
                          className="aegis-input"
                          placeholder="North district"
                          value={areaOfResponsibility}
                          onChange={(event) => setAreaOfResponsibility(event.target.value)}
                        />
                      </div>
                      <div className="md:col-span-2">
                        <label className="mb-2 block text-[11px] font-bold uppercase tracking-[0.2em] text-[#7b6b62]" htmlFor="deptAddress">
                          Address
                        </label>
                        <input
                          id="deptAddress"
                          type="text"
                          className="aegis-input"
                          placeholder="742 Field Command Avenue"
                          value={address}
                          onChange={(event) => setAddress(event.target.value)}
                        />
                      </div>
                    </div>
                  </div>
                ) : null}

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full rounded-[18px] bg-[#a14b2f] px-5 py-4 text-sm font-bold uppercase tracking-[0.22em] text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {loading ? "Creating account..." : "Create Account"}
                </button>
              </form>
            </section>
          </div>
        </main>
      </div>
    </div>
  );
}


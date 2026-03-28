import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { apiRequest } from "@/lib/api/client";
import { useSessionStore, type AppRole } from "@/lib/auth/session-store";

/**
 * Phase 1 — Register page.
 * Split layout (left branding + right form) matching Relief Registry design.
 * Citizen / Department role toggle with conditional department fields.
 */

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
};

export function RegisterPage() {
  const navigate = useNavigate();
  const setSession = useSessionStore((s) => s.setSession);

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

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const body: Record<string, string> = { email, password, role, full_name: fullName };
      if (role === "department") {
        body.organization_name = orgName;
        body.department_type = deptType;
        body.contact_number = contactNumber;
        body.address = address;
        body.area_of_responsibility = areaOfResponsibility;
      }

      const res = await apiRequest<RegisterResponse>("/api/auth/register", {
        method: "POST",
        body: JSON.stringify(body),
      });

      if (res.access_token) {
        setSession({
          user: { id: res.user.id, email: res.user.email, role: res.user.role, full_name: res.user.full_name },
          accessToken: res.access_token,
          department: res.department ?? null,
        });
        navigate(role === "department" ? "/department" : "/citizen");
      } else {
        navigate("/auth/login", {
          state: { message: "Registration successful! Please check your email to confirm, then sign in." },
        });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Registration failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex flex-col bg-surface">
      {/* Top bar */}
      <header className="bg-surface-container w-full">
        <div className="flex justify-between items-center w-full px-12 py-6 max-w-[1440px] mx-auto">
          <Link to="/" className="text-2xl font-headline italic text-on-surface">Dispatch</Link>
          <nav className="hidden md:flex items-center gap-6">
            <Link to="/" className="text-on-surface-variant hover:text-on-surface transition-colors text-sm font-medium">Home</Link>
            <Link to="/feed" className="text-on-surface-variant hover:text-on-surface transition-colors text-sm font-medium">Feed</Link>
          </nav>
        </div>
      </header>

      <main className="flex-grow flex items-center justify-center py-20 px-6 relative overflow-hidden">
        <div className="absolute top-[-10%] left-[-5%] w-[40%] h-[60%] bg-surface-container opacity-40 blur-[120px] rounded-full pointer-events-none" />
        <div className="absolute bottom-[-10%] right-[-5%] w-[30%] h-[50%] bg-secondary-container opacity-20 blur-[100px] rounded-full pointer-events-none" />

        <div className="w-full max-w-4xl grid grid-cols-1 lg:grid-cols-12 gap-0 bg-surface-container-lowest shadow-spotlight rounded-lg overflow-hidden relative z-10">
          {/* Left branding panel */}
          <div className="lg:col-span-5 bg-surface-container p-10 lg:p-14 flex flex-col justify-between border-r border-outline-variant/10">
            <div>
              <span className="text-secondary text-xs font-bold tracking-[0.2em] uppercase mb-4 block">
                Dispatch Protocol
              </span>
              <h1 className="text-4xl lg:text-5xl font-headline italic leading-tight text-on-surface mb-6">
                Cultivating resilience through institutional foresight.
              </h1>
              <p className="text-on-surface-variant leading-relaxed">
                Join Dispatch to coordinate crisis response with precision and community-driven integrity.
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

          {/* Right form panel */}
          <div className="lg:col-span-7 p-10 lg:p-14">
            <div className="mb-10 flex justify-between items-end">
              <div>
                <h2 className="text-2xl font-headline text-on-surface mb-2">Create Account</h2>
                <p className="text-sm text-on-surface-variant">Enter your details to register.</p>
              </div>
              <Link
                className="text-xs font-bold text-secondary tracking-wider uppercase underline underline-offset-4 hover:text-on-secondary-container transition-colors"
                to="/auth/login"
              >
                Log In
              </Link>
            </div>

            <form className="space-y-6" onSubmit={handleSubmit}>
              {error && (
                <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error">
                  {error}
                </div>
              )}

              {/* Role toggle */}
              <div className="mb-2">
                <label className="aegis-label">Identity Specification</label>
                <div className="flex p-1 bg-surface-container rounded-md w-full sm:w-max">
                  {(["citizen", "department"] as const).map((r) => (
                    <button
                      key={r}
                      type="button"
                      onClick={() => setRole(r)}
                      className={`px-6 py-2 rounded text-sm font-medium cursor-pointer transition-all text-center capitalize ${
                        role === r
                          ? "bg-surface-container-lowest text-on-surface shadow-sm"
                          : "text-on-surface-variant hover:text-on-surface"
                      }`}
                    >
                      {r}
                    </button>
                  ))}
                </div>
              </div>

              {/* Common fields */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="aegis-label" htmlFor="fullName">Full Name</label>
                  <input id="fullName" type="text" className="aegis-input" placeholder="Juan Dela Cruz"
                    value={fullName} onChange={(e) => setFullName(e.target.value)} />
                </div>
                <div>
                  <label className="aegis-label" htmlFor="regEmail">Email Address</label>
                  <input id="regEmail" type="email" required className="aegis-input" placeholder="j.doe@dispatch.org"
                    value={email} onChange={(e) => setEmail(e.target.value)} />
                </div>
                <div className="md:col-span-2">
                  <label className="aegis-label" htmlFor="regPassword">Password</label>
                  <input id="regPassword" type="password" required minLength={6} className="aegis-input"
                    placeholder="••••••••••••" value={password} onChange={(e) => setPassword(e.target.value)} />
                </div>
              </div>

              {/* Conditional department fields */}
              {role === "department" && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6 border-t border-outline-variant/20 pt-8 mt-2">
                  <div className="md:col-span-2">
                    <h3 className="text-sm font-headline italic text-on-surface mb-2">Organizational Metadata</h3>
                  </div>
                  <div>
                    <label className="aegis-label" htmlFor="orgName">Org Name</label>
                    <input id="orgName" type="text" required className="aegis-input"
                      placeholder="Bureau of Emergency Management"
                      value={orgName} onChange={(e) => setOrgName(e.target.value)} />
                  </div>
                  <div>
                    <label className="aegis-label" htmlFor="deptType">Org Type</label>
                    <select id="deptType" className="aegis-input cursor-pointer"
                      value={deptType} onChange={(e) => setDeptType(e.target.value)}>
                      {DEPARTMENT_TYPES.map((dt) => (
                        <option key={dt.value} value={dt.value}>{dt.label}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="aegis-label" htmlFor="contactNumber">Contact Number</label>
                    <input id="contactNumber" type="tel" className="aegis-input" placeholder="+63 XXX XXX XXXX"
                      value={contactNumber} onChange={(e) => setContactNumber(e.target.value)} />
                  </div>
                  <div>
                    <label className="aegis-label" htmlFor="areaResp">Operational Area</label>
                    <input id="areaResp" type="text" className="aegis-input" placeholder="North East Region"
                      value={areaOfResponsibility} onChange={(e) => setAreaOfResponsibility(e.target.value)} />
                  </div>
                  <div className="md:col-span-2">
                    <label className="aegis-label" htmlFor="deptAddress">Physical Address</label>
                    <input id="deptAddress" type="text" className="aegis-input" placeholder="742 Scholarly Lane, Suite 400"
                      value={address} onChange={(e) => setAddress(e.target.value)} />
                  </div>
                </div>
              )}

              <div className="pt-4">
                <button
                  type="submit"
                  disabled={loading}
                  className="w-full bg-gradient-to-br from-[#5f5e5c] to-[#535250] text-[#faf7f3] py-4 rounded-md font-medium text-sm tracking-widest uppercase hover:opacity-95 active:scale-[0.98] transition-all shadow-lg shadow-[#5f5e5c]/10 disabled:opacity-50"
                >
                  {loading ? "Creating account..." : "Create Account"}
                </button>
                <p className="mt-6 text-center text-xs text-on-surface-variant leading-relaxed">
                  By registering, you agree to our <span className="underline">Terms & Guidelines</span> and our
                  commitment to data sovereignty within crisis management.
                </p>
              </div>
            </form>
          </div>
        </div>
      </main>

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

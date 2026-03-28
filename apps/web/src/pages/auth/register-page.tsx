import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
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
};

export function RegisterPage() {
  const navigate = useNavigate();
  const setSession = useSessionStore((s) => s.setSession);

  const [role, setRole] = useState<"citizen" | "department">("citizen");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");

  // Department-specific fields
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

      const res = await apiRequest<RegisterResponse>("/api/auth/register", {
        method: "POST",
        body: JSON.stringify(body),
      });

      if (res.access_token) {
        setSession({
          user: {
            id: res.user.id,
            email: res.user.email,
            role: res.user.role,
            full_name: res.user.full_name,
          },
          accessToken: res.access_token,
          department: res.department ?? null,
        });

        if (role === "department") {
          navigate("/department");
        } else {
          navigate("/citizen");
        }
      } else {
        // Email confirmation required - redirect to login
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
    <div className="mx-auto flex min-h-screen max-w-lg items-center px-6 py-12">
      <Card className="w-full">
        <p className="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
          Dispatch
        </p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight">Create an account</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Register as a citizen to report incidents, or as a department to respond.
        </p>

        <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
          {error && (
            <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}

          {/* Role selector */}
          <div className="flex gap-2">
            {(["citizen", "department"] as const).map((r) => (
              <button
                key={r}
                type="button"
                className={`flex-1 rounded-lg border px-4 py-2.5 text-sm font-medium capitalize transition-colors ${
                  role === r
                    ? "border-primary bg-primary/10 text-primary"
                    : "border-border bg-white text-muted-foreground hover:bg-muted"
                }`}
                onClick={() => setRole(r)}
              >
                {r}
              </button>
            ))}
          </div>

          <div className="space-y-1.5">
            <label className="text-sm font-medium" htmlFor="fullName">
              Full name
            </label>
            <input
              id="fullName"
              type="text"
              className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
              placeholder="Juan Dela Cruz"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-sm font-medium" htmlFor="regEmail">
              Email
            </label>
            <input
              id="regEmail"
              type="email"
              required
              className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-sm font-medium" htmlFor="regPassword">
              Password
            </label>
            <input
              id="regPassword"
              type="password"
              required
              minLength={6}
              className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
              placeholder="At least 6 characters"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>

          {role === "department" && (
            <div className="space-y-4 rounded-lg border border-border/70 bg-muted/30 p-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-accent">
                Department details
              </p>

              <div className="space-y-1.5">
                <label className="text-sm font-medium" htmlFor="orgName">
                  Organization name *
                </label>
                <input
                  id="orgName"
                  type="text"
                  required
                  className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                  placeholder="e.g. Marikina City Fire Station"
                  value={orgName}
                  onChange={(e) => setOrgName(e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium" htmlFor="deptType">
                  Department type
                </label>
                <select
                  id="deptType"
                  className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                  value={deptType}
                  onChange={(e) => setDeptType(e.target.value)}
                >
                  {DEPARTMENT_TYPES.map((dt) => (
                    <option key={dt.value} value={dt.value}>
                      {dt.label}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium" htmlFor="contactNumber">
                  Contact number
                </label>
                <input
                  id="contactNumber"
                  type="tel"
                  className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                  placeholder="+63 XXX XXX XXXX"
                  value={contactNumber}
                  onChange={(e) => setContactNumber(e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium" htmlFor="deptAddress">
                  Address
                </label>
                <input
                  id="deptAddress"
                  type="text"
                  className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                  placeholder="Office address"
                  value={address}
                  onChange={(e) => setAddress(e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium" htmlFor="areaResp">
                  Area of responsibility
                </label>
                <input
                  id="areaResp"
                  type="text"
                  className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                  placeholder="e.g. Marikina City and nearby barangays"
                  value={areaOfResponsibility}
                  onChange={(e) => setAreaOfResponsibility(e.target.value)}
                />
              </div>
            </div>
          )}

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Creating account…" : "Create account"}
          </Button>
        </form>

        <p className="mt-6 text-center text-sm text-muted-foreground">
          Already have an account?{" "}
          <Link className="font-medium text-primary hover:underline" to="/auth/login">
            Sign in
          </Link>
        </p>
      </Card>
    </div>
  );
}

import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";

type Department = {
  id: string;
  name: string;
  type: string;
  verification_status: string;
  rejection_reason?: string | null;
  contact_number?: string | null;
  address?: string | null;
  area_of_responsibility?: string | null;
  created_at: string;
};

const statusColors: Record<string, string> = {
  pending: "bg-yellow-100 text-yellow-800",
  approved: "bg-green-100 text-green-800",
  rejected: "bg-red-100 text-red-800",
};

const typeLabels: Record<string, string> = {
  fire: "Fire (BFP)",
  police: "Police (PNP)",
  medical: "Medical",
  disaster: "MDRRMO",
  rescue: "Rescue",
  other: "Other",
};

export function MunicipalityDepartmentsPage() {
  const [departments, setDepartments] = useState<Department[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiRequest<{ departments: Department[] }>("/api/municipality/departments")
      .then((res) => setDepartments(res.departments))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  return (
    <AppShell subtitle="All registered departments" title="Departments">
      {loading ? (
        <Card className="py-10 text-center text-muted-foreground">Loading…</Card>
      ) : departments.length === 0 ? (
        <Card className="py-10 text-center text-muted-foreground">
          No departments registered yet.
        </Card>
      ) : (
        <div className="space-y-3">
          {departments.map((dept) => (
            <Card key={dept.id}>
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h3 className="font-semibold">{dept.name}</h3>
                  <span className="text-xs text-muted-foreground">
                    {typeLabels[dept.type] ?? dept.type}
                  </span>
                </div>
                <span
                  className={`shrink-0 rounded-full px-3 py-1 text-xs font-semibold capitalize ${statusColors[dept.verification_status] ?? "bg-gray-100"}`}
                >
                  {dept.verification_status}
                </span>
              </div>
              {dept.rejection_reason && (
                <p className="mt-2 text-sm text-red-600">
                  Rejection reason: {dept.rejection_reason}
                </p>
              )}
              <div className="mt-2 text-xs text-muted-foreground">
                {dept.address && <span>{dept.address}</span>}
                {dept.contact_number && <span> · {dept.contact_number}</span>}
              </div>
            </Card>
          ))}
        </div>
      )}
    </AppShell>
  );
}

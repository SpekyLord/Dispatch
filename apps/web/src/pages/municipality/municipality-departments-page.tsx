import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";

/**
 * Phase 1 — Municipality departments list.
 * Aegis-styled read-only list of all registered departments with
 * status badges (pending/approved/rejected).
 */

type Department = {
  id: string; name: string; type: string; verification_status: string;
  rejection_reason?: string | null; contact_number?: string | null;
  address?: string | null; area_of_responsibility?: string | null; created_at: string;
};

const statusStyles: Record<string, { bg: string; text: string; label: string }> = {
  pending: { bg: "bg-[#ffdbd0]", text: "text-[#89391e]", label: "Pending" },
  approved: { bg: "bg-[#d4edda]", text: "text-[#155724]", label: "Approved" },
  rejected: { bg: "bg-error-container/20", text: "text-error", label: "Rejected" },
};

const typeLabels: Record<string, string> = {
  fire: "Fire (BFP)", police: "Police (PNP)", medical: "Medical",
  disaster: "MDRRMO", rescue: "Rescue", other: "Other",
};

const typeIcons: Record<string, string> = {
  fire: "local_fire_department", police: "shield", medical: "medical_services",
  disaster: "storm", rescue: "health_and_safety", other: "domain",
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
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl animate-pulse">hourglass_empty</span>
        </Card>
      ) : departments.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">domain</span>
          <p className="text-on-surface-variant">No departments registered yet.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {departments.map((dept) => {
            const style = statusStyles[dept.verification_status] ?? statusStyles.pending;
            return (
              <Card key={dept.id}>
                <div className="flex items-start justify-between gap-4">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-lg bg-surface-container-highest flex items-center justify-center text-on-surface-variant">
                      <span className="material-symbols-outlined">{typeIcons[dept.type] ?? "domain"}</span>
                    </div>
                    <div>
                      <h3 className="font-semibold text-on-surface">{dept.name}</h3>
                      <span className="text-xs text-on-surface-variant">{typeLabels[dept.type] ?? dept.type}</span>
                    </div>
                  </div>
                  <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${style.bg} ${style.text}`}>
                    {style.label}
                  </span>
                </div>

                {dept.rejection_reason && (
                  <div className="mt-3 rounded-md bg-error-container/10 border border-error/10 px-4 py-2.5 text-sm text-error">
                    <span className="font-semibold">Rejection reason:</span> {dept.rejection_reason}
                  </div>
                )}

                <div className="mt-3 flex flex-wrap gap-4 text-xs text-on-surface-variant">
                  {dept.address && (
                    <span className="flex items-center gap-1">
                      <span className="material-symbols-outlined text-[12px]">location_on</span>
                      {dept.address}
                    </span>
                  )}
                  {dept.contact_number && (
                    <span className="flex items-center gap-1">
                      <span className="material-symbols-outlined text-[12px]">call</span>
                      {dept.contact_number}
                    </span>
                  )}
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </AppShell>
  );
}

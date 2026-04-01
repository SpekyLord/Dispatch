// Municipality assessments page — view all department damage assessments.

import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";

import { apiRequest } from "@/lib/api/client";
import { useLocale } from "@/lib/i18n/locale-context";

type Assessment = {
  id: string;
  affected_area: string;
  damage_level: string;
  estimated_casualties: number;
  displaced_persons: number;
  location: string;
  description: string;
  image_urls?: string[];
  created_at: string;
  department_name?: string;
};

// Colour-coded damage level badges
const damageLevelStyles: Record<string, { bg: string; text: string }> = {
  minor: { bg: "bg-green-100", text: "text-green-800" },
  moderate: { bg: "bg-yellow-100", text: "text-yellow-800" },
  severe: { bg: "bg-orange-100", text: "text-orange-800" },
  critical: { bg: "bg-red-100", text: "text-red-800" },
};

export function MunicipalityAssessmentsPage() {
  const { t, getDamageLevelLabel } = useLocale();
  const [assessments, setAssessments] = useState<Assessment[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiRequest<{ assessments: Assessment[] }>("/api/municipality/assessments")
      .then((res) => setAssessments(res.assessments))
      .catch(() => setAssessments([]))
      .finally(() => setLoading(false));
  }, []);

  return (
    <AppShell subtitle={t("assessments.subtitle")} title={t("assessments.title")}>
      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl mb-4 block animate-pulse">hourglass_empty</span>
          {t("assessments.loading")}
        </Card>
      ) : assessments.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">assessment</span>
          <p className="text-on-surface-variant">{t("assessments.empty")}</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {assessments.map((a) => {
            const dmg = damageLevelStyles[a.damage_level] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };

            return (
              <Card key={a.id}>
                <div className="flex items-start justify-between gap-4">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-lg bg-secondary-container flex items-center justify-center text-secondary">
                      <span className="material-symbols-outlined">assessment</span>
                    </div>
                    <div>
                      <h3 className="text-sm font-semibold text-on-surface">{a.affected_area}</h3>
                      {a.department_name && (
                        <p className="text-[10px] uppercase tracking-widest text-on-surface-variant mt-0.5">
                          {t("assessments.byDepartment", { name: a.department_name })}
                        </p>
                      )}
                    </div>
                  </div>
                  <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${dmg.bg} ${dmg.text}`}>
                    {getDamageLevelLabel(a.damage_level)}
                  </span>
                </div>

                {a.description && (
                  <p className="mt-3 text-sm text-on-surface-variant leading-relaxed line-clamp-2">{a.description}</p>
                )}

                {/* Stats row */}
                <div className="mt-4 flex flex-wrap items-center gap-4 text-xs text-on-surface-variant">
                  <span className="flex items-center gap-1">
                    <span className="material-symbols-outlined text-[14px]">location_on</span>
                    {a.location}
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="material-symbols-outlined text-[14px]">personal_injury</span>
                    {t("assessments.casualties", { count: a.estimated_casualties })}
                  </span>
                  <span className="flex items-center gap-1">
                    <span className="material-symbols-outlined text-[14px]">group</span>
                    {t("assessments.displaced", { count: a.displaced_persons })}
                  </span>
                  <span className="ml-auto text-[10px]">
                    {new Date(a.created_at).toLocaleString()}
                  </span>
                </div>

                {/* Thumbnail images */}
                {a.image_urls && a.image_urls.length > 0 && (
                  <div className="mt-3 flex gap-2">
                    {a.image_urls.map((url, i) => (
                      <img key={i} src={url} alt={t("assessments.imageAlt", { index: i + 1 })}
                        className="w-16 h-16 rounded-lg border border-outline-variant/10 object-cover" />
                    ))}
                  </div>
                )}
              </Card>
            );
          })}
        </div>
      )}
    </AppShell>
  );
}

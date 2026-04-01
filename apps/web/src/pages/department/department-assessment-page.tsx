// Department assessment page — form to submit damage assessments + list of previous ones.

import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest, apiUpload } from "@/lib/api/client";
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
};

const damageLevelStyles: Record<string, { bg: string; text: string }> = {
  minor: { bg: "bg-green-100", text: "text-green-800" },
  moderate: { bg: "bg-yellow-100", text: "text-yellow-800" },
  severe: { bg: "bg-orange-100", text: "text-orange-800" },
  critical: { bg: "bg-red-100", text: "text-red-800" },
};

export function DepartmentAssessmentPage() {
  const { t, getDamageLevelLabel } = useLocale();
  const [assessments, setAssessments] = useState<Assessment[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  // Form state
  const [affectedArea, setAffectedArea] = useState("");
  const [damageLevel, setDamageLevel] = useState("minor");
  const [casualties, setCasualties] = useState(0);
  const [displaced, setDisplaced] = useState(0);
  const [location, setLocation] = useState("");
  const [description, setDescription] = useState("");
  const [images, setImages] = useState<File[]>([]);

  function fetchAssessments() {
    apiRequest<{ assessments: Assessment[] }>("/api/departments/assessments")
      .then((res) => setAssessments(res.assessments))
      .catch(() => setAssessments([]))
      .finally(() => setLoading(false));
  }

  useEffect(() => { fetchAssessments(); }, []);

  function resetForm() {
    setAffectedArea("");
    setDamageLevel("minor");
    setCasualties(0);
    setDisplaced(0);
    setLocation("");
    setDescription("");
    setImages([]);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSuccess(false);
    setSubmitting(true);

    try {
      // Use multipart if images attached, otherwise plain JSON
      if (images.length > 0) {
        const fd = new FormData();
        fd.append("affected_area", affectedArea);
        fd.append("damage_level", damageLevel);
        fd.append("estimated_casualties", String(casualties));
        fd.append("displaced_persons", String(displaced));
        fd.append("location", location);
        fd.append("description", description);
        images.forEach((img) => fd.append("images", img));
        await apiUpload("/api/departments/assessments", fd);
      } else {
        await apiRequest("/api/departments/assessments", {
          method: "POST",
          body: JSON.stringify({
            affected_area: affectedArea,
            damage_level: damageLevel,
            estimated_casualties: casualties,
            displaced_persons: displaced,
            location,
            description,
          }),
        });
      }
      setSuccess(true);
      resetForm();
      fetchAssessments();
    } catch (err) {
      setError(err instanceof Error ? err.message : t("departmentAssessments.error"));
    } finally {
      setSubmitting(false);
    }
  }

  function handleImageChange(e: React.ChangeEvent<HTMLInputElement>) {
    const files = e.target.files;
    if (!files) return;
    // Cap at 3 images
    const selected = Array.from(files).slice(0, 3);
    setImages(selected);
  }

  return (
    <AppShell subtitle={t("departmentAssessments.subtitle")} title={t("departmentAssessments.title")}>
      {/* Submission form */}
      <Card className="mb-8">
        <h2 className="font-headline text-2xl text-on-surface mb-6">{t("departmentAssessments.submitTitle")}</h2>

        {error && (
          <div className="mb-4 rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-800">{error}</div>
        )}
        {success && (
          <div className="mb-4 rounded-lg bg-green-50 border border-green-200 px-4 py-3 text-sm text-green-800">
            {t("departmentAssessments.success")}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label className="aegis-label">{t("departmentAssessments.affectedArea")}</label>
              <input aria-label={t("departmentAssessments.affectedArea")} type="text" required className="aegis-input w-full" value={affectedArea}
                onChange={(e) => setAffectedArea(e.target.value)} placeholder={t("departmentAssessments.placeholderArea")} />
            </div>
            <div>
              <label className="aegis-label">{t("departmentAssessments.damageLevel")}</label>
              <select aria-label={t("departmentAssessments.damageLevel")} className="aegis-input w-full" value={damageLevel} onChange={(e) => setDamageLevel(e.target.value)}>
                <option value="minor">{getDamageLevelLabel("minor")}</option>
                <option value="moderate">{getDamageLevelLabel("moderate")}</option>
                <option value="severe">{getDamageLevelLabel("severe")}</option>
                <option value="critical">{getDamageLevelLabel("critical")}</option>
              </select>
            </div>
            <div>
              <label className="aegis-label">{t("departmentAssessments.estimatedCasualties")}</label>
              <input aria-label={t("departmentAssessments.estimatedCasualties")} type="number" min={0} className="aegis-input w-full" value={casualties}
                onChange={(e) => setCasualties(Number(e.target.value))} />
            </div>
            <div>
              <label className="aegis-label">{t("departmentAssessments.displacedPersons")}</label>
              <input aria-label={t("departmentAssessments.displacedPersons")} type="number" min={0} className="aegis-input w-full" value={displaced}
                onChange={(e) => setDisplaced(Number(e.target.value))} />
            </div>
          </div>

          <div>
            <label className="aegis-label">{t("departmentAssessments.location")}</label>
            <input aria-label={t("departmentAssessments.location")} type="text" required className="aegis-input w-full" value={location}
              onChange={(e) => setLocation(e.target.value)} placeholder={t("departmentAssessments.placeholderLocation")} />
          </div>

          <div>
            <label className="aegis-label">{t("departmentAssessments.description")}</label>
            <textarea aria-label={t("departmentAssessments.description")} className="aegis-input w-full min-h-[100px]" value={description}
              onChange={(e) => setDescription(e.target.value)} placeholder={t("departmentAssessments.placeholderDescription")} />
          </div>

          <div>
            <label className="aegis-label">{t("departmentAssessments.images")}</label>
            <input type="file" accept="image/*" multiple className="aegis-input w-full" onChange={handleImageChange} />
            {images.length > 0 && (
              <p className="mt-1 text-xs text-on-surface-variant">{t("departmentAssessments.imagesSelected", { count: images.length })}</p>
            )}
          </div>

          <Button type="submit" variant="secondary" disabled={submitting}>
            {submitting ? t("departmentAssessments.submitting") : t("departmentAssessments.submit")}
          </Button>
        </form>
      </Card>

      {/* Previous assessments list */}
      <h2 className="font-headline text-2xl text-on-surface mb-4">{t("departmentAssessments.previousTitle")}</h2>

      {loading ? (
        <Card className="py-12 text-center text-on-surface-variant">
          <LoadingDots sizeClassName="h-4 w-4" />
        </Card>
      ) : assessments.length === 0 ? (
        <Card className="py-12 text-center">
          <span className="material-symbols-outlined text-4xl text-outline-variant mb-3 block">assessment</span>
          <p className="text-on-surface-variant">{t("departmentAssessments.empty")}</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {assessments.map((a) => {
            const dmg = damageLevelStyles[a.damage_level] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };
            return (
              <Card key={a.id}>
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h3 className="text-sm font-semibold text-on-surface">{a.affected_area}</h3>
                    <p className="text-xs text-on-surface-variant mt-0.5">{a.location}</p>
                  </div>
                  <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${dmg.bg} ${dmg.text}`}>
                    {getDamageLevelLabel(a.damage_level)}
                  </span>
                </div>
                {a.description && (
                  <p className="mt-2 text-sm text-on-surface-variant line-clamp-2">{a.description}</p>
                )}
                <div className="mt-3 flex flex-wrap items-center gap-3 text-xs text-on-surface-variant">
                  <span>{t("assessments.casualties", { count: a.estimated_casualties })}</span>
                  <span>{t("assessments.displaced", { count: a.displaced_persons })}</span>
                  <span className="ml-auto text-[10px]">{new Date(a.created_at).toLocaleString()}</span>
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </AppShell>
  );
}

import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest, apiUpload } from "@/lib/api/client";

/**
 * Phase 1 — Citizen report creation form.
 * Aegis-styled form with description, category/severity selects, address,
 * GPS auto-detect, and image upload (max 3, JPEG/PNG, 5 MB each).
 */

const CATEGORIES = [
  { value: "fire", label: "Fire", icon: "local_fire_department" },
  { value: "flood", label: "Flood", icon: "water_drop" },
  { value: "earthquake", label: "Earthquake", icon: "vibration" },
  { value: "road_accident", label: "Road Accident", icon: "car_crash" },
  { value: "medical", label: "Medical Emergency", icon: "medical_services" },
  { value: "structural", label: "Structural Damage", icon: "domain_disabled" },
  { value: "other", label: "Other", icon: "emergency" },
];

const SEVERITIES = [
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "critical", label: "Critical" },
];

type CreateReportResponse = { report: { id: string } };

export function CitizenReportFormPage() {
  const navigate = useNavigate();

  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("");
  const [severity, setSeverity] = useState("medium");
  const [address, setAddress] = useState("");
  const [latitude, setLatitude] = useState<number | null>(null);
  const [longitude, setLongitude] = useState<number | null>(null);
  const [files, setFiles] = useState<File[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [gpsStatus, setGpsStatus] = useState<"idle" | "loading" | "done" | "error">("idle");

  useEffect(() => {
    if ("geolocation" in navigator) {
      setGpsStatus("loading");
      navigator.geolocation.getCurrentPosition(
        (pos) => { setLatitude(pos.coords.latitude); setLongitude(pos.coords.longitude); setGpsStatus("done"); },
        () => setGpsStatus("error"),
        { timeout: 10000 },
      );
    }
  }, []);

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(e.target.files ?? []);
    if (files.length + selected.length > 3) { setError("Maximum 3 images per report."); return; }
    for (const f of selected) {
      if (!["image/jpeg", "image/png"].includes(f.type)) { setError("Only JPEG and PNG images are allowed."); return; }
      if (f.size > 5 * 1024 * 1024) { setError("Each image must be under 5 MB."); return; }
    }
    setError(null);
    setFiles((prev) => [...prev, ...selected]);
  }

  function removeFile(index: number) {
    setFiles((prev) => prev.filter((_, i) => i !== index));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!category) { setError("Please select a category."); return; }
    setError(null);
    setLoading(true);
    try {
      const body: Record<string, unknown> = { description, category, severity, address: address || undefined };
      if (latitude !== null && longitude !== null) { body.latitude = latitude; body.longitude = longitude; }
      const res = await apiRequest<CreateReportResponse>("/api/reports", { method: "POST", body: JSON.stringify(body) });
      const reportId = res.report.id;
      for (const file of files) {
        const formData = new FormData();
        formData.append("file", file);
        await apiUpload(`/api/reports/${reportId}/upload`, formData);
      }
      navigate(`/citizen/report/${reportId}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to submit report.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <AppShell subtitle="Submit an incident report" title="New Report">
      <Card className="mx-auto max-w-2xl">
        <form className="space-y-6" onSubmit={handleSubmit}>
          {error && (
            <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error">
              {error}
            </div>
          )}

          {/* Description */}
          <div>
            <label className="aegis-label" htmlFor="description">Incident Description *</label>
            <textarea
              id="description"
              required
              rows={4}
              className="aegis-input"
              placeholder="Describe the incident in detail..."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>

          {/* Category & Severity */}
          <div className="grid gap-6 md:grid-cols-2">
            <div>
              <label className="aegis-label" htmlFor="category">Category *</label>
              <select id="category" required className="aegis-input cursor-pointer"
                value={category} onChange={(e) => setCategory(e.target.value)}>
                <option value="">Select category...</option>
                {CATEGORIES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
              </select>
            </div>
            <div>
              <label className="aegis-label" htmlFor="severity">Severity</label>
              <select id="severity" className="aegis-input cursor-pointer"
                value={severity} onChange={(e) => setSeverity(e.target.value)}>
                {SEVERITIES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            </div>
          </div>

          {/* Address & GPS */}
          <div>
            <label className="aegis-label" htmlFor="address">Address / Location</label>
            <input id="address" type="text" className="aegis-input"
              placeholder="e.g. Corner of Rizal Ave and Mabini St, Brgy. San Jose"
              value={address} onChange={(e) => setAddress(e.target.value)} />
            <div className="mt-2 flex items-center gap-2 text-xs text-on-surface-variant">
              <span className="material-symbols-outlined text-[14px]">
                {gpsStatus === "done" ? "gps_fixed" : gpsStatus === "loading" ? "gps_not_fixed" : "gps_off"}
              </span>
              {gpsStatus === "loading" && "Detecting location..."}
              {gpsStatus === "done" && `${latitude?.toFixed(5)}, ${longitude?.toFixed(5)}`}
              {gpsStatus === "error" && "Could not detect GPS. Enter address manually."}
              {gpsStatus === "idle" && "GPS not available."}
            </div>
          </div>

          {/* Photo upload */}
          <div>
            <label className="aegis-label">Evidence Photos (max 3)</label>
            <p className="text-xs text-on-surface-variant mb-3">JPEG or PNG, up to 5 MB each.</p>
            <div className="flex flex-wrap gap-2 mb-3">
              {files.map((f, i) => (
                <div key={i} className="flex items-center gap-2 rounded-md bg-surface-container px-3 py-2 text-xs text-on-surface">
                  <span className="material-symbols-outlined text-[14px]">image</span>
                  <span className="truncate max-w-[120px]">{f.name}</span>
                  <button type="button" onClick={() => removeFile(i)}
                    className="text-error hover:text-error/80 ml-1">
                    <span className="material-symbols-outlined text-[14px]">close</span>
                  </button>
                </div>
              ))}
            </div>
            {files.length < 3 && (
              <label className="inline-flex items-center gap-2 cursor-pointer rounded-md border border-dashed border-outline-variant px-4 py-3 text-xs font-medium text-on-surface-variant hover:bg-surface-container transition-colors">
                <span className="material-symbols-outlined text-[16px]">add_photo_alternate</span>
                Add Photo
                <input type="file" accept="image/jpeg,image/png" className="hidden" onChange={handleFileChange} />
              </label>
            )}
          </div>

          {/* Submit */}
          <div className="flex gap-3 pt-4">
            <Button type="submit" disabled={loading} className="flex-1">
              {loading ? "Submitting..." : "Submit Report"}
            </Button>
            <Button type="button" variant="outline" onClick={() => navigate("/citizen")}>
              Cancel
            </Button>
          </div>
        </form>
      </Card>
    </AppShell>
  );
}

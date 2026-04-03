import { type ChangeEvent, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { useAppShellTheme } from "@/components/layout/app-shell-theme";
import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { apiRequest, apiUpload } from "@/lib/api/client";

/**
 * Phase 1 — Citizen report creation form.
 * Aegis-styled form with description, category/severity selects, address,
 * GPS auto-detect, and image upload (max 3, JPEG/PNG, 5 MB each).
 */

const CATEGORIES = [
  { value: "fire", label: "Fire" },
  { value: "flood", label: "Flood" },
  { value: "earthquake", label: "Earthquake" },
  { value: "road_accident", label: "Road Accident" },
  { value: "medical", label: "Medical Emergency" },
  { value: "structural", label: "Structural Failure" },
  { value: "other", label: "Other" },
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
  const { isDarkMode } = useAppShellTheme();

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
  const filePreviews = useMemo(
    () => files.map((file) => ({ file, url: URL.createObjectURL(file) })),
    [files],
  );

  useEffect(() => {
    void requestCurrentLocation(true);
  }, []);

  useEffect(() => () => {
    filePreviews.forEach((preview) => URL.revokeObjectURL(preview.url));
  }, [filePreviews]);

  async function requestCurrentLocation(silent = false) {
    if (!("geolocation" in navigator)) {
      setGpsStatus("idle");
      if (!silent) {
        setError("GPS is not available on this device.");
      }
      return;
    }

    setError(null);
    setGpsStatus("loading");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLatitude(position.coords.latitude);
        setLongitude(position.coords.longitude);
        setGpsStatus("done");
      },
      () => {
        setGpsStatus("error");
        if (!silent) {
          setError("Could not detect GPS. Enter address manually.");
        }
      },
      { timeout: 10000 },
    );
  }

  function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(e.target.files ?? []);
    if (files.length + selected.length > 3) { setError("Maximum 3 images per report."); return; }
    for (const f of selected) {
      if (!["image/jpeg", "image/png"].includes(f.type)) { setError("Only JPEG and PNG images are allowed."); return; }
      if (f.size > 5 * 1024 * 1024) { setError("Each image must be under 5 MB."); return; }
    }
    setError(null);
    setFiles((prev) => [...prev, ...selected]);
    e.target.value = "";
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

  const pageClassName = isDarkMode ? "space-y-8 text-[#f4eee8]" : "space-y-8";
  const shellCardClassName = isDarkMode
    ? "mx-auto max-w-4xl rounded-[34px] border border-[#2d2926] bg-[#1f1c1a] p-3 shadow-[rgba(0,0,0,0.38)_0px_30px_50px_-12px_inset,rgba(255,255,255,0.03)_0px_18px_26px_-18px_inset] md:p-4"
    : "mx-auto max-w-4xl rounded-[34px] border border-[#ead8cc] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset] md:p-4";
  const formPanelClassName = isDarkMode
    ? "space-y-7 rounded-[30px] border border-[#2f2b28] bg-[#252220] p-6 shadow-[rgba(0,0,0,0.28)_0px_18px_30px_-18px_inset,rgba(255,255,255,0.02)_0px_1px_0px_inset] transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#4a433d] hover:bg-[#292624]"
    : "space-y-7 rounded-[30px] border border-[#f1e4db] bg-[#fffaf4] p-6 shadow-[rgba(50,50,93,0.12)_0px_18px_30px_-18px_inset,rgba(255,255,255,0.85)_0px_1px_0px_inset] transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#e7c7b8] hover:bg-[#fffaf6]";
  const labelClassName = isDarkMode
    ? "mb-3 block text-[11px] font-bold uppercase tracking-[0.22em] text-[#b59787]"
    : "mb-3 block text-[11px] font-bold uppercase tracking-[0.22em] text-[#9c8475]";
  const inputClassName = isDarkMode
    ? "w-full rounded-[18px] border border-[#34302d] bg-[#2a2724] px-4 py-4 text-sm text-[#f2e7df] placeholder:text-[#8e8178] focus:border-[#d97757] focus:outline-none"
    : "w-full rounded-[18px] border border-[#ede1d7] bg-[#f7f2ea] px-4 py-4 text-sm text-[#4f4742] placeholder:text-[#b8aca3] focus:border-[#d97757] focus:outline-none";
  const subtleTextClassName = isDarkMode ? "text-[#b8a89d]" : "text-[#8d8178]";
  const photoSlotClassName = isDarkMode
    ? "relative flex h-32 items-center justify-center overflow-hidden rounded-[18px] border border-[#34302d] bg-[#2a2724]"
    : "relative flex h-32 items-center justify-center overflow-hidden rounded-[18px] border border-[#eee4db] bg-[#f3eee6]";
  const gpsLabel =
    gpsStatus === "loading"
      ? "Detecting location..."
      : gpsStatus === "done"
        ? `${latitude?.toFixed(5)}, ${longitude?.toFixed(5)}`
        : gpsStatus === "error"
          ? "Could not detect GPS. Enter address manually."
          : "GPS not available.";

  return (
    <AppShell subtitle="Submit an incident report" title="New Report">
      <div className={pageClassName}>
        <div className="mx-auto max-w-4xl">
          <h1 className={`font-headline text-4xl md:text-5xl ${isDarkMode ? "text-[#f4eee8]" : "text-[#3f352f]"}`}>
            Submit Accident Report
          </h1>
          <p className={`mt-3 max-w-2xl text-sm leading-7 ${subtleTextClassName}`}>
            Record critical incident data with scholarly precision. Your detailed report assists in risk
            reduction and organizational safety measures.
          </p>
        </div>

        <Card className={shellCardClassName}>
        <form className={formPanelClassName} onSubmit={handleSubmit}>
          {error && (
            <div className="rounded-[18px] border border-[#d97757]/25 bg-[#d97757]/10 px-4 py-3 text-sm text-[#d97757]">
              {error}
            </div>
          )}

          <div>
            <label className={labelClassName} htmlFor="description">
              Incident Description
            </label>
            <textarea
              id="description"
              required
              rows={6}
              className={`${inputClassName} min-h-[170px] resize-none`}
              placeholder="Describe the sequence of events, conditions, and parties involved..."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>

          <div className="grid gap-6 md:grid-cols-[1.2fr_1fr]">
            <div>
              <label className={labelClassName} htmlFor="category">
                Select Category
              </label>
              <select
                id="category"
                required
                className={`${inputClassName} cursor-pointer`}
                value={category}
                onChange={(e) => setCategory(e.target.value)}
              >
                <option value="">Select category...</option>
                {CATEGORIES.map((entry) => <option key={entry.value} value={entry.value}>{entry.label}</option>)}
              </select>
            </div>
            <div>
              <label className={labelClassName}>Severity</label>
              <div className={isDarkMode ? "flex rounded-[16px] border border-[#34302d] bg-[#2a2724] p-1" : "flex rounded-[16px] border border-[#ede1d7] bg-[#f7f2ea] p-1"}>
                {SEVERITIES.map((entry) => {
                  const active = severity === entry.value;
                  return (
                    <button
                      key={entry.value}
                      type="button"
                      className={
                        "flex-1 rounded-[12px] px-4 py-3 text-sm font-semibold transition-colors " +
                        (active
                          ? "bg-[#b55a36] text-white shadow-sm"
                          : isDarkMode
                            ? "text-[#c5b5aa] hover:bg-[#34302d]"
                            : "text-[#7f736c] hover:bg-[#ede4da]")
                      }
                      onClick={() => setSeverity(entry.value)}
                    >
                      {entry.label}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>

          <div>
            <label className={labelClassName} htmlFor="address">
              Address / Location
            </label>
            <div className={isDarkMode ? "flex flex-col gap-3 rounded-[18px] border border-[#34302d] bg-[#2a2724] p-2 md:flex-row md:items-center" : "flex flex-col gap-3 rounded-[18px] border border-[#ede1d7] bg-[#f7f2ea] p-2 md:flex-row md:items-center"}>
              <input
                id="address"
                type="text"
                className={`flex-1 border-0 bg-transparent px-3 py-2 text-sm focus:outline-none ${isDarkMode ? "text-[#f2e7df] placeholder:text-[#8e8178]" : "text-[#4f4742] placeholder:text-[#b8aca3]"}`}
                placeholder="Enter physical address or site ID"
                value={address}
                onChange={(e) => setAddress(e.target.value)}
              />
              <button
                type="button"
                onClick={() => void requestCurrentLocation()}
                className={isDarkMode ? "inline-flex items-center justify-center gap-2 rounded-[14px] bg-[#34302d] px-4 py-2 text-xs font-semibold text-[#f2e7df] transition-colors hover:bg-[#3f3935]" : "inline-flex items-center justify-center gap-2 rounded-[14px] bg-[#efe7dd] px-4 py-2 text-xs font-semibold text-[#5f5650] transition-colors hover:bg-[#e8ddd1]"}
              >
                <span className="material-symbols-outlined text-[15px]">my_location</span>
                Use Current
              </button>
            </div>
            <div className={`mt-3 flex items-center gap-2 text-xs font-medium ${subtleTextClassName}`}>
              <span className="material-symbols-outlined text-[15px] text-[#d97757]">location_on</span>
              {gpsLabel}
            </div>
          </div>

          <div>
            <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
              <div>
                <label className={labelClassName}>Evidence Photos</label>
                <p className={`text-xs ${subtleTextClassName}`}>Attach up to 3 visual records for the archival log.</p>
              </div>
              {files.length < 3 && (
                <label className="inline-flex cursor-pointer items-center gap-2 text-sm font-semibold text-[#c56f46] transition-colors hover:text-[#a84f2c]">
                  <span className="material-symbols-outlined text-[18px]">add_a_photo</span>
                  Add Photo
                  <input type="file" accept="image/jpeg,image/png" className="hidden" onChange={handleFileChange} />
                </label>
              )}
            </div>
            <div className="mt-4 grid gap-4 sm:grid-cols-3">
              {Array.from({ length: 3 }).map((_, index) => {
                const preview = filePreviews[index];
                return (
                  <div key={index} className={photoSlotClassName}>
                    {preview ? (
                      <>
                        <img alt={preview.file.name} className="h-full w-full object-cover" src={preview.url} />
                        <button
                          type="button"
                          onClick={() => removeFile(index)}
                          className="absolute right-2 top-2 inline-flex h-8 w-8 items-center justify-center rounded-full bg-black/65 text-white transition-colors hover:bg-black/80"
                        >
                          <span className="material-symbols-outlined text-[16px]">close</span>
                        </button>
                      </>
                    ) : (
                      <div className={`flex flex-col items-center gap-2 text-center ${subtleTextClassName}`}>
                        <span className="material-symbols-outlined text-[22px] opacity-70">image</span>
                        <span className="text-[11px] font-semibold uppercase tracking-[0.18em]">Slot {index + 1}</span>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          <div className="flex flex-col-reverse gap-3 pt-4 sm:flex-row sm:items-center sm:justify-end">
            <Button type="button" variant="outline" onClick={() => navigate("/citizen")} className="min-w-[180px]">
              Cancel Submission
            </Button>
            <Button type="submit" disabled={loading} className="min-w-[200px]">
              {loading ? "Submitting..." : "Submit Report"}
            </Button>
          </div>
        </form>
        </Card>
      </div>
    </AppShell>
  );
}

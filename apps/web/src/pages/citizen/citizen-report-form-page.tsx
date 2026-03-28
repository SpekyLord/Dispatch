import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest, apiUpload } from "@/lib/api/client";

const CATEGORIES = [
  { value: "fire", label: "Fire" },
  { value: "flood", label: "Flood" },
  { value: "earthquake", label: "Earthquake" },
  { value: "road_accident", label: "Road Accident" },
  { value: "medical", label: "Medical Emergency" },
  { value: "structural", label: "Structural Damage" },
  { value: "other", label: "Other" },
];

const SEVERITIES = [
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "critical", label: "Critical" },
];

type CreateReportResponse = {
  report: { id: string };
};

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

  // GPS auto-detect on mount
  useEffect(() => {
    if ("geolocation" in navigator) {
      setGpsStatus("loading");
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          setLatitude(pos.coords.latitude);
          setLongitude(pos.coords.longitude);
          setGpsStatus("done");
        },
        () => setGpsStatus("error"),
        { timeout: 10000 },
      );
    }
  }, []);

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(e.target.files ?? []);
    if (files.length + selected.length > 3) {
      setError("Maximum 3 images per report.");
      return;
    }
    for (const f of selected) {
      if (!["image/jpeg", "image/png"].includes(f.type)) {
        setError("Only JPEG and PNG images are allowed.");
        return;
      }
      if (f.size > 5 * 1024 * 1024) {
        setError("Each image must be under 5 MB.");
        return;
      }
    }
    setError(null);
    setFiles((prev) => [...prev, ...selected]);
  }

  function removeFile(index: number) {
    setFiles((prev) => prev.filter((_, i) => i !== index));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!category) {
      setError("Please select a category.");
      return;
    }
    setError(null);
    setLoading(true);

    try {
      const body: Record<string, unknown> = {
        description,
        category,
        severity,
        address: address || undefined,
      };
      if (latitude !== null && longitude !== null) {
        body.latitude = latitude;
        body.longitude = longitude;
      }

      const res = await apiRequest<CreateReportResponse>("/api/reports", {
        method: "POST",
        body: JSON.stringify(body),
      });

      const reportId = res.report.id;

      // Upload images sequentially
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
        <form className="space-y-5" onSubmit={handleSubmit}>
          {error && (
            <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}

          <div className="space-y-1.5">
            <label className="text-sm font-medium" htmlFor="description">
              Description *
            </label>
            <textarea
              id="description"
              required
              rows={4}
              className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
              placeholder="Describe the incident in detail…"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="category">
                Category *
              </label>
              <select
                id="category"
                required
                className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                value={category}
                onChange={(e) => setCategory(e.target.value)}
              >
                <option value="">Select category…</option>
                {CATEGORIES.map((c) => (
                  <option key={c.value} value={c.value}>
                    {c.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="severity">
                Severity
              </label>
              <select
                id="severity"
                className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
                value={severity}
                onChange={(e) => setSeverity(e.target.value)}
              >
                {SEVERITIES.map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="space-y-1.5">
            <label className="text-sm font-medium" htmlFor="address">
              Address / Location description
            </label>
            <input
              id="address"
              type="text"
              className="w-full rounded-lg border border-border bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/30"
              placeholder="e.g. Corner of Rizal Ave and Mabini St, Brgy. San Jose"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              GPS:{" "}
              {gpsStatus === "loading"
                ? "Detecting location…"
                : gpsStatus === "done"
                  ? `${latitude?.toFixed(5)}, ${longitude?.toFixed(5)}`
                  : gpsStatus === "error"
                    ? "Could not detect GPS. Enter address manually."
                    : "Not available."}
            </p>
          </div>

          {/* Image upload */}
          <div className="space-y-2">
            <label className="text-sm font-medium">Photos (max 3, JPEG/PNG, up to 5 MB each)</label>
            <div className="flex flex-wrap gap-2">
              {files.map((f, i) => (
                <div
                  key={i}
                  className="relative rounded-lg border border-border bg-muted/50 px-3 py-2 text-xs"
                >
                  {f.name}
                  <button
                    type="button"
                    className="ml-2 text-red-500 hover:text-red-700"
                    onClick={() => removeFile(i)}
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
            {files.length < 3 && (
              <input
                type="file"
                accept="image/jpeg,image/png"
                className="text-sm"
                onChange={handleFileChange}
              />
            )}
          </div>

          <div className="flex gap-3">
            <Button type="submit" disabled={loading} className="flex-1">
              {loading ? "Submitting…" : "Submit Report"}
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

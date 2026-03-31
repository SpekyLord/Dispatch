import { useEffect, useState, type ChangeEvent, type FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { apiUpload } from "@/lib/api/client";

const POST_CATEGORIES = [
  { value: "alert", label: "Alert" },
  { value: "warning", label: "Warning" },
  { value: "safety_tip", label: "Safety Tip" },
  { value: "update", label: "Update" },
  { value: "situational_report", label: "Situational Report" },
];

const MAX_POST_PHOTOS = 3;
const MAX_POST_ATTACHMENTS = 5;
const ALLOWED_PHOTO_TYPES = ["image/jpeg", "image/png"];
const ALLOWED_ATTACHMENT_TYPES = [
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "text/plain",
  "text/csv",
];

type DepartmentCreatePostFormProps = {
  onCancel?: () => void;
  onSuccess?: () => void | Promise<void>;
  submitLabel?: string;
};

export function DepartmentCreatePostForm({
  onCancel,
  onSuccess,
  submitLabel = "Publish",
}: DepartmentCreatePostFormProps) {
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [category, setCategory] = useState("update");
  const [location, setLocation] = useState("");
  const [photoFiles, setPhotoFiles] = useState<File[]>([]);
  const [attachmentFiles, setAttachmentFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [gpsStatus, setGpsStatus] = useState<"idle" | "loading" | "done" | "error" | "unsupported">("idle");
  const [permissionState, setPermissionState] = useState<"idle" | "prompt" | "granted" | "denied" | "unsupported">("idle");

  function importCurrentLocation() {
    if (!("geolocation" in navigator)) {
      setGpsStatus("unsupported");
      setPermissionState("unsupported");
      setLocation("");
      return;
    }

    setError(null);
    setGpsStatus("loading");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocation(`${pos.coords.latitude.toFixed(5)}, ${pos.coords.longitude.toFixed(5)}`);
        setGpsStatus("done");
        setPermissionState("granted");
      },
      (geoError) => {
        setLocation("");
        setGpsStatus("error");
        if (geoError.code === 1) {
          setPermissionState("denied");
        }
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 60000,
      },
    );
  }

  useEffect(() => {
    if (!("geolocation" in navigator)) {
      setGpsStatus("unsupported");
      setPermissionState("unsupported");
      return;
    }

    if (!("permissions" in navigator) || !navigator.permissions?.query) {
      return;
    }

    let active = true;
    void navigator.permissions
      .query({ name: "geolocation" })
      .then((status) => {
        if (!active) {
          return;
        }
        setPermissionState(status.state);
        status.onchange = () => {
          if (active) {
            setPermissionState(status.state);
          }
        };
      })
      .catch(() => undefined);

    return () => {
      active = false;
    };
  }, []);

  function handlePhotoChange(e: ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(e.target.files ?? []);
    if (photoFiles.length + selected.length > MAX_POST_PHOTOS) {
      setError(`Maximum ${MAX_POST_PHOTOS} photos per post.`);
      return;
    }
    for (const file of selected) {
      if (!ALLOWED_PHOTO_TYPES.includes(file.type)) {
        setError("Only JPEG and PNG photos are allowed.");
        return;
      }
      if (file.size > 5 * 1024 * 1024) {
        setError("Each photo must be under 5 MB.");
        return;
      }
    }
    setError(null);
    setPhotoFiles((prev) => [...prev, ...selected]);
  }

  function handleAttachmentChange(e: ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(e.target.files ?? []);
    if (attachmentFiles.length + selected.length > MAX_POST_ATTACHMENTS) {
      setError(`Maximum ${MAX_POST_ATTACHMENTS} attachments per post.`);
      return;
    }
    for (const file of selected) {
      if (!ALLOWED_ATTACHMENT_TYPES.includes(file.type)) {
        setError("Attachments must be PDF, Office documents, TXT, or CSV files.");
        return;
      }
      if (file.size > 10 * 1024 * 1024) {
        setError("Each attachment must be under 10 MB.");
        return;
      }
    }
    setError(null);
    setAttachmentFiles((prev) => [...prev, ...selected]);
  }

  function removePhoto(index: number) {
    setPhotoFiles((prev) => prev.filter((_, i) => i !== index));
  }

  function removeAttachment(index: number) {
    setAttachmentFiles((prev) => prev.filter((_, i) => i !== index));
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!title.trim() || !content.trim()) {
      setError("Title and content are required.");
      return;
    }
    if (gpsStatus !== "done" || !location.trim()) {
      setError("Turn on location services and import your current location before publishing.");
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const formData = new FormData();
      formData.append("title", title.trim());
      formData.append("content", content.trim());
      formData.append("category", category);
      formData.append("location", location.trim());
      for (const photo of photoFiles) {
        formData.append("photos", photo);
      }
      for (const attachment of attachmentFiles) {
        formData.append("attachments", attachment);
      }

      await apiUpload("/api/departments/posts", formData);
      setTitle("");
      setContent("");
      setCategory("update");
      setPhotoFiles([]);
      setAttachmentFiles([]);
      await onSuccess?.();
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "Failed to create post.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="space-y-5" onSubmit={handleSubmit}>
      {error && (
        <div className="rounded-md border border-error/20 bg-error-container/20 px-4 py-3 text-sm text-error">
          {error}
        </div>
      )}

      <div>
        <label className="aegis-label">Title</label>
        <input
          type="text"
          className="aegis-input"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Announcement title"
        />
      </div>

      <div>
        <label className="aegis-label">Content</label>
        <textarea
          className="aegis-input min-h-[120px]"
          value={content}
          onChange={(e) => setContent(e.target.value)}
          placeholder="Write your announcement..."
        />
      </div>

      <div>
        <label className="aegis-label">Category</label>
        <select className="aegis-input" value={category} onChange={(e) => setCategory(e.target.value)}>
          {POST_CATEGORIES.map((postCategory) => (
            <option key={postCategory.value} value={postCategory.value}>
              {postCategory.label}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label className="aegis-label">Location</label>
        <div className="space-y-3">
          <input
            type="text"
            className="aegis-input"
            value={location}
            readOnly
            placeholder="Turn on location services to import your current location"
          />
          <div className="flex flex-wrap items-center gap-3">
            <Button
              type="button"
              variant="outline"
              onClick={importCurrentLocation}
              disabled={gpsStatus === "loading"}
            >
              {gpsStatus === "loading"
                ? "Requesting location..."
                : permissionState === "granted" || gpsStatus === "done"
                  ? "Use current location"
                  : "Request location access"}
            </Button>
            <div className="flex items-center gap-2 text-xs text-on-surface-variant">
              <span className="material-symbols-outlined text-[14px]">
                {gpsStatus === "done"
                  ? "gps_fixed"
                  : gpsStatus === "loading"
                    ? "gps_not_fixed"
                    : "gps_off"}
              </span>
              <span>
                {gpsStatus === "loading" && "Waiting for your browser to request location access..."}
                {gpsStatus === "done" && "Current location imported from this device."}
                {gpsStatus === "error" && "Location access was denied or unavailable. Click the button to request access from your browser."}
                {gpsStatus === "unsupported" && "This device or browser does not support location access."}
                {gpsStatus === "idle" && permissionState === "granted" && "Location is ready to be imported from this browser."}
                {gpsStatus === "idle" && permissionState === "prompt" && "Click the button to let your browser request location access."}
                {gpsStatus === "idle" && permissionState === "denied" && "Location access is blocked. Allow this site in your browser settings, then try again."}
                {gpsStatus === "idle" && permissionState === "idle" && "Location is required before publishing this post."}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div>
        <label className="aegis-label">Photos</label>
        <p className="mb-3 text-xs text-on-surface-variant">JPEG or PNG, up to 5 MB each.</p>
        <div className="mb-3 flex flex-wrap gap-2">
          {photoFiles.map((file, index) => (
            <div key={`${file.name}-${index}`} className="flex items-center gap-2 rounded-md bg-surface-container px-3 py-2 text-xs text-on-surface">
              <span className="material-symbols-outlined text-[14px]">image</span>
              <span className="max-w-[180px] truncate">{file.name}</span>
              <button type="button" onClick={() => removePhoto(index)} className="ml-1 text-error hover:text-error/80">
                <span className="material-symbols-outlined text-[14px]">close</span>
              </button>
            </div>
          ))}
        </div>
        {photoFiles.length < MAX_POST_PHOTOS && (
          <label className="inline-flex cursor-pointer items-center gap-2 rounded-md border border-dashed border-outline-variant px-4 py-3 text-xs font-medium text-on-surface-variant transition-colors hover:bg-surface-container">
            <span className="material-symbols-outlined text-[16px]">add_photo_alternate</span>
            Add Photo
            <input
              type="file"
              accept="image/jpeg,image/png"
              multiple
              className="hidden"
              onChange={handlePhotoChange}
            />
          </label>
        )}
      </div>

      <div>
        <label className="aegis-label">Attachments</label>
        <p className="mb-3 text-xs text-on-surface-variant">PDF, Office documents, TXT, or CSV, up to 10 MB each.</p>
        <div className="mb-3 flex flex-wrap gap-2">
          {attachmentFiles.map((file, index) => (
            <div key={`${file.name}-${index}`} className="flex items-center gap-2 rounded-md bg-surface-container px-3 py-2 text-xs text-on-surface">
              <span className="material-symbols-outlined text-[14px]">attach_file</span>
              <span className="max-w-[180px] truncate">{file.name}</span>
              <button type="button" onClick={() => removeAttachment(index)} className="ml-1 text-error hover:text-error/80">
                <span className="material-symbols-outlined text-[14px]">close</span>
              </button>
            </div>
          ))}
        </div>
        {attachmentFiles.length < MAX_POST_ATTACHMENTS && (
          <label className="inline-flex cursor-pointer items-center gap-2 rounded-md border border-dashed border-outline-variant px-4 py-3 text-xs font-medium text-on-surface-variant transition-colors hover:bg-surface-container">
            <span className="material-symbols-outlined text-[16px]">upload_file</span>
            Add Attachment
            <input
              type="file"
              accept=".pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.txt,.csv"
              multiple
              className="hidden"
              onChange={handleAttachmentChange}
            />
          </label>
        )}
      </div>

      <div className="flex gap-3 pt-2">
        <Button type="submit" variant="secondary" disabled={loading}>
          {loading ? "Publishing..." : submitLabel}
        </Button>
        {onCancel && (
          <Button type="button" variant="outline" onClick={onCancel}>
            Cancel
          </Button>
        )}
      </div>
    </form>
  );
}

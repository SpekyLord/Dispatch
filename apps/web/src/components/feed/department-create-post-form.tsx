import { useEffect, useState, type ChangeEvent, type FormEvent, type ReactNode } from "react";

import {
  FEED_DAMAGE_LEVEL_OPTIONS,
  type FeedAssessmentDetails,
  type FeedPostKind,
} from "@/components/feed/assessment-post-summary";
import { Button } from "@/components/ui/button";
import { apiRequest, apiUpload } from "@/lib/api/client";

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

const POST_KIND_OPTIONS: Array<{
  value: FeedPostKind;
  label: string;
  description: string;
  icon: string;
  iconAccentClassName: string;
}> = [
  {
    value: "standard",
    label: "Regular Post",
    description: "Use the usual public bulletin layout for announcements and updates.",
    icon: "campaign",
    iconAccentClassName: "bg-[#ffeadf] text-[#a14b2f]",
  },
  {
    value: "assessment",
    label: "Assessment Post",
    description: "Publish a structured field assessment with damage and impact statistics.",
    icon: "monitoring",
    iconAccentClassName: "bg-[#f5e9dd] text-[#8b5b3e]",
  },
] as const;

const DEFAULT_ASSESSMENT_DETAILS: FeedAssessmentDetails = {
  affected_area: "",
  damage_level: "minor",
  estimated_casualties: 0,
  displaced_persons: 0,
  description: "",
};

type DepartmentCreatePostFormProps = {
  mode?: "create" | "edit";
  postId?: string | number;
  initialValues?: {
    title?: string;
    content?: string;
    category?: string;
    location?: string;
    post_kind?: FeedPostKind;
    assessment_details?: FeedAssessmentDetails | null;
  };
  onCancel?: () => void;
  onSuccess?: () => void | Promise<void>;
  submitLabel?: string;
};

function FieldLabel({ icon, children }: { icon: string; children: ReactNode }) {
  return (
    <label className="aegis-label flex items-center gap-2">
      <span className="material-symbols-outlined text-[15px] text-[#b35e38]">{icon}</span>
      <span>{children}</span>
    </label>
  );
}

export function DepartmentCreatePostForm({
  mode = "create",
  postId,
  initialValues,
  onCancel,
  onSuccess,
  submitLabel = "Publish",
}: DepartmentCreatePostFormProps) {
  const [title, setTitle] = useState(initialValues?.title ?? "");
  const [content, setContent] = useState(initialValues?.content ?? "");
  const [category, setCategory] = useState(initialValues?.category ?? "update");
  const [location, setLocation] = useState(initialValues?.location ?? "");
  const [postKind, setPostKind] = useState<FeedPostKind>(initialValues?.post_kind ?? "standard");
  const [assessmentDetails, setAssessmentDetails] = useState<FeedAssessmentDetails>(
    initialValues?.assessment_details ?? DEFAULT_ASSESSMENT_DETAILS,
  );
  const [photoFiles, setPhotoFiles] = useState<File[]>([]);
  const [attachmentFiles, setAttachmentFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [gpsStatus, setGpsStatus] = useState<"idle" | "loading" | "done" | "error" | "unsupported">(
    initialValues?.location ? "done" : "idle",
  );
  const [permissionState, setPermissionState] = useState<"idle" | "prompt" | "granted" | "denied" | "unsupported">("idle");

  useEffect(() => {
    setTitle(initialValues?.title ?? "");
    setContent(initialValues?.content ?? "");
    setCategory(initialValues?.category ?? "update");
    setLocation(initialValues?.location ?? "");
    setPostKind(initialValues?.post_kind ?? "standard");
    setAssessmentDetails(initialValues?.assessment_details ?? DEFAULT_ASSESSMENT_DETAILS);
    setPhotoFiles([]);
    setAttachmentFiles([]);
    setGpsStatus(initialValues?.location ? "done" : "idle");
    setError(null);
  }, [
    initialValues?.assessment_details,
    initialValues?.category,
    initialValues?.content,
    initialValues?.location,
    initialValues?.post_kind,
    initialValues?.title,
    mode,
    postId,
  ]);

  function updateAssessmentField<Key extends keyof FeedAssessmentDetails>(
    field: Key,
    value: FeedAssessmentDetails[Key],
  ) {
    setAssessmentDetails((current) => ({
      ...current,
      [field]: value,
    }));
  }

  function handlePostKindChange(nextKind: FeedPostKind) {
    setPostKind(nextKind);
    setError(null);
    if (nextKind === "assessment" && category === "update") {
      setCategory("situational_report");
    }
  }

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
    if (!location.trim()) {
      setError("Location is required.");
      return;
    }
    if (postKind === "assessment" && !assessmentDetails.affected_area.trim()) {
      setError("Affected area is required for assessment posts.");
      return;
    }
    if (postKind === "assessment" && assessmentDetails.estimated_casualties < 0) {
      setError("Estimated casualties must be zero or greater.");
      return;
    }
    if (postKind === "assessment" && assessmentDetails.displaced_persons < 0) {
      setError("Displaced persons must be zero or greater.");
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const normalizedAssessmentDetails =
        postKind === "assessment"
          ? {
              affected_area: assessmentDetails.affected_area.trim(),
              damage_level: assessmentDetails.damage_level,
              estimated_casualties: Number(assessmentDetails.estimated_casualties || 0),
              displaced_persons: Number(assessmentDetails.displaced_persons || 0),
              description: assessmentDetails.description?.trim() ?? "",
            }
          : null;

      if (mode === "edit") {
        if (!postId) {
          throw new Error("Post id is required for editing.");
        }
        await apiRequest(`/api/feed/${postId}`, {
          method: "PUT",
          body: JSON.stringify({
            title: title.trim(),
            content: content.trim(),
            category,
            location: location.trim(),
            post_kind: postKind,
            assessment_details: normalizedAssessmentDetails,
          }),
        });
      } else {
        const formData = new FormData();
        formData.append("title", title.trim());
        formData.append("content", content.trim());
        formData.append("category", category);
        formData.append("location", location.trim());
        formData.append("post_kind", postKind);
        if (normalizedAssessmentDetails) {
          formData.append("assessment_details", JSON.stringify(normalizedAssessmentDetails));
        }
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
        setLocation("");
        setPostKind("standard");
        setAssessmentDetails(DEFAULT_ASSESSMENT_DETAILS);
        setPhotoFiles([]);
        setAttachmentFiles([]);
        setGpsStatus("idle");
      }
      await onSuccess?.();
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : mode === "edit"
            ? "Failed to update post."
            : "Failed to create post.",
      );
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

      <div className="pb-1">
        <FieldLabel icon="tune">Post Format</FieldLabel>
        <div className="grid gap-3 md:grid-cols-2">
          {POST_KIND_OPTIONS.map((option) => {
            const active = postKind === option.value;
            return (
              <button
                key={option.value}
                type="button"
                aria-label={option.label}
                aria-pressed={active}
                onClick={() => handlePostKindChange(option.value)}
                className={`rounded-[22px] border px-4 py-4 text-left transition-all ${
                  active
                    ? "border-[#b35e38] bg-[#fff3ec] shadow-[0_12px_22px_-18px_rgba(179,94,56,0.55)]"
                    : "border-[#e2d1c7] bg-[#fff8f3] hover:border-[#d9c2b5] hover:bg-[#fffaf6]"
                }`}
              >
                <div className="flex items-center gap-3">
                  <span
                    className={`flex h-11 w-11 items-center justify-center rounded-2xl shadow-[0_10px_18px_-14px_rgba(161,75,47,0.38)] ${option.iconAccentClassName}`}
                  >
                    <span className="material-symbols-outlined text-[20px]">{option.icon}</span>
                  </span>
                  <p className="text-sm font-semibold text-on-surface">{option.label}</p>
                </div>
                <div className="mt-3 border-t border-[#ead8cc] pt-3">
                  <p className="text-xs leading-5 text-on-surface-variant">{option.description}</p>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      <div className="border-t border-[#ead8cc] pt-6">
        <div>
          <FieldLabel icon="title">Title</FieldLabel>
          <input
            type="text"
            className="aegis-input"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={postKind === "assessment" ? "Assessment headline" : "Announcement title"}
          />
        </div>

        <div className="mt-5">
          <FieldLabel icon="notes">Content</FieldLabel>
          <textarea
            className="aegis-input min-h-[120px]"
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder={
              postKind === "assessment"
                ? "Write the operational summary for this field assessment..."
                : "Write your announcement..."
            }
          />
        </div>

        <div className="mt-5">
          <FieldLabel icon="sell">Feed Category</FieldLabel>
          <select className="aegis-input" value={category} onChange={(e) => setCategory(e.target.value)}>
            {POST_CATEGORIES.map((postCategory) => (
              <option key={postCategory.value} value={postCategory.value}>
                {postCategory.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {postKind === "assessment" && (
        <div className="rounded-[28px] border border-[#e2d1c7] bg-[#fff8f3] p-5">
          <div className="mb-4">
            <div className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
              <span className="material-symbols-outlined text-[16px]">monitoring</span>
              <span>Assessment Details</span>
            </div>
            <p className="mt-2 text-sm leading-relaxed text-on-surface-variant">
              Publish the same structured impact details teams already use inside the assessments tab.
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <FieldLabel icon="pin_drop">Affected Area</FieldLabel>
              <input
                aria-label="Affected Area"
                type="text"
                className="aegis-input w-full"
                value={assessmentDetails.affected_area}
                onChange={(e) => updateAssessmentField("affected_area", e.target.value)}
                placeholder="Barangay, district, or operations zone"
              />
            </div>
            <div>
              <FieldLabel icon="warning">Damage Level</FieldLabel>
              <select
                aria-label="Damage Level"
                className="aegis-input w-full"
                value={assessmentDetails.damage_level}
                onChange={(e) => updateAssessmentField("damage_level", e.target.value)}
              >
                {FEED_DAMAGE_LEVEL_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <FieldLabel icon="groups">Estimated Casualties</FieldLabel>
              <input
                aria-label="Estimated Casualties"
                type="number"
                min={0}
                className="aegis-input w-full"
                value={assessmentDetails.estimated_casualties}
                onChange={(e) => updateAssessmentField("estimated_casualties", Number(e.target.value))}
              />
            </div>
            <div>
              <FieldLabel icon="group_off">Displaced Persons</FieldLabel>
              <input
                aria-label="Displaced Persons"
                type="number"
                min={0}
                className="aegis-input w-full"
                value={assessmentDetails.displaced_persons}
                onChange={(e) => updateAssessmentField("displaced_persons", Number(e.target.value))}
              />
            </div>
          </div>

          <div className="mt-4">
            <FieldLabel icon="article">Assessment Note</FieldLabel>
            <textarea
              aria-label="Assessment Note"
              className="aegis-input min-h-[110px] w-full"
              value={assessmentDetails.description ?? ""}
              onChange={(e) => updateAssessmentField("description", e.target.value)}
              placeholder="Summarize damage observations, access limits, and response concerns..."
            />
          </div>
        </div>
      )}

      <div className="border-t border-[#ead8cc] pt-6">
        <FieldLabel icon="location_on">Location</FieldLabel>
        <div className="space-y-3">
          <input
            type="text"
            className="aegis-input"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
            placeholder={
              mode === "edit"
                ? "Update the location for this announcement"
                : "Turn on location services to import your current location"
            }
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

      {mode === "create" && (
        <>
          <div className="border-t border-[#ead8cc] pt-6">
            <FieldLabel icon="photo_library">Photos</FieldLabel>
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

          <div className="border-t border-[#ead8cc] pt-6">
            <FieldLabel icon="attach_file">Attachments</FieldLabel>
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
        </>
      )}

      <div className="flex gap-3 border-t border-[#ead8cc] pt-5">
        <Button type="submit" variant="secondary" disabled={loading}>
          {loading ? (mode === "edit" ? "Saving..." : "Publishing...") : submitLabel}
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

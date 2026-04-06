import { type ChangeEvent, useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";

import {
  ProfileInteractivePostStack,
  type ProfileInteractiveDepartment,
  type ProfileInteractivePost,
} from "@/components/feed/profile-interactive-post-stack";
import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest, apiUpload } from "@/lib/api/client";
import { useSessionStore, type DepartmentInfo } from "@/lib/auth/session-store";

type DepartmentProfileFormState = {
  name: string;
  type: string;
  description: string;
  contact_number: string;
  address: string;
  area_of_responsibility: string;
};

const profileTabs = ["Activity", "Announcements", "Bookmarks", "Archive"] as const;
const profileLaneEffectClassName =
  "dispatch-profile-publish-lane space-y-5 overflow-x-clip rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]";
const profileSurfaceClassName = "dispatch-profile-surface border-[#e2d1c7] bg-[#fff8f3]";
const profileRaisedCardClassName =
  "shadow-[0_5px_15px_0_#00000026]";
const profileCardHoverClassName =
  "dispatch-profile-card transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#e7c7b8] hover:bg-[#fffaf6] hover:shadow-[0_5px_5px_0_#00000026]";
const profilePillClassName =
  "dispatch-profile-pill border border-[#e2d1c7] bg-[#f7efe7] text-[#6f625b]";
const profileActionSurfaceClassName =
  "dispatch-profile-action-surface border border-[#dbc6b9] bg-[#f7efe7] text-on-surface transition-colors hover:bg-[#f3e7de]";
const departmentTypeOptions = [
  { value: "fire", label: "Fire (BFP)" },
  { value: "police", label: "Police (PNP)" },
  { value: "medical", label: "Medical" },
  { value: "disaster", label: "Disaster Response (MDRRMO)" },
  { value: "other", label: "Other" },
] as const;
const headerPlaceholderImage =
  "data:image/svg+xml;utf8," +
  encodeURIComponent(`
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 520">
      <defs>
        <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#74635b" />
          <stop offset="48%" stop-color="#5d514c" />
          <stop offset="100%" stop-color="#a14b2f" />
        </linearGradient>
      </defs>
      <rect width="1600" height="520" fill="url(#bg)" />
      <circle cx="1220" cy="150" r="160" fill="rgba(255,248,243,0.12)" />
      <circle cx="320" cy="420" r="220" fill="rgba(255,248,243,0.08)" />
      <path d="M0 370 C180 320 280 410 470 360 S760 250 980 310 S1320 420 1600 280 L1600 520 L0 520 Z" fill="rgba(255,248,243,0.1)" />
      <text x="110" y="175" fill="#fff8f3" font-family="Georgia, serif" font-size="56">Department Cover Placeholder</text>
      <text x="110" y="235" fill="#f5e8dd" font-family="Arial, sans-serif" font-size="28">Temporary visual for the profile header</text>
    </svg>
  `);

function summarizeProfilePostContent(content: string, maxLength = 92) {
  const collapsed = content.replace(/\s+/g, " ").trim();
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return `${collapsed.slice(0, maxLength).trimEnd()}...`;
}

function formatDepartmentType(value?: string | null) {
  if (!value) return "Department";
  return value
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function createProfileDraft(department: DepartmentInfo): DepartmentProfileFormState {
  return {
    name: department.name ?? "",
    type: department.type ?? "fire",
    description: department.description ?? "",
    contact_number: department.contact_number ?? "",
    address: department.address ?? "",
    area_of_responsibility: department.area_of_responsibility ?? "",
  };
}

export function DepartmentProfilePage() {
  const user = useSessionStore((state) => state.user);
  const sessionDepartment = useSessionStore((state) => state.department);
  const setDepartment = useSessionStore((state) => state.setDepartment);
  const [department, setDepartmentState] = useState<DepartmentInfo | null>(sessionDepartment);
  const [posts, setPosts] = useState<ProfileInteractivePost[]>([]);
  const [loading, setLoading] = useState(true);
  const [isEditProfileOpen, setIsEditProfileOpen] = useState(false);
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const [profilePhotoFile, setProfilePhotoFile] = useState<File | null>(null);
  const [headerPhotoFile, setHeaderPhotoFile] = useState<File | null>(null);
  const [profilePhotoPreviewUrl, setProfilePhotoPreviewUrl] = useState<string | null>(null);
  const [headerPhotoPreviewUrl, setHeaderPhotoPreviewUrl] = useState<string | null>(null);
  const [removeProfilePhoto, setRemoveProfilePhoto] = useState(false);
  const [removeHeaderPhoto, setRemoveHeaderPhoto] = useState(false);
  const [profileDraft, setProfileDraft] = useState<DepartmentProfileFormState>({
    name: "",
    type: "fire",
    description: "",
    contact_number: "",
    address: "",
    area_of_responsibility: "",
  });
  const profilePhotoInputRef = useRef<HTMLInputElement | null>(null);
  const headerPhotoInputRef = useRef<HTMLInputElement | null>(null);

  const loadDepartmentProfile = useCallback(
    async (currentUserId: string) => {
      const [departmentResponse, postsResponse] = await Promise.all([
        apiRequest<{ department: DepartmentInfo }>("/api/departments/profile"),
        apiRequest<{ posts: ProfileInteractivePost[] }>(`/api/feed?uploader=${currentUserId}`),
      ]);
      setDepartmentState(departmentResponse.department);
      setDepartment(departmentResponse.department);
      setPosts(postsResponse.posts);
      return departmentResponse.department;
    },
    [setDepartment],
  );

  useEffect(() => {
    if (!user) {
      setLoading(false);
      return;
    }

    loadDepartmentProfile(user.id)
      .catch(() => {
        setDepartmentState(null);
        setPosts([]);
      })
      .finally(() => setLoading(false));
  }, [loadDepartmentProfile, user]);

  const displayName = department?.name || user?.full_name || "Department Profile";
  const handle = user?.email?.split("@")[0] ?? "dept_command";
  const profilePhoto = department?.profile_picture || department?.profile_photo;
  const headerPhoto = department?.header_photo || headerPlaceholderImage;
  const postCount = department?.post_count ?? posts.length;
  const profileDescription = department?.description?.trim()
    ? department.description
    : "This department profile is ready for customization. Add your organization overview, public safety focus, and operating details here.";
  const profileRailPosts = posts.slice(0, 2);
  const interactiveDepartment: ProfileInteractiveDepartment | null = department
    ? {
        id: department.id ?? user?.id ?? "department",
        name: department.name ?? displayName,
        type: department.type,
        profile_picture: department.profile_picture,
        profile_photo: department.profile_photo,
        verification_status: department.verification_status,
      }
    : null;

  const draftProfilePhoto = removeProfilePhoto
    ? undefined
    : profilePhotoPreviewUrl || profilePhoto;
  const draftHeaderPhoto = removeHeaderPhoto
    ? headerPlaceholderImage
    : headerPhotoPreviewUrl || headerPhoto;

  useEffect(() => {
    if (!profilePhotoFile) {
      setProfilePhotoPreviewUrl(null);
      return;
    }
    const nextUrl = URL.createObjectURL(profilePhotoFile);
    setProfilePhotoPreviewUrl(nextUrl);
    return () => URL.revokeObjectURL(nextUrl);
  }, [profilePhotoFile]);

  useEffect(() => {
    if (!headerPhotoFile) {
      setHeaderPhotoPreviewUrl(null);
      return;
    }
    const nextUrl = URL.createObjectURL(headerPhotoFile);
    setHeaderPhotoPreviewUrl(nextUrl);
    return () => URL.revokeObjectURL(nextUrl);
  }, [headerPhotoFile]);

  function openEditProfile() {
    if (!department) {
      setProfileError("Department profile is still loading.");
      return;
    }
    setProfileDraft(createProfileDraft(department));
    setProfilePhotoFile(null);
    setHeaderPhotoFile(null);
    setRemoveProfilePhoto(false);
    setRemoveHeaderPhoto(false);
    setProfileError(null);
    setIsEditProfileOpen(true);
  }

  function updateProfileDraft<K extends keyof DepartmentProfileFormState>(
    key: K,
    value: DepartmentProfileFormState[K],
  ) {
    setProfileDraft((prev) => ({ ...prev, [key]: value }));
  }

  async function handleSaveProfile() {
    if (!user) {
      setProfileError("Department session not found.");
      return;
    }
    setProfileSaving(true);
    setProfileError(null);
    try {
      const formData = new FormData();
      formData.append("name", profileDraft.name.trim());
      formData.append("type", profileDraft.type);
      formData.append("description", profileDraft.description.trim());
      formData.append("contact_number", profileDraft.contact_number.trim());
      formData.append("address", profileDraft.address.trim());
      formData.append("area_of_responsibility", profileDraft.area_of_responsibility.trim());
      if (removeProfilePhoto) {
        formData.append("remove_profile_picture", "true");
      }
      if (removeHeaderPhoto) {
        formData.append("remove_header_photo", "true");
      }
      if (profilePhotoFile) {
        formData.append("profile_picture_file", profilePhotoFile);
      }
      if (headerPhotoFile) {
        formData.append("header_photo_file", headerPhotoFile);
      }

      await apiUpload<{ department: DepartmentInfo }>(
        "/api/departments/profile",
        formData,
        { method: "PUT" },
      );
      await loadDepartmentProfile(user.id);
      setIsEditProfileOpen(false);
    } catch (error) {
      setProfileError(error instanceof Error ? error.message : "Failed to update profile.");
    } finally {
      setProfileSaving(false);
    }
  }

  function handleProfilePhotoChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }
    if (!["image/jpeg", "image/png"].includes(file.type)) {
      setProfileError("Only JPEG and PNG images are allowed.");
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      setProfileError("Each image must be under 5 MB.");
      return;
    }
    setProfileError(null);
    setRemoveProfilePhoto(false);
    setProfilePhotoFile(file);
  }

  function handleHeaderPhotoChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }
    if (!["image/jpeg", "image/png"].includes(file.type)) {
      setProfileError("Only JPEG and PNG images are allowed.");
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      setProfileError("Each image must be under 5 MB.");
      return;
    }
    setProfileError(null);
    setRemoveHeaderPhoto(false);
    setHeaderPhotoFile(file);
  }

  function clearProfilePhoto() {
    setProfilePhotoFile(null);
    setRemoveProfilePhoto(true);
    if (profilePhotoInputRef.current) {
      profilePhotoInputRef.current.value = "";
    }
  }

  function clearHeaderPhoto() {
    setHeaderPhotoFile(null);
    setRemoveHeaderPhoto(true);
    if (headerPhotoInputRef.current) {
      headerPhotoInputRef.current.value = "";
    }
  }

  if (loading) {
    return (
      <AppShell subtitle="Department profile" title="Profile">
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading profile...
        </Card>
      </AppShell>
    );
  }

  if (!user || !department) {
    return (
      <AppShell subtitle="Department profile" title="Profile">
        <Card className="py-16 text-center text-on-surface-variant">
          Department profile details are not available yet.
        </Card>
      </AppShell>
    );
  }

  return (
    <AppShell subtitle="Department profile" title="Profile">
      <div className="dispatch-profile-page">
        <style>{`
          .dispatch-shell-dark .dispatch-profile-page .text-on-surface { color: #f4eee8 !important; }
          .dispatch-shell-dark .dispatch-profile-page .text-on-surface-variant { color: #c6b8ac !important; }
          .dispatch-shell-dark .dispatch-profile-page .text-outline,
          .dispatch-shell-dark .dispatch-profile-page .text-outline-variant { color: #9d8d80 !important; }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-publish-lane {
            background: #1d1b1a !important;
            box-shadow:
              rgba(255,255,255,0.04) 0px 1px 0px inset,
              rgba(0,0,0,0.48) 0px 24px 48px -18px inset !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-surface {
            background: #23211f !important;
            border-color: #34302b !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-card {
            box-shadow: 0 5px 15px 0 #00000026 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-card:hover {
            background: #292624 !important;
            border-color: #4a433d !important;
            box-shadow: 0 5px 5px 0 #00000026 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-pill,
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-tab-trigger,
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-action-surface {
            background: #2a2724 !important;
            border-color: #3b3732 !important;
            color: #d7c4b7 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-tab-trigger[data-active="true"] {
            background: #4a3025 !important;
            border-color: #9d654c !important;
            color: #fff4ec !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-divider {
            border-color: rgba(255,255,255,0.08) !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-avatar-shell {
            border-color: #23211f !important;
            background: #2a2724 !important;
            color: #d59b7c !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-header-overlay {
            background: linear-gradient(180deg, rgba(10,10,10,0.08), rgba(0,0,0,0.38)) !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-readiness-card {
            background: #2a2724 !important;
            border-color: #3b3732 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-form-input {
            background: #23211f !important;
            border-color: #3b3732 !important;
            color: #f4eee8 !important;
          }
        `}</style>
      <div className="grid gap-6 md:grid-cols-[minmax(0,1fr)_18rem] md:items-start xl:grid-cols-[minmax(0,1fr)_20rem]">
        <div className={`min-w-0 ${profileLaneEffectClassName}`}>
        <section className={`overflow-hidden rounded-[28px] border text-on-surface ${profileSurfaceClassName} ${profileRaisedCardClassName} ${profileCardHoverClassName}`}>
          <div className="relative h-56 overflow-hidden md:h-64">
            <img alt="Department profile header" className="h-full w-full object-cover" src={headerPhoto} />
            <div className="dispatch-profile-header-overlay absolute inset-0 bg-[linear-gradient(180deg,rgba(255,252,247,0.06),rgba(56,56,49,0.18))]" />
          </div>

          <div className="relative px-5 pb-6 pt-5 md:px-8">
            <div className="relative flex flex-col gap-5 md:flex-row md:items-start">
              <div className="dispatch-profile-avatar-shell absolute right-0 top-[-84px] h-28 w-28 overflow-hidden rounded-full border-4 border-[#fff8f3] bg-[#f2e7de] text-[#8f4427] shadow-lg md:h-36 md:w-36">
                {profilePhoto ? (
                  <img alt={`${displayName} profile`} className="h-full w-full object-cover" src={profilePhoto} />
                ) : (
                  <div className="flex h-full w-full items-center justify-center">
                    <span className="material-symbols-outlined text-[56px] md:text-[68px]">local_fire_department</span>
                  </div>
                )}
              </div>

              <div className="w-full">
                <div className="pr-8 md:pr-36">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="font-headline text-3xl text-on-surface md:text-4xl">{displayName}</h2>
                  {department.verification_status === "approved" && (
                    <span
                      className="material-symbols-outlined text-[#ff8a1f]"
                      style={{ fontVariationSettings: "\"FILL\" 1" }}
                    >
                      verified
                    </span>
                  )}
                </div>
                <p className="mt-1 text-lg text-[#a14b2f]">@{handle}</p>
                </div>
                <p className="mt-4 w-full text-[1.05rem] leading-relaxed text-on-surface-variant [text-align:justify]">
                  {profileDescription}
                </p>

                <div className="mt-4 flex flex-wrap gap-2">
                  <span className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-sm ${profilePillClassName}`}>
                    <span className="material-symbols-outlined text-[16px]">badge</span>
                    {formatDepartmentType(department.type)}
                  </span>
                  {department.contact_number && (
                    <span className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-sm ${profilePillClassName}`}>
                      <span className="material-symbols-outlined text-[16px]">call</span>
                      {department.contact_number}
                    </span>
                  )}
                  {department.area_of_responsibility && (
                    <span className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-sm ${profilePillClassName}`}>
                      <span className="material-symbols-outlined text-[16px]">location_on</span>
                      {department.area_of_responsibility}
                    </span>
                  )}
                  {department.address && (
                    <span className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-sm ${profilePillClassName}`}>
                      <span className="material-symbols-outlined text-[16px]">home_pin</span>
                      {department.address}
                    </span>
                  )}
                </div>

                <p className="mt-5 text-lg text-on-surface-variant">
                  <span className="font-semibold text-on-surface">{postCount}</span> published post{postCount === 1 ? "" : "s"}
                  <span className="mx-2 text-outline">|</span>
                  <span className="font-semibold capitalize text-on-surface">{department.verification_status}</span> status
                </p>

                <div className="mt-5 grid gap-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_52px]">
                  <Button
                    className={`rounded-xl px-6 py-4 text-base font-semibold normal-case tracking-normal ${profileActionSurfaceClassName}`}
                    onClick={openEditProfile}
                    type="button"
                    variant="secondary"
                  >
                    Edit Profile
                  </Button>
                  <Link to="/department/news-feed">
                    <button
                      className={`w-full rounded-xl px-6 py-4 text-base font-semibold ${profileActionSurfaceClassName}`}
                      type="button"
                    >
                      Open News Feed
                    </button>
                  </Link>
                  <Link
                    className={`flex items-center justify-center rounded-xl ${profileActionSurfaceClassName}`}
                    to="/department"
                  >
                    <span className="material-symbols-outlined">more_horiz</span>
                  </Link>
                </div>
              </div>
            </div>

            <nav className="mt-6 overflow-x-auto">
              <div className="flex min-w-max gap-3 pb-1">
                {profileTabs.map((tab, index) => (
                  <button
                    key={tab}
                    className={`dispatch-profile-tab-trigger inline-flex items-center rounded-full border px-4 py-2 text-sm font-semibold transition-all ${
                      index === 0
                        ? "border-[#a14b2f] bg-[#a14b2f] text-white"
                        : profilePillClassName
                    }`}
                    data-active={index === 0 ? "true" : "false"}
                    type="button"
                  >
                    {tab === "Archive" ? `Reads (${postCount})` : tab}
                  </button>
                ))}
              </div>
            </nav>
          </div>
        </section>

        {interactiveDepartment ? (
          <ProfileInteractivePostStack
            cardClassName={`${profileSurfaceClassName} ${profileRaisedCardClassName}`}
            department={interactiveDepartment}
            emptyMessage="No published announcements yet."
            hoverClassName={profileCardHoverClassName}
            posts={posts}
          />
        ) : null}
        </div>

        <div className="min-w-0">
          <div className="space-y-6 md:sticky md:top-6">
            <section className="overflow-hidden rounded-[28px] border border-[#e4c0ae] bg-gradient-to-br from-[#d98d63] via-[#bf6e49] to-[#a86446] p-4 text-white shadow-xl">
              <div className="mx-auto flex max-w-[17rem] items-center justify-center gap-3 rounded-2xl border border-white/10 bg-white/10 px-4 py-3 backdrop-blur-sm">
                <span className="material-symbols-outlined text-white/75">search</span>
                <input
                  aria-label="Temporary profile search"
                  className="w-full bg-transparent text-center text-sm text-white outline-none placeholder:text-center placeholder:text-white/55"
                  placeholder="Search response protocols and field updates..."
                  readOnly
                />
              </div>
            </section>

            <section className="overflow-hidden rounded-[28px] border border-[#e4c0ae] bg-gradient-to-br from-[#d98d63] via-[#bf6e49] to-[#a86446] p-5 text-white shadow-xl">
              <div className="flex flex-col items-center gap-4 text-center">
                <div className="mx-auto max-w-[17rem]">
                  <span className="inline-flex rounded-full border border-white/20 bg-white/10 px-3 py-1 text-[10px] font-bold uppercase tracking-[0.22em] text-white/90">
                    Department View
                  </span>
                  <h2 className="mt-3 font-headline text-[1.8rem] leading-[1.02]">ResilienceHub Temporary News Desk</h2>
                  <p className="mt-3 text-sm leading-relaxed text-white/80">
                    Keep the same News Feed utility rail while the profile block stays in the center column.
                  </p>
                </div>

                <div className="grid w-full max-w-[17rem] gap-3">
                  <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                    <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Published posts</p>
                    <p className="mt-2 font-headline text-4xl">{String(postCount).padStart(2, "0")}</p>
                    <p className="mt-1 text-xs text-white/70">Profile activity and public announcements</p>
                  </div>
                  <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                    <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Verification</p>
                    <p className="mt-2 font-headline text-2xl capitalize">{department.verification_status}</p>
                    <p className="mt-1 text-xs text-white/70">Department profile overview</p>
                  </div>
                </div>
              </div>
            </section>

            <Card className={profileSurfaceClassName}>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                Active Readiness
              </p>
              <div className="mt-5 space-y-5">
                {profileRailPosts.length === 0 ? (
                  <div className="dispatch-profile-readiness-card rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                    <p className="text-sm leading-relaxed text-on-surface-variant">
                      Published profile activity will appear here once your department has public posts.
                    </p>
                  </div>
                ) : (
                  profileRailPosts.map((post) => (
                    <div key={post.id} className="dispatch-profile-readiness-card rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                      <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                        {post.category.replace("_", " ")}
                      </p>
                      <p className="mt-2 text-lg leading-tight text-on-surface">
                        {summarizeProfilePostContent(post.content)}
                      </p>
                      <p className="mt-2 text-xs text-outline">{displayName}</p>
                    </div>
                  ))
                )}
              </div>
            </Card>
          </div>
        </div>

        {isEditProfileOpen && (
          <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/55 p-4 backdrop-blur-md md:p-8">
            <div className={`dispatch-profile-surface relative flex max-h-[92vh] w-full max-w-3xl flex-col overflow-hidden rounded-[28px] border text-on-surface shadow-[0_24px_60px_rgba(56,56,49,0.18)] ${profileSurfaceClassName}`}>
              <div className="dispatch-profile-divider flex items-center gap-4 border-b border-[#e2d1c7] bg-[#fff8f3]/95 px-5 py-4 backdrop-blur-sm md:px-6">
                <button
                  aria-label="Close edit profile modal"
                  className={`dispatch-profile-pill rounded-full p-2 text-on-surface-variant transition-colors hover:bg-[#f3e7de] hover:text-on-surface ${profilePillClassName}`}
                  onClick={() => setIsEditProfileOpen(false)}
                  type="button"
                >
                  <span className="material-symbols-outlined">close</span>
                </button>
                <h2 className="text-xl font-semibold text-on-surface">Edit profile</h2>
                <button
                  className="ml-auto rounded-full bg-[#a14b2f] px-5 py-2 text-xs font-semibold uppercase tracking-wide text-white transition-colors hover:bg-[#914024] disabled:cursor-not-allowed disabled:opacity-70"
                  disabled={profileSaving}
                  onClick={() => void handleSaveProfile()}
                  type="button"
                >
                  {profileSaving ? "Saving..." : "Save"}
                </button>
              </div>

              <div className="min-h-0 overflow-y-auto px-5 pb-8 pt-5 md:px-6">
                <div className={`relative overflow-hidden rounded-[24px] border bg-[#f7efe7] ${profilePillClassName}`}>
                  <div className="relative h-52 overflow-hidden bg-[#efe3da]">
                    <img
                      alt="Department header preview"
                      className="h-full w-full object-cover"
                      src={draftHeaderPhoto}
                    />
                    <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(255,252,247,0.06),rgba(56,56,49,0.18))]" />
                    <div className="absolute left-1/2 top-6 flex -translate-x-1/2 items-center gap-3">
                      <button
                        className={`dispatch-profile-pill rounded-full p-3 text-[#a14b2f] transition-colors hover:bg-[#f3e7de] ${profilePillClassName}`}
                        onClick={() => headerPhotoInputRef.current?.click()}
                        type="button"
                      >
                        <span className="material-symbols-outlined">imagesmode</span>
                      </button>
                      <button
                        className={`dispatch-profile-pill rounded-full p-3 text-[#a14b2f] transition-colors hover:bg-[#f3e7de] ${profilePillClassName}`}
                        onClick={clearHeaderPhoto}
                        type="button"
                      >
                        <span className="material-symbols-outlined">close</span>
                      </button>
                    </div>
                  </div>

                  <div className="relative px-4 pb-4 md:px-5">
                    <div className="-mt-12 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
                      <div className="flex flex-col gap-4 md:flex-row md:items-end">
                        <div className="dispatch-profile-avatar-shell flex h-24 w-24 items-center justify-center overflow-hidden rounded-full border-4 border-[#fff8f3] bg-[#f2e7de] text-[#8f4427] shadow-lg">
                          {draftProfilePhoto ? (
                            <img
                              alt="Department profile preview"
                              className="h-full w-full object-cover"
                              src={draftProfilePhoto}
                            />
                          ) : (
                            <span className="material-symbols-outlined text-[44px]">
                              local_fire_department
                            </span>
                          )}
                        </div>

                        <div className={`rounded-2xl border px-4 py-4 text-on-surface-variant md:min-w-[340px] ${profileSurfaceClassName}`}>
                          <p className="text-lg font-semibold text-on-surface">Edit your department page</p>
                          <p className="mt-1 text-sm text-on-surface-variant">
                            Update your public identity, description, and header visuals in one place.
                          </p>
                          <div className="mt-4 flex flex-wrap gap-2">
                            <button
                              className={`dispatch-profile-pill inline-flex items-center gap-2 rounded-full px-3 py-2 text-xs font-semibold text-[#a14b2f] transition-colors hover:bg-[#f3e7de] ${profilePillClassName}`}
                              onClick={() => profilePhotoInputRef.current?.click()}
                              type="button"
                            >
                              <span className="material-symbols-outlined text-[16px]">imagesmode</span>
                              Choose profile image
                            </button>
                            <button
                              className={`dispatch-profile-pill inline-flex items-center gap-2 rounded-full px-3 py-2 text-xs font-semibold text-[#a14b2f] transition-colors hover:bg-[#f3e7de] ${profilePillClassName}`}
                              onClick={clearProfilePhoto}
                              type="button"
                            >
                              <span className="material-symbols-outlined text-[16px]">close</span>
                              Remove profile image
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <input
                  ref={profilePhotoInputRef}
                  accept="image/jpeg,image/png"
                  className="hidden"
                  onChange={handleProfilePhotoChange}
                  type="file"
                />
                <input
                  ref={headerPhotoInputRef}
                  accept="image/jpeg,image/png"
                  className="hidden"
                  onChange={handleHeaderPhotoChange}
                  type="file"
                />

                {profileError && (
                  <div className="mt-5 rounded-2xl border border-error/20 bg-error-container/20 px-4 py-3 text-sm text-error">
                    {profileError}
                  </div>
                )}

                <div className="mt-5 space-y-5">
                  <div>
                    <label className="mb-2 block text-sm text-on-surface-variant" htmlFor="department-profile-name">
                      Name
                    </label>
                    <input
                      id="department-profile-name"
                      className="dispatch-profile-form-input w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
                      onChange={(event) => updateProfileDraft("name", event.target.value)}
                      placeholder="Department name"
                      type="text"
                      value={profileDraft.name}
                    />
                  </div>

                  <div>
                    <label className="mb-2 block text-sm text-on-surface-variant" htmlFor="department-profile-description">
                      Bio
                    </label>
                    <textarea
                      id="department-profile-description"
                      className="dispatch-profile-form-input min-h-[140px] w-full resize-none rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
                      onChange={(event) => updateProfileDraft("description", event.target.value)}
                      placeholder="Department description"
                      value={profileDraft.description}
                    />
                  </div>

                  <div className="grid gap-5 md:grid-cols-2">
                    <div>
                      <label className="mb-2 block text-sm text-on-surface-variant" htmlFor="department-profile-area">
                        Location / Area of Responsibility
                      </label>
                      <input
                        id="department-profile-area"
                        className="dispatch-profile-form-input w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
                        onChange={(event) => updateProfileDraft("area_of_responsibility", event.target.value)}
                        placeholder="Coverage area"
                        type="text"
                        value={profileDraft.area_of_responsibility}
                      />
                    </div>
                    <div>
                      <label className="mb-2 block text-sm text-on-surface-variant" htmlFor="department-profile-type">
                        Department Type
                      </label>
                      <select
                        id="department-profile-type"
                        className="dispatch-profile-form-input w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors focus:border-[#a14b2f]"
                        onChange={(event) => updateProfileDraft("type", event.target.value)}
                        value={profileDraft.type}
                      >
                        {departmentTypeOptions.map((option) => (
                          <option key={option.value} value={option.value}>
                            {option.label}
                          </option>
                        ))}
                      </select>
                    </div>
                  </div>

                  <div>
                    <label className="mb-2 block text-sm text-on-surface-variant" htmlFor="department-profile-address">
                      Address
                    </label>
                    <input
                      id="department-profile-address"
                      className="dispatch-profile-form-input w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
                      onChange={(event) => updateProfileDraft("address", event.target.value)}
                      placeholder="Office or station address"
                      type="text"
                      value={profileDraft.address}
                    />
                  </div>

                  <div>
                    <label className="mb-2 block text-sm text-on-surface-variant" htmlFor="department-profile-contact">
                      Contact Number
                    </label>
                    <input
                      id="department-profile-contact"
                      className="dispatch-profile-form-input w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
                      onChange={(event) => updateProfileDraft("contact_number", event.target.value)}
                      placeholder="Hotline or office contact"
                      type="text"
                      value={profileDraft.contact_number}
                    />
                  </div>

                  <div className={`rounded-xl border px-4 py-4 text-sm text-on-surface-variant ${profilePillClassName}`}>
                    Profile and header images are now selected from your device. JPEG and PNG files up to 5 MB are supported.
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
      </div>
    </AppShell>
  );
}

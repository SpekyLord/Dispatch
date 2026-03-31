import { type ChangeEvent, useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { apiRequest, apiUpload } from "@/lib/api/client";
import { useSessionStore, type DepartmentInfo } from "@/lib/auth/session-store";

type DepartmentProfilePost = {
  id: string | number;
  title: string;
  content: string;
  category: string;
  created_at: string;
  reaction?: number | null;
  comment_count?: number | null;
  photos?: string[];
};

type DepartmentProfileFormState = {
  name: string;
  type: string;
  description: string;
  contact_number: string;
  address: string;
  area_of_responsibility: string;
};

const profileTabs = ["Activity", "Announcements", "Bookmarks", "Archive"] as const;
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
  const [posts, setPosts] = useState<DepartmentProfilePost[]>([]);
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
        apiRequest<{ posts: DepartmentProfilePost[] }>(`/api/feed?uploader=${currentUserId}`),
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
          <span className="material-symbols-outlined mb-4 block animate-pulse text-4xl">
            hourglass_empty
          </span>
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
      <div className="space-y-8">
        <section className="overflow-hidden rounded-[28px] border border-[#e2d1c7] bg-[#fff8f3] text-on-surface shadow-sm">
          <div className="relative h-56 overflow-hidden md:h-64">
            <img alt="Department profile header" className="h-full w-full object-cover" src={headerPhoto} />
            <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(255,252,247,0.06),rgba(56,56,49,0.18))]" />
          </div>

          <div className="relative px-5 pb-6 pt-5 md:px-8">
            <div className="relative flex flex-col gap-5 md:flex-row md:items-start">
              <div className="absolute right-0 top-[-84px] h-28 w-28 overflow-hidden rounded-full border-4 border-[#fff8f3] bg-[#f2e7de] text-[#8f4427] shadow-lg md:h-36 md:w-36">
                {profilePhoto ? (
                  <img alt={`${displayName} profile`} className="h-full w-full object-cover" src={profilePhoto} />
                ) : (
                  <div className="flex h-full w-full items-center justify-center">
                    <span className="material-symbols-outlined text-[56px] md:text-[68px]">local_fire_department</span>
                  </div>
                )}
              </div>

              <div className="max-w-3xl pr-24 md:pr-44">
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
                <p className="mt-4 max-w-3xl text-[1.05rem] leading-relaxed text-on-surface-variant">
                  {profileDescription}
                </p>

                <div className="mt-4 flex flex-wrap gap-2">
                  <span className="inline-flex items-center gap-2 rounded-full border border-[#e2d1c7] bg-[#f7efe7] px-3 py-2 text-sm text-[#6f625b]">
                    <span className="material-symbols-outlined text-[16px]">badge</span>
                    {formatDepartmentType(department.type)}
                  </span>
                  {department.contact_number && (
                    <span className="inline-flex items-center gap-2 rounded-full border border-[#e2d1c7] bg-[#f7efe7] px-3 py-2 text-sm text-[#6f625b]">
                      <span className="material-symbols-outlined text-[16px]">call</span>
                      {department.contact_number}
                    </span>
                  )}
                  {department.area_of_responsibility && (
                    <span className="inline-flex items-center gap-2 rounded-full border border-[#e2d1c7] bg-[#f7efe7] px-3 py-2 text-sm text-[#6f625b]">
                      <span className="material-symbols-outlined text-[16px]">location_on</span>
                      {department.area_of_responsibility}
                    </span>
                  )}
                  {department.address && (
                    <span className="inline-flex items-center gap-2 rounded-full border border-[#e2d1c7] bg-[#f7efe7] px-3 py-2 text-sm text-[#6f625b]">
                      <span className="material-symbols-outlined text-[16px]">home_pin</span>
                      {department.address}
                    </span>
                  )}
                </div>

                <p className="mt-5 text-lg text-on-surface-variant">
                  <span className="font-semibold text-on-surface">{postCount}</span> published post{postCount === 1 ? "" : "s"}
                  <span className="mx-2 text-outline">â€¢</span>
                  <span className="font-semibold capitalize text-on-surface">{department.verification_status}</span> status
                </p>

                <div className="mt-5 grid gap-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_52px]">
                  <Button
                    className="rounded-xl px-6 py-4 text-base font-semibold normal-case tracking-normal"
                    onClick={openEditProfile}
                    type="button"
                    variant="secondary"
                  >
                    Edit Profile
                  </Button>
                  <Link to="/department/news-feed">
                    <button
                      className="w-full rounded-xl border border-[#dbc6b9] bg-[#f7efe7] px-6 py-4 text-base font-semibold text-on-surface transition-colors hover:bg-[#f3e7de]"
                      type="button"
                    >
                      Open News Feed
                    </button>
                  </Link>
                  <Link
                    className="flex items-center justify-center rounded-xl border border-[#dbc6b9] bg-[#f7efe7] text-on-surface transition-colors hover:bg-[#f3e7de]"
                    to="/department"
                  >
                    <span className="material-symbols-outlined">more_horiz</span>
                  </Link>
                </div>
              </div>
            </div>

            <nav className="mt-6 overflow-x-auto border-b border-outline-variant/15">
              <div className="flex min-w-max gap-12">
                {profileTabs.map((tab, index) => (
                  <button
                    key={tab}
                    className={`border-b-2 px-1 pb-4 text-sm font-semibold transition-colors ${
                      index === 0
                        ? "border-[#a14b2f] text-on-surface"
                        : "border-transparent text-on-surface-variant hover:text-on-surface"
                    }`}
                    type="button"
                  >
                    {tab === "Archive" ? `Reads (${postCount})` : tab}
                  </button>
                ))}
              </div>
            </nav>
          </div>
        </section>

        <div className="space-y-5">
          {posts.length === 0 ? (
            <Card className="border-[#e2d1c7] bg-[#fff8f3] py-14 text-center text-on-surface-variant">
              <span className="material-symbols-outlined mb-4 block text-4xl text-outline">
                campaign
              </span>
              No published announcements yet.
            </Card>
          ) : (
            posts.map((post) => (
              <Card key={post.id} className="border-[#e2d1c7] bg-[#fff8f3]">
                <article className="space-y-4">
                  <div className="flex gap-4">
                    <div className="flex h-10 w-10 items-center justify-center rounded-full bg-[#f2e7de] text-[#8f4427]">
                      <span className="material-symbols-outlined">campaign</span>
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-on-surface">{department.name}</span>
                        <span className="text-sm text-on-surface-variant">
                          {new Date(post.created_at).toLocaleString()}
                        </span>
                      </div>
                      <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                        {post.category.replace("_", " ")}
                      </p>
                    </div>
                  </div>

                  <div className="pl-0 md:pl-14">
                    <Link to={`/feed/${post.id}`}>
                      <h3 className="font-headline text-3xl leading-tight text-on-surface transition-colors hover:text-[#a14b2f]">
                        {post.title}
                      </h3>
                    </Link>
                    <p className="mt-3 max-w-3xl whitespace-pre-wrap text-base leading-relaxed text-on-surface-variant">
                      {post.content}
                    </p>

                    {post.photos && post.photos.length > 0 && (
                      <div className="mt-5 overflow-hidden rounded-xl border border-[#e2d1c7] bg-[#f7efe7]">
                        <img
                          alt={post.title}
                          className="h-64 w-full object-cover"
                          src={post.photos[0]}
                        />
                      </div>
                    )}

                    <div className="mt-5 flex items-center gap-6 text-on-surface-variant">
                      <button className="flex items-center gap-2 transition-colors hover:text-[#a14b2f]" type="button">
                        <span className="material-symbols-outlined">chat_bubble</span>
                        <span className="text-xs font-bold">{post.comment_count ?? 0}</span>
                      </button>
                      <button className="flex items-center gap-2 transition-colors hover:text-[#a14b2f]" type="button">
                        <span className="material-symbols-outlined">favorite</span>
                        <span className="text-xs font-bold">{post.reaction ?? 0}</span>
                      </button>
                      <Link
                        className="ml-auto flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-[#a14b2f] transition-colors hover:text-[#89391e]"
                        to={`/feed/${post.id}`}
                      >
                        <span className="material-symbols-outlined text-[18px]">open_in_new</span>
                        Open post
                      </Link>
                    </div>
                  </div>
                </article>
              </Card>
            ))
          )}
        </div>

        {isEditProfileOpen && (
          <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/55 p-4 backdrop-blur-md md:p-8">
            <div className="relative flex max-h-[92vh] w-full max-w-3xl flex-col overflow-hidden rounded-[28px] border border-[#e2d1c7] bg-[#fff8f3] text-on-surface shadow-[0_24px_60px_rgba(56,56,49,0.18)]">
              <div className="flex items-center gap-4 border-b border-[#e2d1c7] bg-[#fff8f3]/95 px-5 py-4 backdrop-blur-sm md:px-6">
                <button
                  aria-label="Close edit profile modal"
                  className="rounded-full p-2 text-on-surface-variant transition-colors hover:bg-[#f3e7de] hover:text-on-surface"
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
                <div className="relative overflow-hidden rounded-[24px] border border-[#e2d1c7] bg-[#f7efe7]">
                  <div className="relative h-52 overflow-hidden bg-[#efe3da]">
                    <img
                      alt="Department header preview"
                      className="h-full w-full object-cover"
                      src={draftHeaderPhoto}
                    />
                    <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(255,252,247,0.06),rgba(56,56,49,0.18))]" />
                    <div className="absolute left-1/2 top-6 flex -translate-x-1/2 items-center gap-3">
                      <button
                        className="rounded-full border border-[#e2d1c7] bg-[#fff8f3]/90 p-3 text-[#a14b2f] transition-colors hover:bg-[#f3e7de]"
                        onClick={() => headerPhotoInputRef.current?.click()}
                        type="button"
                      >
                        <span className="material-symbols-outlined">imagesmode</span>
                      </button>
                      <button
                        className="rounded-full border border-[#e2d1c7] bg-[#fff8f3]/90 p-3 text-[#a14b2f] transition-colors hover:bg-[#f3e7de]"
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
                        <div className="flex h-24 w-24 items-center justify-center overflow-hidden rounded-full border-4 border-[#fff8f3] bg-[#f2e7de] text-[#8f4427] shadow-lg">
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

                        <div className="rounded-2xl border border-[#e2d1c7] bg-[#fff8f3] px-4 py-4 text-on-surface-variant md:min-w-[340px]">
                          <p className="text-lg font-semibold text-on-surface">Edit your department page</p>
                          <p className="mt-1 text-sm text-on-surface-variant">
                            Update your public identity, description, and header visuals in one place.
                          </p>
                          <div className="mt-4 flex flex-wrap gap-2">
                            <button
                              className="inline-flex items-center gap-2 rounded-full border border-[#e2d1c7] bg-[#f7efe7] px-3 py-2 text-xs font-semibold text-[#a14b2f] transition-colors hover:bg-[#f3e7de]"
                              onClick={() => profilePhotoInputRef.current?.click()}
                              type="button"
                            >
                              <span className="material-symbols-outlined text-[16px]">imagesmode</span>
                              Choose profile image
                            </button>
                            <button
                              className="inline-flex items-center gap-2 rounded-full border border-[#e2d1c7] bg-[#f7efe7] px-3 py-2 text-xs font-semibold text-[#a14b2f] transition-colors hover:bg-[#f3e7de]"
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
                      className="w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
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
                      className="min-h-[140px] w-full resize-none rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
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
                        className="w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
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
                        className="w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors focus:border-[#a14b2f]"
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
                      className="w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
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
                      className="w-full rounded-xl border border-[#e2d1c7] bg-white px-4 py-4 text-base text-on-surface outline-none transition-colors placeholder:text-on-surface-variant/50 focus:border-[#a14b2f]"
                      onChange={(event) => updateProfileDraft("contact_number", event.target.value)}
                      placeholder="Hotline or office contact"
                      type="text"
                      value={profileDraft.contact_number}
                    />
                  </div>

                  <div className="rounded-xl border border-[#e2d1c7] bg-[#f7efe7] px-4 py-4 text-sm text-on-surface-variant">
                    Profile and header images are now selected from your device. JPEG and PNG files up to 5 MB are supported.
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

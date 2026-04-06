import { type ChangeEvent, useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";

import {
  ProfileInteractivePostStack,
  type ProfileInteractivePost,
} from "@/components/feed/profile-interactive-post-stack";
import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest, apiUpload } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";

type CitizenProfileFormState = {
  full_name: string;
  description: string;
  phone: string;
};

type ReportsCountResponse = { reports: { id: string }[] };
type ProfileResponse = { profile: {
  id: string; email: string; role: string; full_name?: string | null;
  phone?: string | null; avatar_url?: string | null;
  description?: string | null; header_photo?: string | null; profile_picture?: string | null;
  is_verified?: boolean;
} };

const profileTabs = ["Activity", "Reports", "Bookmarks", "Archive"] as const;

const profileLaneEffectClassName =
  "dispatch-profile-publish-lane space-y-5 overflow-x-clip rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]";
const profileSurfaceClassName = "dispatch-profile-surface border-[#e2d1c7] bg-[#fff8f3]";
const profileRaisedCardClassName = "shadow-[0_5px_15px_0_#00000026]";
const profileCardHoverClassName =
  "dispatch-profile-card transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#e7c7b8] hover:bg-[#fffaf6] hover:shadow-[0_5px_5px_0_#00000026]";
const profilePillClassName =
  "dispatch-profile-pill border border-[#e2d1c7] bg-[#f7efe7] text-[#6f625b]";
const profileActionSurfaceClassName =
  "dispatch-profile-action-surface border border-[#dbc6b9] bg-[#f7efe7] text-on-surface transition-colors hover:bg-[#f3e7de]";

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
    </svg>
  `);

function summarizePostContent(content: string, maxLength = 92) {
  const collapsed = content.replace(/\s+/g, " ").trim();
  return collapsed.length <= maxLength ? collapsed : `${collapsed.slice(0, maxLength).trimEnd()}...`;
}

export function CitizenProfilePage() {
  const user = useSessionStore((state) => state.user);
  const updateUser = useSessionStore((state) => state.updateUser);

  const [posts, setPosts] = useState<ProfileInteractivePost[]>([]);
  const [reportCount, setReportCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [isEditProfileOpen, setIsEditProfileOpen] = useState(false);
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);

  // Local copies of profile fields that can be updated without a page reload
  const [localProfile, setLocalProfile] = useState<{
    description: string | null;
    header_photo: string | null;
    profile_picture: string | null;
    is_verified: boolean;
  }>({ description: null, header_photo: null, profile_picture: null, is_verified: false });

  const [profileDraft, setProfileDraft] = useState<CitizenProfileFormState>({
    full_name: "", description: "", phone: "",
  });

  // File upload state
  const [profilePhotoFile, setProfilePhotoFile] = useState<File | null>(null);
  const [headerPhotoFile, setHeaderPhotoFile] = useState<File | null>(null);
  const [profilePhotoPreviewUrl, setProfilePhotoPreviewUrl] = useState<string | null>(null);
  const [headerPhotoPreviewUrl, setHeaderPhotoPreviewUrl] = useState<string | null>(null);
  const [removeProfilePhoto, setRemoveProfilePhoto] = useState(false);
  const [removeHeaderPhoto, setRemoveHeaderPhoto] = useState(false);

  const profilePhotoInputRef = useRef<HTMLInputElement | null>(null);
  const headerPhotoInputRef = useRef<HTMLInputElement | null>(null);

  const loadProfile = useCallback(async (userId: string) => {
    const [profileRes, postsRes, reportsRes] = await Promise.all([
      apiRequest<ProfileResponse>("/api/users/profile"),
      apiRequest<{ posts: ProfileInteractivePost[] }>(`/api/feed?uploader=${userId}`),
      apiRequest<ReportsCountResponse>(`/api/reports?reporter_id=${userId}`).catch(() => ({ reports: [] })),
    ]);
    setLocalProfile({
      description: profileRes.profile.description ?? null,
      header_photo: profileRes.profile.header_photo ?? null,
      profile_picture: profileRes.profile.profile_picture ?? null,
      is_verified: profileRes.profile.is_verified ?? false,
    });
    setPosts(postsRes.posts);
    setReportCount(Array.isArray(reportsRes.reports) ? reportsRes.reports.length : 0);
  }, []);

  useEffect(() => {
    if (!user) { setLoading(false); return; }
    loadProfile(user.id)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [loadProfile, user]);

  // Object URL cleanup
  useEffect(() => {
    if (!profilePhotoFile) { setProfilePhotoPreviewUrl(null); return; }
    const url = URL.createObjectURL(profilePhotoFile);
    setProfilePhotoPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [profilePhotoFile]);

  useEffect(() => {
    if (!headerPhotoFile) { setHeaderPhotoPreviewUrl(null); return; }
    const url = URL.createObjectURL(headerPhotoFile);
    setHeaderPhotoPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [headerPhotoFile]);

  function openEditProfile() {
    setProfileDraft({
      full_name: user?.full_name ?? "",
      description: localProfile.description ?? "",
      phone: user?.phone ?? "",
    });
    setProfilePhotoFile(null);
    setHeaderPhotoFile(null);
    setProfilePhotoPreviewUrl(null);
    setHeaderPhotoPreviewUrl(null);
    setRemoveProfilePhoto(false);
    setRemoveHeaderPhoto(false);
    setProfileError(null);
    setIsEditProfileOpen(true);
  }

  async function handleSaveProfile() {
    setProfileSaving(true);
    setProfileError(null);
    try {
      const formData = new FormData();
      formData.append("full_name", profileDraft.full_name);
      formData.append("description", profileDraft.description);
      formData.append("phone", profileDraft.phone);
      if (removeProfilePhoto) formData.append("remove_profile_picture", "true");
      if (removeHeaderPhoto) formData.append("remove_header_photo", "true");
      if (profilePhotoFile) formData.append("profile_picture_file", profilePhotoFile);
      if (headerPhotoFile) formData.append("header_photo_file", headerPhotoFile);

      const res = await apiUpload<ProfileResponse>("/api/users/profile", formData, { method: "PUT" });

      updateUser({
        full_name: res.profile.full_name ?? undefined,
        phone: res.profile.phone ?? undefined,
        avatar_url: res.profile.avatar_url ?? undefined,
        description: res.profile.description ?? undefined,
        header_photo: res.profile.header_photo ?? undefined,
        profile_picture: res.profile.profile_picture ?? undefined,
      });
      setLocalProfile({
        description: res.profile.description ?? null,
        header_photo: res.profile.header_photo ?? null,
        profile_picture: res.profile.profile_picture ?? null,
        is_verified: res.profile.is_verified ?? false,
      });
      setIsEditProfileOpen(false);
    } catch (err) {
      setProfileError(err instanceof Error ? err.message : "Failed to save profile.");
    } finally {
      setProfileSaving(false);
    }
  }

  function handleProfilePhotoChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    setProfilePhotoFile(file);
    if (file) setRemoveProfilePhoto(false);
  }

  function handleHeaderPhotoChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    setHeaderPhotoFile(file);
    if (file) setRemoveHeaderPhoto(false);
  }

  if (loading) {
    return (
      <AppShell subtitle="Citizen profile" title="Profile">
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading profile...
        </Card>
      </AppShell>
    );
  }

  if (!user) {
    return (
      <AppShell subtitle="Citizen profile" title="Profile">
        <Card className="py-16 text-center text-on-surface-variant">No active session.</Card>
      </AppShell>
    );
  }

  const displayName = user.full_name || "Citizen";
  const handle = user.email?.split("@")[0] ?? "citizen";
  const postCount = posts.length;
  const profilePhoto = localProfile.profile_picture ?? user.profile_picture ?? user.avatar_url;
  const headerPhoto = (removeHeaderPhoto ? null : headerPhotoPreviewUrl ?? localProfile.header_photo) ?? headerPlaceholderImage;
  const profileDescription = (localProfile.description ?? user.description)?.trim()
    || "This citizen profile is ready to customise. Add a short bio, your contact details, and keep your community updated.";
  const railPosts = posts.slice(0, 2);

  const draftProfilePhoto = removeProfilePhoto
    ? undefined
    : profilePhotoPreviewUrl ?? profilePhoto;
  const draftHeaderPhoto = removeHeaderPhoto
    ? headerPlaceholderImage
    : headerPhotoPreviewUrl ?? localProfile.header_photo ?? headerPlaceholderImage;

  const interactiveProfile = {
    id: user.id,
    name: displayName,
    type: null,
    profile_picture: profilePhoto ?? null,
    profile_photo: profilePhoto ?? null,
    verification_status: localProfile.is_verified ? "approved" : "pending",
  };

  return (
    <AppShell subtitle="Citizen profile" title="Profile">
      <div className="dispatch-profile-page">
        <style>{`
          .dispatch-shell-dark .dispatch-profile-page .text-on-surface { color: #f4eee8 !important; }
          .dispatch-shell-dark .dispatch-profile-page .text-on-surface-variant { color: #c6b8ac !important; }
          .dispatch-shell-dark .dispatch-profile-page .text-outline,
          .dispatch-shell-dark .dispatch-profile-page .text-outline-variant { color: #9d8d80 !important; }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-publish-lane {
            background: #1d1b1a !important;
            box-shadow: rgba(255,255,255,0.04) 0px 1px 0px inset, rgba(0,0,0,0.48) 0px 24px 48px -18px inset !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-surface {
            background: #23211f !important; border-color: #34302b !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-card { box-shadow: 0 5px 15px 0 #00000026 !important; }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-card:hover {
            background: #292624 !important; border-color: #4a433d !important; box-shadow: 0 5px 5px 0 #00000026 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-pill,
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-tab-trigger,
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-action-surface {
            background: #2a2724 !important; border-color: #3b3732 !important; color: #d7c4b7 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-tab-trigger[data-active="true"] {
            background: #4a3025 !important; border-color: #9d654c !important; color: #fff4ec !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-divider { border-color: rgba(255,255,255,0.08) !important; }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-avatar-shell {
            border-color: #23211f !important; background: #2a2724 !important; color: #d59b7c !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-header-overlay {
            background: linear-gradient(180deg, rgba(10,10,10,0.08), rgba(0,0,0,0.38)) !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-readiness-card {
            background: #2a2724 !important; border-color: #3b3732 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-form-input {
            background: #23211f !important; border-color: #3b3732 !important; color: #f4eee8 !important;
          }
        `}</style>

        <div className="grid gap-6 md:grid-cols-[minmax(0,1fr)_18rem] md:items-start xl:grid-cols-[minmax(0,1fr)_20rem]">
          {/* ── Main column ── */}
          <div className={`min-w-0 ${profileLaneEffectClassName}`}>
            <section className={`overflow-hidden rounded-[28px] border text-on-surface ${profileSurfaceClassName} ${profileRaisedCardClassName} ${profileCardHoverClassName}`}>
              {/* Header photo */}
              <div className="relative h-56 overflow-hidden md:h-64">
                <img alt="Profile header" className="h-full w-full object-cover" src={headerPhoto} />
                <div className="dispatch-profile-header-overlay absolute inset-0 bg-[linear-gradient(180deg,rgba(255,252,247,0.06),rgba(56,56,49,0.18))]" />
              </div>

              <div className="relative px-5 pb-6 pt-5 md:px-8">
                <div className="relative flex flex-col gap-5 md:flex-row md:items-start">
                  {/* Avatar */}
                  <div className="dispatch-profile-avatar-shell absolute right-0 top-[-84px] h-28 w-28 overflow-hidden rounded-full border-4 border-[#fff8f3] bg-[#f2e7de] text-[#8f4427] shadow-lg md:h-36 md:w-36">
                    {profilePhoto ? (
                      <img alt={`${displayName} profile`} className="h-full w-full object-cover" src={profilePhoto} />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center">
                        <span className="material-symbols-outlined text-[56px] md:text-[68px]">person</span>
                      </div>
                    )}
                  </div>

                  <div className="w-full">
                    <div className="pr-8 md:pr-36">
                      <div className="flex flex-wrap items-center gap-2">
                        <h2 className="font-headline text-3xl text-on-surface md:text-4xl">{displayName}</h2>
                        {localProfile.is_verified && (
                          <span
                            className="material-symbols-outlined text-[#ff8a1f]"
                            style={{ fontVariationSettings: '"FILL" 1' }}
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
                        <span className="material-symbols-outlined text-[16px]">person</span>
                        Citizen
                      </span>
                      {user.phone && (
                        <span className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-sm ${profilePillClassName}`}>
                          <span className="material-symbols-outlined text-[16px]">call</span>
                          {user.phone}
                        </span>
                      )}
                    </div>

                    <p className="mt-5 text-lg text-on-surface-variant">
                      <span className="font-semibold text-on-surface">{postCount}</span> published post{postCount === 1 ? "" : "s"}
                      <span className="mx-2 text-outline">|</span>
                      <span className="font-semibold text-on-surface">{reportCount}</span> report{reportCount === 1 ? "" : "s"} filed
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
                      <Link to="/citizen/news-feed">
                        <button className={`w-full rounded-xl px-6 py-4 text-base font-semibold ${profileActionSurfaceClassName}`} type="button">
                          Open News Feed
                        </button>
                      </Link>
                      <Link
                        className={`flex items-center justify-center rounded-xl ${profileActionSurfaceClassName}`}
                        to="/citizen"
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
                          index === 0 ? "border-[#a14b2f] bg-[#a14b2f] text-white" : profilePillClassName
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

            <ProfileInteractivePostStack
              cardClassName={`${profileSurfaceClassName} ${profileRaisedCardClassName}`}
              department={interactiveProfile}
              emptyMessage="No published posts yet."
              hoverClassName={profileCardHoverClassName}
              posts={posts}
            />
          </div>

          {/* ── Right sidebar ── */}
          <div className="min-w-0">
            <div className="space-y-6 md:sticky md:top-6">
              {/* Search placeholder */}
              <section className="overflow-hidden rounded-[28px] border border-[#e4c0ae] bg-gradient-to-br from-[#d98d63] via-[#bf6e49] to-[#a86446] p-4 text-white shadow-xl">
                <div className="mx-auto flex max-w-[17rem] items-center justify-center gap-3 rounded-2xl border border-white/10 bg-white/10 px-4 py-3 backdrop-blur-sm">
                  <span className="material-symbols-outlined text-white/75">search</span>
                  <input
                    aria-label="Search profile"
                    className="w-full bg-transparent text-center text-sm text-white outline-none placeholder:text-center placeholder:text-white/55"
                    placeholder="Search posts and activity..."
                    readOnly
                  />
                </div>
              </section>

              {/* Stats card */}
              <section className="overflow-hidden rounded-[28px] border border-[#e4c0ae] bg-gradient-to-br from-[#d98d63] via-[#bf6e49] to-[#a86446] p-5 text-white shadow-xl">
                <div className="flex flex-col items-center gap-4 text-center">
                  <div className="mx-auto max-w-[17rem]">
                    <span className="inline-flex rounded-full border border-white/20 bg-white/10 px-3 py-1 text-[10px] font-bold uppercase tracking-[0.22em] text-white/90">
                      Citizen Profile
                    </span>
                    <h2 className="mt-3 font-headline text-[1.8rem] leading-[1.02]">{displayName}</h2>
                    <p className="mt-3 text-sm leading-relaxed text-white/80">
                      Community member profile — posts, reports, and public activity in one place.
                    </p>
                  </div>
                  <div className="grid w-full max-w-[17rem] gap-3">
                    <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                      <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Published Posts</p>
                      <p className="mt-2 font-headline text-4xl">{String(postCount).padStart(2, "0")}</p>
                      <p className="mt-1 text-xs text-white/70">Profile activity and announcements</p>
                    </div>
                    <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                      <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Reports Filed</p>
                      <p className="mt-2 font-headline text-2xl">{String(reportCount).padStart(2, "0")}</p>
                      <p className="mt-1 text-xs text-white/70">Incident reports submitted</p>
                    </div>
                  </div>
                </div>
              </section>

              {/* Recent activity */}
              <Card className={profileSurfaceClassName}>
                <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                  Recent Activity
                </p>
                <div className="mt-5 space-y-5">
                  {railPosts.length === 0 ? (
                    <div className="dispatch-profile-readiness-card rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                      <p className="text-sm leading-relaxed text-on-surface-variant">
                        Published activity will appear here once you have public posts.
                      </p>
                    </div>
                  ) : (
                    railPosts.map((post) => (
                      <div key={post.id} className="dispatch-profile-readiness-card rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                        <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                          {post.category.replace("_", " ")}
                        </p>
                        <p className="mt-2 text-lg leading-tight text-on-surface">
                          {summarizePostContent(post.content)}
                        </p>
                        <p className="mt-2 text-xs text-outline">{displayName}</p>
                      </div>
                    ))
                  )}
                </div>
              </Card>
            </div>
          </div>
        </div>

        {/* ── Edit Profile Modal ── */}
        {isEditProfileOpen && (
          <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/55 p-4 backdrop-blur-md md:p-8">
            <div className={`dispatch-profile-surface relative flex max-h-[92vh] w-full max-w-3xl flex-col overflow-hidden rounded-[28px] border text-on-surface shadow-[0_24px_60px_rgba(56,56,49,0.18)] ${profileSurfaceClassName}`}>
              {/* Modal header */}
              <div className="dispatch-profile-divider flex items-center gap-4 border-b border-[#e2d1c7] bg-[#fff8f3]/95 px-5 py-4 backdrop-blur-sm md:px-6">
                <button
                  aria-label="Close edit profile"
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
                {/* Header photo editor */}
                <div className={`relative overflow-hidden rounded-[24px] border bg-[#f7efe7] ${profilePillClassName}`}>
                  <div className="relative h-40 overflow-hidden bg-[#efe3da]">
                    <img alt="Header preview" className="h-full w-full object-cover" src={draftHeaderPhoto} />
                  </div>
                  <div className="flex items-center gap-3 px-4 py-3">
                    <span className="text-xs text-on-surface-variant">Header photo</span>
                    <div className="ml-auto flex gap-2">
                      <button
                        className={`rounded-full px-3 py-1.5 text-xs font-semibold ${profileActionSurfaceClassName}`}
                        onClick={() => headerPhotoInputRef.current?.click()}
                        type="button"
                      >
                        {localProfile.header_photo || headerPhotoFile ? "Change" : "Upload"}
                      </button>
                      {(localProfile.header_photo || headerPhotoFile) && (
                        <button
                          className="rounded-full border border-[#dbc6b9] bg-[#f7efe7] px-3 py-1.5 text-xs font-semibold text-[#a14b2f] transition-colors hover:bg-[#f3e7de]"
                          onClick={() => { setRemoveHeaderPhoto(true); setHeaderPhotoFile(null); }}
                          type="button"
                        >
                          Remove
                        </button>
                      )}
                    </div>
                  </div>
                </div>

                {/* Avatar editor */}
                <div className="mt-4 flex items-center gap-4">
                  <div className="h-20 w-20 overflow-hidden rounded-full border-2 border-[#e2d1c7] bg-[#f2e7de] text-[#8f4427]">
                    {draftProfilePhoto ? (
                      <img alt="Avatar preview" className="h-full w-full object-cover" src={draftProfilePhoto} />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center">
                        <span className="material-symbols-outlined text-4xl">person</span>
                      </div>
                    )}
                  </div>
                  <div className="flex gap-2">
                    <button
                      className={`rounded-full px-3 py-1.5 text-xs font-semibold ${profileActionSurfaceClassName}`}
                      onClick={() => profilePhotoInputRef.current?.click()}
                      type="button"
                    >
                      {profilePhoto || profilePhotoFile ? "Change photo" : "Upload photo"}
                    </button>
                    {(profilePhoto || profilePhotoFile) && (
                      <button
                        className="rounded-full border border-[#dbc6b9] bg-[#f7efe7] px-3 py-1.5 text-xs font-semibold text-[#a14b2f] transition-colors hover:bg-[#f3e7de]"
                        onClick={() => { setRemoveProfilePhoto(true); setProfilePhotoFile(null); }}
                        type="button"
                      >
                        Remove
                      </button>
                    )}
                  </div>
                </div>

                {profileError && (
                  <div className="mt-4 rounded-2xl border border-[#d08e77] bg-[#6d4134]/55 px-4 py-3 text-sm text-[#ffe4d7]">
                    {profileError}
                  </div>
                )}

                {/* Form fields */}
                <div className="mt-5 space-y-4">
                  <div>
                    <label className="mb-1.5 block text-xs font-semibold uppercase tracking-widest text-on-surface-variant" htmlFor="citizen-profile-name">
                      Full Name
                    </label>
                    <input
                      className="dispatch-profile-form-input w-full rounded-2xl border border-[#e2d1c7] bg-[#fff8f3] px-4 py-3 text-sm text-on-surface outline-none focus:border-[#a14b2f]"
                      id="citizen-profile-name"
                      type="text"
                      value={profileDraft.full_name}
                      onChange={(e) => setProfileDraft((d) => ({ ...d, full_name: e.target.value }))}
                    />
                  </div>
                  <div>
                    <label className="mb-1.5 block text-xs font-semibold uppercase tracking-widest text-on-surface-variant" htmlFor="citizen-profile-bio">
                      Bio
                    </label>
                    <textarea
                      className="dispatch-profile-form-input min-h-[120px] w-full resize-none rounded-2xl border border-[#e2d1c7] bg-[#fff8f3] px-4 py-3 text-sm text-on-surface outline-none focus:border-[#a14b2f]"
                      id="citizen-profile-bio"
                      value={profileDraft.description}
                      onChange={(e) => setProfileDraft((d) => ({ ...d, description: e.target.value }))}
                    />
                  </div>
                  <div>
                    <label className="mb-1.5 block text-xs font-semibold uppercase tracking-widest text-on-surface-variant" htmlFor="citizen-profile-phone">
                      Phone
                    </label>
                    <input
                      className="dispatch-profile-form-input w-full rounded-2xl border border-[#e2d1c7] bg-[#fff8f3] px-4 py-3 text-sm text-on-surface outline-none focus:border-[#a14b2f]"
                      id="citizen-profile-phone"
                      type="tel"
                      value={profileDraft.phone}
                      onChange={(e) => setProfileDraft((d) => ({ ...d, phone: e.target.value }))}
                    />
                  </div>
                </div>

                <p className="mt-5 text-xs text-on-surface-variant">
                  Photos must be JPEG or PNG, max 5 MB.
                </p>

                <input accept="image/jpeg,image/png" className="hidden" ref={profilePhotoInputRef} type="file" onChange={handleProfilePhotoChange} />
                <input accept="image/jpeg,image/png" className="hidden" ref={headerPhotoInputRef} type="file" onChange={handleHeaderPhotoChange} />
              </div>
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

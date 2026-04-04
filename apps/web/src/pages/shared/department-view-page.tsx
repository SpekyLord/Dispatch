import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";

import {
  ProfileInteractivePostStack,
  type ProfileInteractiveDepartment,
  type ProfileInteractivePost,
} from "@/components/feed/profile-interactive-post-stack";
import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import type { DepartmentInfo } from "@/lib/auth/session-store";

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

function formatHandle(name?: string | null) {
  if (!name) {
    return "department";
  }
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}

function summarizePostContent(content: string, maxLength = 92) {
  const collapsed = content.replace(/\s+/g, " ").trim();
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return `${collapsed.slice(0, maxLength).trimEnd()}...`;
}

export function DepartmentViewPage() {
  const { uploaderId } = useParams<{ uploaderId: string }>();
  const [department, setDepartment] = useState<DepartmentInfo | null>(null);
  const [posts, setPosts] = useState<ProfileInteractivePost[]>([]);
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState(false);

  useEffect(() => {
    if (!uploaderId) {
      return;
    }

    let isActive = true;
    Promise.resolve().then(() => {
      if (!isActive) {
        return;
      }
      setLoading(true);
      setDepartment(null);
      setPosts([]);
    });

    Promise.all([
      apiRequest<{ department: DepartmentInfo }>(`/api/departments/view/${uploaderId}`),
      apiRequest<{ posts: ProfileInteractivePost[] }>(`/api/feed?uploader=${uploaderId}`),
    ])
      .then(([departmentResponse, postsResponse]) => {
        if (!isActive) {
          return;
        }
        setDepartment(departmentResponse.department);
        setPosts(postsResponse.posts);
      })
      .catch(() => {
        if (!isActive) {
          return;
        }
        setDepartment(null);
        setPosts([]);
        setFetchError(true);
      })
      .finally(() => {
        if (isActive) {
          setLoading(false);
        }
      });

    return () => {
      isActive = false;
    };
  }, [uploaderId]);

  if (!uploaderId) {
    return (
      <AppShell subtitle="Publisher profile" title="Department">
        <Card className="py-16 text-center text-on-surface-variant">
          This department profile is not available right now.
        </Card>
      </AppShell>
    );
  }

  if (loading) {
    return (
      <AppShell subtitle="Publisher profile" title="Department">
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading publisher profile...
        </Card>
      </AppShell>
    );
  }

  if (!department) {
    return (
      <AppShell subtitle="Publisher profile" title="Department">
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined mb-2 text-3xl">{fetchError ? "cloud_off" : "info"}</span>
          <p>{fetchError ? "Failed to load department profile." : "This department profile is not available right now."}</p>
          {fetchError && (
            <button
              type="button"
              className="mt-4 rounded-full bg-primary px-6 py-2 text-sm font-medium text-on-primary"
              onClick={() => window.location.reload()}
            >
              Retry
            </button>
          )}
        </Card>
      </AppShell>
    );
  }

  const displayName = department.name || "Department Profile";
  const handle = formatHandle(displayName);
  const profilePhoto = department.profile_picture || department.profile_photo;
  const headerPhoto = department.header_photo || headerPlaceholderImage;
  const postCount = department.post_count ?? posts.length;
  const profileDescription = department.description?.trim()
    ? department.description
    : "This department has not added a public description yet.";
  const profileRailPosts = posts.slice(0, 2);
  const interactiveDepartment: ProfileInteractiveDepartment = {
    id: department.id ?? uploaderId,
    name: department.name ?? displayName,
    type: department.type,
    profile_picture: department.profile_picture,
    profile_photo: department.profile_photo,
    verification_status: department.verification_status,
  };

  return (
    <AppShell subtitle="Publisher profile" title="Department">
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
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-tab-trigger {
            background: #2a2724 !important;
            border-color: #3b3732 !important;
            color: #d7c4b7 !important;
          }
          .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-tab-trigger[data-active="true"] {
            background: #4a3025 !important;
            border-color: #9d654c !important;
            color: #fff4ec !important;
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

        <ProfileInteractivePostStack
          cardClassName={`${profileSurfaceClassName} ${profileRaisedCardClassName}`}
          department={interactiveDepartment}
          emptyMessage="No published announcements yet."
          hoverClassName={profileCardHoverClassName}
          posts={posts}
        />
        </div>

        <div className="min-w-0 md:-mt-20">
          <div className="space-y-6 md:sticky md:top-28 md:max-h-[calc(100vh-8rem)] md:overflow-y-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
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
                    Keep the same utility rail from News Feed while the profile block takes over the center column.
                  </p>
                </div>

                <div className="grid w-full max-w-[17rem] gap-3">
                  <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                    <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Published posts</p>
                    <p className="mt-2 font-headline text-4xl">{String(postCount).padStart(2, "0")}</p>
                    <p className="mt-1 text-xs text-white/70">Live profile activity and announcements</p>
                  </div>
                  <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                    <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Verification</p>
                    <p className="mt-2 font-headline text-2xl capitalize">{department.verification_status}</p>
                    <p className="mt-1 text-xs text-white/70">Publisher profile overview</p>
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
                      Published profile activity will appear here once this department has public posts.
                    </p>
                  </div>
                ) : (
                  profileRailPosts.map((post) => (
                    <div key={post.id} className="dispatch-profile-readiness-card rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                      <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                        {post.category.replace("_", " ")}
                      </p>
                      <p className="mt-2 text-lg leading-tight text-on-surface">
                        {summarizePostContent(post.content)}
                      </p>
                      <p className="mt-2 text-xs text-outline">{department.name}</p>
                    </div>
                  ))
                )}
              </div>
            </Card>
          </div>
        </div>
      </div>
      </div>
    </AppShell>
  );
}

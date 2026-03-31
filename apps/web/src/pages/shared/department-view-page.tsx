import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";
import type { DepartmentInfo } from "@/lib/auth/session-store";

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

const profileTabs = ["Activity", "Announcements", "Bookmarks", "Archive"] as const;
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

export function DepartmentViewPage() {
  const { uploaderId } = useParams<{ uploaderId: string }>();
  const [department, setDepartment] = useState<DepartmentInfo | null>(null);
  const [posts, setPosts] = useState<DepartmentProfilePost[]>([]);
  const [loading, setLoading] = useState(true);

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
      apiRequest<{ posts: DepartmentProfilePost[] }>(`/api/feed?uploader=${uploaderId}`),
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
          <span className="material-symbols-outlined mb-4 block animate-pulse text-4xl">
            hourglass_empty
          </span>
          Loading publisher profile...
        </Card>
      </AppShell>
    );
  }

  if (!department) {
    return (
      <AppShell subtitle="Publisher profile" title="Department">
        <Card className="py-16 text-center text-on-surface-variant">
          This department profile is not available right now.
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

  return (
    <AppShell subtitle="Publisher profile" title="Department">
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
                  <span className="mx-2 text-outline">|</span>
                  <span className="font-semibold capitalize text-on-surface">{department.verification_status}</span> status
                </p>
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
                      <div className="flex items-center gap-2">
                        <span className="material-symbols-outlined">chat_bubble</span>
                        <span className="text-xs font-bold">{post.comment_count ?? 0}</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="material-symbols-outlined">favorite</span>
                        <span className="text-xs font-bold">{post.reaction ?? 0}</span>
                      </div>
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
      </div>
    </AppShell>
  );
}

import { Link } from "react-router-dom";
import { useCallback, useEffect, useMemo, useState } from "react";

import { AttachmentList } from "@/components/feed/attachment-list";
import {
  DepartmentHoverPreview,
  type FeedDepartmentPreview,
} from "@/components/feed/department-hover-preview";
import { DepartmentCreatePostForm } from "@/components/feed/department-create-post-form";
import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type NewsFeedRole = "citizen" | "department" | "municipality";

type RoleCopy = {
  badge: string;
  subtitle: string;
  intro: string;
  searchPlaceholder: string;
  accessTitle: string;
  accessBody: string;
};

type FeedPost = {
  id: string | number;
  uploader: string;
  title: string;
  content: string;
  category: string;
  location?: string | null;
  created_at: string;
  reaction?: number | null;
  liked_by_me?: boolean;
  comment_count?: number | null;
  photos?: string[];
  attachments?: string[];
  department?: FeedDepartmentPreview | null;
};

type CommentThreadItem = {
  id: string | number;
  post_id: string | number;
  user_id: string;
  user_name: string;
  created_at: string;
  comment: string;
};

const roleCopy: Record<NewsFeedRole, RoleCopy> = {
  citizen: {
    badge: "Citizen View",
    subtitle: "Temporary bulletin board",
    intro: "A temporary News feed based on the provided HTML. It gives citizens a quick place to review response updates, preparedness reminders, and agency highlights while we refine the permanent module later.",
    searchPlaceholder: "Search local safety updates...",
    accessTitle: "Read-only access",
    accessBody: "Citizens can browse awareness posts, public advisories, and response updates here, but only departments are allowed to publish News feed content.",
  },
  department: {
    badge: "Department View",
    subtitle: "Temporary operations bulletin",
    intro: "A temporary News feed for response teams to scan public-facing announcements, readiness notes, and cross-agency highlights using the layout from the supplied HTML.",
    searchPlaceholder: "Search response protocols and field updates...",
    accessTitle: "Department publishing",
    accessBody: "Departments are the only role that can publish awareness posts, incident updates, and public News feed announcements from this temporary view.",
  },
  municipality: {
    badge: "Municipality View",
    subtitle: "Temporary regional bulletin",
    intro: "A temporary News feed for municipal users to monitor advisories, readiness themes, and cross-department communication in a single view before we replace it with the final implementation.",
    searchPlaceholder: "Search municipal alerts and coordination notes...",
    accessTitle: "Observation-only access",
    accessBody: "Municipality users can monitor the News feed here, but publishing remains restricted to departments only for awareness posts, reports, and news.",
  },
};

const quickActions = [
  { icon: "location_on", label: "Location tags" },
  { icon: "attach_file", label: "Attachments" },
  { icon: "broadcast_on_personal", label: "Broadcasts" },
] as const;

const categoryStyles: Record<string, { accentClassName: string; icon: string }> = {
  alert: { accentClassName: "bg-[#ffdbd0] text-[#89391e]", icon: "warning" },
  warning: { accentClassName: "bg-[#ffe7cf] text-[#a14b2f]", icon: "error_outline" },
  safety_tip: { accentClassName: "bg-[#dce8f3] text-[#456b86]", icon: "health_and_safety" },
  update: { accentClassName: "bg-[#e6f1e8] text-[#397154]", icon: "info" },
  situational_report: { accentClassName: "bg-[#ece3f5] text-[#6e4c91]", icon: "summarize" },
};

const readinessTopics = [
  {
    category: "Hydrology",
    title: "Flood Mitigation Strategies for Urban Basins",
    meta: "1.2k responders active",
  },
  {
    category: "Logistics",
    title: "Supply Chain Resilience in Seismic Zones",
    meta: "850 agencies coordinated",
  },
  {
    category: "Psychology",
    title: "Mental Fortitude in High-Stress Operations",
    meta: "2.4k personnel enrolled",
  },
] as const;

const footerLinks = ["Standard Ops", "Ethics Policy", "Command Chain"] as const;
const warmPanelClassName = "border-[#efd8d0] bg-[#fff8f3]";
const warmTabClassName = "border border-[#ecd8cf] bg-[#f7efe7] text-[#6f625b]";
const warmActionTabClassName =
  "border border-[#ecd8cf] bg-[#f7efe7] text-[#8a5a40] transition-colors hover:bg-[#f2e7de]";

export function RoleNewsFeedPage({ role }: { role: NewsFeedRole }) {
  const copy = roleCopy[role];
  const canPost = role === "department";
  const accessToken = useSessionStore((state) => state.accessToken);
  const currentUser = useSessionStore((state) => state.user);
  const [posts, setPosts] = useState<FeedPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeCommentPostId, setActiveCommentPostId] = useState<string | number | null>(null);
  const [isCreatePostOpen, setIsCreatePostOpen] = useState(false);
  const [likedPostIds, setLikedPostIds] = useState<Array<string | number>>([]);
  const [bookmarkedPostIds, setBookmarkedPostIds] = useState<Array<string | number>>([]);
  const [reactingPostIds, setReactingPostIds] = useState<Array<string | number>>([]);
  const [comments, setComments] = useState<CommentThreadItem[]>([]);
  const [commentsLoading, setCommentsLoading] = useState(false);
  const [commentDraft, setCommentDraft] = useState("");
  const [commentError, setCommentError] = useState<string | null>(null);
  const [commentSubmitting, setCommentSubmitting] = useState(false);

  const fetchPosts = useCallback((showLoader = true) => {
    if (showLoader) {
      setLoading(true);
    }
    return apiRequest<{ posts: FeedPost[] }>("/api/feed")
      .then((res) => {
        setPosts(res.posts);
        setLikedPostIds(res.posts.filter((post) => post.liked_by_me).map((post) => post.id));
      })
      .catch(() => {
        setPosts([]);
        setLikedPostIds([]);
      })
      .finally(() => {
        if (showLoader) {
          setLoading(false);
        }
      });
  }, []);

  useEffect(() => {
    queueMicrotask(() => {
      void fetchPosts();
    });
  }, [fetchPosts]);

  useEffect(() => {
    const subscription = subscribeToTable(
      "department_feed_posts",
      () => {
        void fetchPosts(false);
      },
      { accessToken },
    );
    return () => subscription.unsubscribe();
  }, [accessToken, fetchPosts]);

  const activeCommentPost = useMemo(
    () => posts.find((post) => post.id === activeCommentPostId) ?? null,
    [activeCommentPostId, posts],
  );

  const fetchComments = useCallback((postId: string | number, showLoader = true) => {
    if (showLoader) {
      setCommentsLoading(true);
    }
    return apiRequest<{ comments: CommentThreadItem[] }>(`/api/feed/${postId}/comments`)
      .then((res) => setComments(res.comments))
      .catch(() => setComments([]))
      .finally(() => {
        if (showLoader) {
          setCommentsLoading(false);
        }
      });
  }, []);

  async function handleReact(postId: string | number) {
    if (reactingPostIds.includes(postId)) {
      return;
    }

    setReactingPostIds((prev) => [...prev, postId]);
    try {
      const response = await apiRequest<{ post: FeedPost }>(`/api/feed/${postId}/reaction`, {
        method: "POST",
      });
      setPosts((prev) =>
        prev.map((post) =>
          post.id === postId
            ? {
                ...post,
                reaction: response.post.reaction ?? 0,
                liked_by_me: response.post.liked_by_me ?? false,
              }
            : post,
        ),
      );
      setLikedPostIds((prev) =>
        response.post.liked_by_me
          ? prev.includes(postId)
            ? prev
            : [...prev, postId]
          : prev.filter((id) => id !== postId),
      );
    } finally {
      setReactingPostIds((prev) => prev.filter((id) => id !== postId));
    }
  }

  function toggleBookmarked(postId: string | number) {
    setBookmarkedPostIds((prev) =>
      prev.includes(postId) ? prev.filter((id) => id !== postId) : [...prev, postId],
    );
  }

  async function handleSubmitComment() {
    if (!activeCommentPostId) {
      return;
    }
    if (!commentDraft.trim()) {
      setCommentError("Comment is required.");
      return;
    }

    setCommentSubmitting(true);
    setCommentError(null);
    try {
      await apiRequest<{ comment: CommentThreadItem }>(`/api/feed/${activeCommentPostId}/comments`, {
        method: "POST",
        body: JSON.stringify({ comment: commentDraft.trim() }),
      });
      setCommentDraft("");
      await Promise.all([fetchComments(activeCommentPostId, false), fetchPosts(false)]);
    } catch (error) {
      setCommentError(error instanceof Error ? error.message : "Failed to publish comment.");
    } finally {
      setCommentSubmitting(false);
    }
  }

  useEffect(() => {
    if (!activeCommentPostId) {
      setComments([]);
      setCommentDraft("");
      setCommentError(null);
      return;
    }

    void fetchComments(activeCommentPostId);
  }, [activeCommentPostId, fetchComments]);

  useEffect(() => {
    if (!activeCommentPostId) {
      return;
    }

    const subscription = subscribeToTable(
      "department_feed_comment",
      () => {
        void fetchComments(activeCommentPostId, false);
        void fetchPosts(false);
      },
      { accessToken, filter: `post_id=eq.${activeCommentPostId}` },
    );

    return () => subscription.unsubscribe();
  }, [accessToken, activeCommentPostId, fetchComments, fetchPosts]);

  return (
    <AppShell subtitle={copy.subtitle} title="News Feed">
      <div className="space-y-8">
        <section className="overflow-hidden rounded-[28px] border border-[#d8b7aa] bg-gradient-to-br from-[#a14b2f] via-[#8f4427] to-[#5f5e5c] p-6 text-white shadow-xl">
          <div className="flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between">
            <div className="max-w-3xl">
              <span className="inline-flex rounded-full border border-white/20 bg-white/10 px-3 py-1 text-[11px] font-bold uppercase tracking-[0.24em] text-white/90">
                {copy.badge}
              </span>
              <h2 className="mt-4 font-headline text-3xl lg:text-4xl">ResilienceHub Temporary News Desk</h2>
              <p className="mt-3 max-w-2xl text-sm leading-relaxed text-white/80">
                {copy.intro}
              </p>
              <div className="mt-5 flex items-center gap-3 rounded-2xl border border-white/10 bg-white/10 px-4 py-3 backdrop-blur-sm">
                <span className="material-symbols-outlined text-white/75">search</span>
                <input
                  aria-label="Temporary news search"
                  className="w-full bg-transparent text-sm text-white outline-none placeholder:text-white/55"
                  placeholder={copy.searchPlaceholder}
                  readOnly
                />
              </div>
            </div>

            <div className="grid gap-3 sm:grid-cols-2 xl:min-w-[360px]">
              <div className="rounded-2xl border border-white/10 bg-white/10 p-4 backdrop-blur-sm">
                <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">
                  Active advisories
                </p>
                <p className="mt-2 font-headline text-4xl">{loading ? "..." : String(posts.length).padStart(2, "0")}</p>
                <p className="mt-1 text-xs text-white/70">Live posts from department feed</p>
              </div>
              <div className="rounded-2xl border border-white/10 bg-white/10 p-4 backdrop-blur-sm">
                <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">
                  Coordination mode
                </p>
                <p className="mt-2 font-headline text-2xl">Steady Watch</p>
                <p className="mt-1 text-xs text-white/70">Preparedness bulletin enabled</p>
              </div>
            </div>
          </div>
        </section>

        <div className="grid gap-6 xl:grid-cols-12">
          <div className="space-y-6 xl:col-span-8">
            <Card className={warmPanelClassName}>
              <div className="flex flex-col gap-4 md:flex-row md:items-start">
                <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[#ffdbd0] text-[#89391e]">
                  <span className="material-symbols-outlined">campaign</span>
                </div>
                  <div className="flex-1">
                    <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                      {canPost ? "Department composer" : "Posting permissions"}
                    </p>

                    {canPost ? (
                      <>
                        <div className="mt-4 rounded-[28px] border border-[#ecd8cf] bg-[#fff8f3] px-4 py-4">
                          <div className="flex flex-col gap-4 md:flex-row md:items-center">
                            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[#ffefe6] text-[#a14b2f]">
                              <span className="material-symbols-outlined">edit_square</span>
                            </div>
                            <button
                              type="button"
                              onClick={() => setIsCreatePostOpen(true)}
                              className="min-h-[56px] flex-1 rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-5 text-left text-lg text-[#7a6b63] transition-colors hover:bg-[#f2e7de] hover:text-[#5f4f46]"
                            >
                              Anything urgent to share?
                            </button>
                            <Button
                              type="button"
                              variant="secondary"
                              className="min-w-[96px] self-end md:self-auto"
                              onClick={() => setIsCreatePostOpen(true)}
                            >
                              Post
                            </Button>
                          </div>

                          <div className="mt-4 flex flex-wrap gap-2 border-t border-[#ecd8cf] pt-4">
                            {quickActions.map((action) => (
                              <span
                                key={action.label}
                                className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-xs font-medium ${warmTabClassName}`}
                              >
                              <span className="material-symbols-outlined text-[16px]">{action.icon}</span>
                                {action.label}
                              </span>
                            ))}
                          </div>
                        </div>
                      </>
                    ) : (
                      <>
                        <h3 className="mt-3 text-2xl text-on-surface">{copy.accessTitle}</h3>
                        <p className="mt-3 max-w-3xl text-sm leading-relaxed text-on-surface-variant">
                          {copy.accessBody}
                        </p>
                        <div className="mt-4 rounded-2xl border border-[#ecd8cf] bg-white px-4 py-4">
                        <div className="flex items-start gap-3">
                          <span className="material-symbols-outlined text-[#a14b2f]">lock</span>
                          <div>
                            <p className="text-sm font-semibold text-on-surface">Publishing is restricted</p>
                            <p className="mt-1 text-sm leading-relaxed text-on-surface-variant">
                              Only department accounts can create awareness posts, reports, and news entries in this News feed.
                            </p>
                          </div>
                        </div>
                        </div>
                      </>
                    )}
                  </div>
                </div>
              </Card>

            <div className="space-y-5">
              {loading ? (
                <Card className={`${warmPanelClassName} py-16 text-center text-on-surface-variant`}>
                  <span className="material-symbols-outlined text-4xl mb-4 block animate-pulse">hourglass_empty</span>
                  Loading news feed...
                </Card>
              ) : posts.length === 0 ? (
                <Card className={`${warmPanelClassName} py-16 text-center`}>
                  <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">campaign</span>
                  <p className="text-on-surface-variant">No department news posts yet.</p>
                </Card>
              ) : (
                posts.map((post) => {
                  const categoryStyle = categoryStyles[post.category] ?? {
                    accentClassName: "bg-[#f0eee5] text-[#5f5e5c]",
                    icon: "article",
                  };
                  const publisherPath = `/departments/${post.uploader}`;

                  return (
                    <Card key={post.id} className={`${warmPanelClassName} relative overflow-visible`}>
                      <article className="space-y-5">
                        <div className="flex items-start gap-3">
                          <DepartmentHoverPreview
                            className="shrink-0"
                            department={post.department}
                            panelClassName="left-1/2 -translate-x-1/2"
                            profilePath={publisherPath}
                          >
                            <Link
                              aria-label={`Open ${post.department?.name ?? "department"} profile`}
                              className={`flex h-10 w-10 items-center justify-center overflow-hidden rounded-full transition-transform duration-200 ease-out group-hover/publisher:scale-[1.04] ${categoryStyle.accentClassName}`}
                              to={publisherPath}
                            >
                              {post.department?.profile_picture ? (
                                <img
                                  alt={`${post.department.name} profile`}
                                  className="h-full w-full object-cover"
                                  src={post.department.profile_picture}
                                />
                              ) : (
                                <span className="material-symbols-outlined">{categoryStyle.icon}</span>
                              )}
                            </Link>
                          </DepartmentHoverPreview>
                          <div className="min-w-0 flex-1">
                            <DepartmentHoverPreview
                              className="inline-flex max-w-full"
                              department={post.department}
                              panelClassName="left-1/2 -translate-x-1/2"
                              profilePath={publisherPath}
                            >
                              <Link className="inline-flex min-w-0 flex-col items-start" to={publisherPath}>
                                <p className="text-sm font-semibold text-on-surface transition-colors duration-200 ease-out group-hover/publisher:text-[#a14b2f]">
                                  {post.department?.name ?? "Department Update"}
                                </p>
                                <p className="text-[11px] font-bold uppercase tracking-widest text-outline transition-opacity duration-200 ease-out group-hover/publisher:opacity-55">
                                  {new Date(post.created_at).toLocaleString()}
                                </p>
                              </Link>
                            </DepartmentHoverPreview>
                          </div>
                          <div className="ml-auto flex flex-wrap items-center justify-end gap-2">
                            <span className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${warmTabClassName}`}>
                              {post.category.replace("_", " ")}
                            </span>
                            <Link
                              className={`inline-flex items-center gap-2 rounded-full px-3 py-1 font-medium ${warmActionTabClassName}`}
                              to={`/feed/${post.id}`}
                            >
                              <span className="material-symbols-outlined text-[18px]">open_in_new</span>
                              Open full announcement
                            </Link>
                          </div>
                        </div>

                        <div className="space-y-4 pl-0 md:pl-12">
                          <div>
                            <h3 className="text-2xl text-on-surface">{post.title}</h3>
                            {post.location && (
                              <p className={`mt-2 inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs ${warmTabClassName}`}>
                                <span className="material-symbols-outlined text-[16px]">location_on</span>
                                {post.location}
                              </p>
                            )}
                          </div>

                          <p className="text-base leading-relaxed text-on-surface-variant whitespace-pre-wrap">
                            {post.content}
                          </p>

                          {post.photos && post.photos.length > 0 && (
                            <div className="grid gap-3 sm:grid-cols-2">
                              {post.photos.map((url, index) => (
                                <div key={`${post.id}-photo-${index}`} className="overflow-hidden rounded-2xl border border-outline-variant/10">
                                  <img src={url} alt={`${post.title} photo ${index + 1}`} className="h-48 w-full object-cover" />
                                </div>
                              ))}
                            </div>
                          )}

                          {post.attachments && post.attachments.length > 0 && (
                            <div className="rounded-2xl border border-[#ecd8cf] bg-[#fff8f3] px-4 py-1">
                              <AttachmentList attachments={post.attachments} />
                            </div>
                          )}

                          <div className="flex items-center justify-between border-t border-outline-variant/10 pt-4 text-outline">
                            <div className="flex items-center gap-8">
                              <button
                                className="flex items-center gap-2 transition-colors hover:text-[#a14b2f]"
                                type="button"
                                onClick={() => void handleReact(post.id)}
                                disabled={reactingPostIds.includes(post.id)}
                              >
                                <span
                                  className="material-symbols-outlined"
                                  style={{ fontVariationSettings: likedPostIds.includes(post.id) ? "\"FILL\" 1" : "\"FILL\" 0" }}
                                >
                                  favorite
                                </span>
                                <span className="text-xs font-bold uppercase tracking-widest">
                                  {post.reaction ?? 0}
                                </span>
                              </button>
                              <button
                                className="flex items-center gap-2 text-on-surface transition-colors hover:text-[#a14b2f]"
                                type="button"
                                onClick={() => setActiveCommentPostId(post.id)}
                              >
                                <span className="material-symbols-outlined">chat_bubble</span>
                                <span className="text-xs font-bold uppercase tracking-widest">
                                  {post.comment_count ?? 0}
                                </span>
                              </button>
                            </div>
                            <button
                              className="transition-colors hover:text-on-surface"
                              type="button"
                              onClick={() => toggleBookmarked(post.id)}
                              title="Bookmark announcement"
                            >
                              <span
                                className="material-symbols-outlined"
                                style={{ fontVariationSettings: bookmarkedPostIds.includes(post.id) ? "\"FILL\" 1" : "\"FILL\" 0" }}
                              >
                                bookmark
                              </span>
                            </button>
                          </div>
                        </div>
                      </article>
                    </Card>
                  );
                })
              )}
            </div>
          </div>

          <div className="space-y-6 xl:col-span-4">
            <Card className={warmPanelClassName}>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                Active Readiness
              </p>
              <div className="mt-5 space-y-5">
                {readinessTopics.map((topic) => (
                  <div
                    key={topic.title}
                    className="group cursor-default rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4 transition-shadow hover:shadow-sm"
                  >
                    <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                      {topic.category}
                    </p>
                    <p className="mt-2 text-lg leading-tight text-on-surface transition-colors group-hover:text-[#a14b2f]">
                      {topic.title}
                    </p>
                    <p className="mt-2 text-xs text-outline">{topic.meta}</p>
                  </div>
                ))}
              </div>
            </Card>

            <Card className={warmPanelClassName}>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                Training Hub
              </p>
              <h3 className="mt-3 text-2xl text-on-surface">NIMS Webinar Registration</h3>
              <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">
                Register for Friday&apos;s preparedness webinar to keep this temporary News feed aligned
                with the project&apos;s response coordination goals.
              </p>
              <Button type="button" variant="secondary" className="mt-5 w-full">
                Register Now
              </Button>
            </Card>

            <Card className={warmPanelClassName}>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                Quick Access
              </p>
              <div className="mt-4 flex flex-wrap gap-2">
                {footerLinks.map((link) => (
                  <span
                    key={link}
                    className={`rounded-full px-3 py-2 text-xs ${warmTabClassName}`}
                  >
                    {link}
                  </span>
                ))}
              </div>
              <p className="mt-4 text-xs text-outline">
                Temporary News feed page added from the supplied HTML layout.
              </p>
            </Card>
          </div>
        </div>
      </div>

      {activeCommentPost && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div className="relative flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl border border-[#efd8d0] bg-[#fff8f3] shadow-[0_20px_40px_rgba(56,56,49,0.12)]">
              {(() => {
                const publisherPath = `/departments/${activeCommentPost.uploader}`;
                return (
              <div className="flex items-center gap-4 border-b border-[#ecd8cf] bg-[#fff8f3]/95 px-8 py-6 backdrop-blur-sm">
                <DepartmentHoverPreview
                  className="shrink-0"
                  department={activeCommentPost.department}
                  panelClassName="left-1/2 -translate-x-1/2"
                  profilePath={publisherPath}
                >
                  <Link
                    aria-label={`Open ${activeCommentPost.department?.name ?? "department"} profile`}
                    className="flex h-12 w-12 items-center justify-center overflow-hidden rounded-full bg-surface-container-highest text-[#a14b2f] transition-transform duration-200 ease-out group-hover/publisher:scale-[1.04]"
                    onClick={() => setActiveCommentPostId(null)}
                    to={publisherPath}
                  >
                    {activeCommentPost.department?.profile_picture ? (
                      <img
                        alt={`${activeCommentPost.department.name} profile`}
                        className="h-full w-full object-cover"
                        src={activeCommentPost.department.profile_picture}
                      />
                    ) : (
                      <span className="material-symbols-outlined">campaign</span>
                    )}
                  </Link>
                </DepartmentHoverPreview>
                <DepartmentHoverPreview
                  className="inline-flex min-w-0 max-w-full"
                  department={activeCommentPost.department}
                  panelClassName="left-1/2 -translate-x-1/2"
                  profilePath={publisherPath}
                >
                  <Link
                    className="inline-flex min-w-0 flex-col items-start"
                    onClick={() => setActiveCommentPostId(null)}
                    to={publisherPath}
                  >
                    <p className="text-base font-semibold text-on-surface transition-colors duration-200 ease-out group-hover/publisher:text-[#a14b2f]">
                      {activeCommentPost.department?.name ?? "Department Update"}
                    </p>
                    <p className="text-[10px] font-bold uppercase tracking-widest text-outline transition-opacity duration-200 ease-out group-hover/publisher:opacity-55">
                      {new Date(activeCommentPost.created_at).toLocaleString()}
                    </p>
                  </Link>
                </DepartmentHoverPreview>
                <span className={`ml-auto rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${warmTabClassName}`}>
                  {activeCommentPost.category.replace("_", " ")}
                </span>
                <button
                  className={`rounded-full p-2 transition-colors hover:text-on-surface ${warmTabClassName}`}
                  type="button"
                  onClick={() => setActiveCommentPostId(null)}
                >
                  <span className="material-symbols-outlined">close</span>
                </button>
              </div>
                );
              })()}

            <div className="min-h-0 overflow-y-auto">
              <article className="p-8 pt-6">
                <div className="space-y-5">
                  <div>
                    <h3 className="text-3xl text-on-surface">{activeCommentPost.title}</h3>
                    {activeCommentPost.location && (
                      <p className={`mt-3 inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs ${warmTabClassName}`}>
                        <span className="material-symbols-outlined text-[16px]">location_on</span>
                        {activeCommentPost.location}
                      </p>
                    )}
                  </div>

                  <p className="text-[1.125rem] leading-[1.6] text-on-surface whitespace-pre-wrap">
                    {activeCommentPost.content}
                  </p>

                  {activeCommentPost.photos && activeCommentPost.photos.length > 0 && (
                    <div className="overflow-hidden rounded border border-outline-variant/10">
                      <img
                        src={activeCommentPost.photos[0]}
                        alt={activeCommentPost.title}
                        className="block h-auto w-full"
                      />
                    </div>
                  )}

                  <div className="flex items-center justify-between border-y border-outline-variant/10 py-4">
                    <div className="flex items-center gap-8">
                      <button
                        className="group flex items-center gap-2 text-on-surface-variant transition-colors hover:text-[#a14b2f]"
                        type="button"
                        onClick={() => void handleReact(activeCommentPost.id)}
                        disabled={reactingPostIds.includes(activeCommentPost.id)}
                      >
                        <span
                          className="material-symbols-outlined"
                          style={{ fontVariationSettings: likedPostIds.includes(activeCommentPost.id) ? "\"FILL\" 1" : "\"FILL\" 0" }}
                        >
                          favorite
                        </span>
                        <span className="text-xs font-bold uppercase tracking-widest">
                          {activeCommentPost.reaction ?? 0}
                        </span>
                      </button>
                      <button className="group flex items-center gap-2 text-on-surface transition-colors" type="button">
                        <span className="material-symbols-outlined">chat_bubble</span>
                        <span className="text-xs font-bold uppercase tracking-widest">
                          {activeCommentPost.comment_count ?? comments.length}
                        </span>
                      </button>
                    </div>
                    <button className="text-on-surface-variant transition-colors hover:text-on-surface" type="button">
                      <span className="material-symbols-outlined">bookmark</span>
                    </button>
                  </div>
                </div>

              </article>

              <section className="bg-[#f7efe7] px-8 py-10">
                <h4 className="mb-8 text-xs font-bold uppercase tracking-widest text-on-surface-variant">
                  Response Thread
                </h4>

                <div className="mb-10 flex gap-4">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-surface-container-highest">
                    <span className="material-symbols-outlined text-on-surface-variant">person</span>
                  </div>
                  <div className="relative flex-grow">
                    <textarea
                      value={commentDraft}
                      onChange={(event) => setCommentDraft(event.target.value)}
                      className="w-full resize-none rounded-lg border-none bg-surface-container-highest p-3 text-sm placeholder:text-on-surface-variant/50 focus:ring-1 focus:ring-primary/20"
                      placeholder="Add your perspective..."
                      rows={1}
                    />
                    <button
                      className="absolute right-3 top-2.5 text-[#a14b2f] transition-colors hover:text-[#914024]"
                      type="button"
                      onClick={() => void handleSubmitComment()}
                      disabled={commentSubmitting}
                    >
                      <span className="material-symbols-outlined text-xl">send</span>
                    </button>
                  </div>
                </div>

                {commentError && (
                  <div className="mb-6 rounded-md border border-error/20 bg-error-container/20 px-4 py-3 text-sm text-error">
                    {commentError}
                  </div>
                )}

                <div className="space-y-8">
                  {commentsLoading ? (
                    <p className="text-sm text-on-surface-variant">Loading comments...</p>
                  ) : comments.length === 0 ? (
                    <p className="text-sm text-on-surface-variant">No comments yet. Start the conversation.</p>
                  ) : comments.map((comment) => (
                    <div key={comment.id} className="flex gap-4">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-surface-container-highest">
                        <span className="material-symbols-outlined text-on-surface-variant">person</span>
                      </div>
                      <div className="space-y-1">
                        <div className="flex items-baseline gap-3">
                          <span className="text-sm font-semibold text-on-surface">{comment.user_name}</span>
                          <span className="text-[10px] font-medium text-on-surface-variant/60">
                            {new Date(comment.created_at).toLocaleString()}
                          </span>
                        </div>
                        <p className="text-sm leading-relaxed text-on-surface">{comment.comment}</p>
                        <div className="flex gap-4 pt-1">
                          <button className="text-[10px] font-bold uppercase tracking-widest text-outline transition-colors hover:text-[#a14b2f]" type="button">
                            Like
                          </button>
                          <button className="text-[10px] font-bold uppercase tracking-widest text-outline transition-colors hover:text-[#a14b2f]" type="button">
                            Reply
                          </button>
                        </div>
                      </div>
                    </div>
                  ))}

                  <div className="flex justify-center pt-4 text-[10px] font-bold uppercase tracking-widest text-outline">
                    {`${comments.length} comment${comments.length === 1 ? "" : "s"}`}
                    {currentUser ? ` • signed in as ${currentUser.full_name ?? currentUser.email}` : ""}
                  </div>
                </div>
              </section>
            </div>
          </div>
        </div>
      )}

      {canPost && isCreatePostOpen && (
        <div className="fixed inset-0 z-[75] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div className="relative flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl border border-[#efd8d0] bg-[#fff8f3] shadow-[0_20px_40px_rgba(56,56,49,0.12)]">
            <div className="flex items-center gap-4 border-b border-[#ecd8cf] bg-[#fff8f3]/95 px-8 py-6 backdrop-blur-sm">
                <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[#ffdbd0] text-[#89391e]">
                  <span className="material-symbols-outlined">edit_square</span>
                </div>
                <div className="min-w-0">
                  <p className="text-base font-semibold text-on-surface">Department Command Desk</p>
                  <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                    Publish from the temporary news feed
                  </p>
                </div>
                <button
                  aria-label="Close create post modal"
                  className={`ml-auto rounded-full p-2 text-on-surface-variant transition-colors hover:text-on-surface ${warmTabClassName}`}
                  type="button"
                  onClick={() => setIsCreatePostOpen(false)}
                >
                  <span className="material-symbols-outlined">close</span>
                </button>
              </div>

            <div className="min-h-0 overflow-y-auto">
              <article className="p-8 pt-6">
                <div className="mb-8">
                  <p className="font-headline text-3xl leading-tight text-on-surface">
                    Create a public announcement without leaving the feed.
                  </p>
                  <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">
                    This keeps the same publishing flow, uploads, and location checks, but places the form in the temporary modal layout from the supplied reference.
                  </p>
                </div>

                <DepartmentCreatePostForm
                  onCancel={() => setIsCreatePostOpen(false)}
                  onSuccess={async () => {
                    setIsCreatePostOpen(false);
                    await fetchPosts(false);
                  }}
                />
              </article>
            </div>
          </div>
        </div>
      )}
    </AppShell>
  );
}

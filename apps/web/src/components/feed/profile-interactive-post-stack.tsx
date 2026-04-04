import { useEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent, type MouseEvent } from "react";

import {
  AssessmentPostSummary,
  type FeedAssessmentDetails,
  isAssessmentPost,
} from "@/components/feed/assessment-post-summary";
import { AttachmentList } from "@/components/feed/attachment-list";
import { DepartmentHoverPreview, type FeedDepartmentPreview } from "@/components/feed/department-hover-preview";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";

export type ProfileInteractivePost = {
  id: string | number;
  uploader?: string;
  title: string;
  content: string;
  category: string;
  post_kind?: "standard" | "assessment";
  assessment_details?: FeedAssessmentDetails | null;
  created_at: string;
  reaction?: number | null;
  liked_by_me?: boolean;
  comment_count?: number | null;
  photos?: string[];
  attachments?: string[];
  location?: string | null;
};

export type ProfileInteractiveDepartment = {
  id: string;
  name: string;
  type?: string | null;
  profile_picture?: string | null;
  profile_photo?: string | null;
  verification_status?: string | null;
};

type CommentThreadItem = {
  id: string | number;
  post_id: string | number;
  user_id: string;
  user_name: string;
  created_at: string;
  comment: string;
};

type ActiveImageViewer = {
  title: string;
  photos: string[];
  index: number;
} | null;

type ProfileInteractivePostStackProps = {
  posts: ProfileInteractivePost[];
  department: ProfileInteractiveDepartment;
  cardClassName: string;
  hoverClassName: string;
  emptyMessage: string;
};

const categoryStyles: Record<string, { accentClassName: string; icon: string }> = {
  alert: { accentClassName: "bg-[#ffdbd0] text-[#89391e]", icon: "warning" },
  warning: { accentClassName: "bg-[#ffe7cf] text-[#a14b2f]", icon: "error_outline" },
  safety_tip: { accentClassName: "bg-[#dce8f3] text-[#456b86]", icon: "health_and_safety" },
  update: { accentClassName: "bg-[#e6f1e8] text-[#397154]", icon: "info" },
  situational_report: { accentClassName: "bg-[#ece3f5] text-[#6e4c91]", icon: "summarize" },
};

const heartOutlinePath =
  "M17.5,1.917a6.4,6.4,0,0,0-5.5,3.3,6.4,6.4,0,0,0-5.5-3.3A6.8,6.8,0,0,0,0,8.967c0,4.547,4.786,9.513,8.8,12.88a4.974,4.974,0,0,0,6.4,0C19.214,18.48,24,13.514,24,8.967A6.8,6.8,0,0,0,17.5,1.917Zm-3.585,18.4a2.973,2.973,0,0,1-3.83,0C4.947,16.006,2,11.87,2,8.967a4.8,4.8,0,0,1,4.5-5.05A4.8,4.8,0,0,1,11,8.967a1,1,0,0,0,2,0,4.8,4.8,0,0,1,4.5-5.05A4.8,4.8,0,0,1,22,8.967C22,11.87,19.053,16.006,13.915,20.313Z";
const heartFilledPath =
  "M17.5,1.917a6.4,6.4,0,0,0-5.5,3.3,6.4,6.4,0,0,0-5.5-3.3A6.8,6.8,0,0,0,0,8.967c0,4.547,4.786,9.513,8.8,12.88a4.974,4.974,0,0,0,6.4,0C19.214,18.48,24,13.514,24,8.967A6.8,6.8,0,0,0,17.5,1.917Z";
const bookmarkPath =
  "M27 4v27a1 1 0 0 1-1.625.781L16 24.281l-9.375 7.5A1 1 0 0 1 5 31V4a4 4 0 0 1 4-4h14a4 4 0 0 1 4 4z";

function getFeedPhotoGridTileClassName(index: number, totalPhotos: number) {
  if (totalPhotos === 2) {
    return "aspect-[1.06/1]";
  }
  if (totalPhotos === 3) {
    return index === 0 ? "row-span-2 aspect-[0.92/1.08]" : "aspect-[1/0.82]";
  }
  return "aspect-[1/0.86]";
}

function parseCoordinateLocation(location?: string | null) {
  if (!location) {
    return null;
  }

  const match = location.trim().match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
  if (!match) {
    return null;
  }

  const lat = Number(match[1]);
  const lng = Number(match[2]);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return null;
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return null;
  }

  return { lat, lng };
}

function formatCoordinateFallback(location?: string | null) {
  const parsed = parseCoordinateLocation(location);
  if (!parsed) {
    return location?.trim() ?? "";
  }
  return `${parsed.lat.toFixed(4)}, ${parsed.lng.toFixed(4)}`;
}

function summarizeResolvedLocation(data: {
  name?: string;
  address?: Record<string, string | undefined>;
  display_name?: string;
}) {
  const address = data.address ?? {};
  const primary =
    data.name ||
    address.amenity ||
    address.building ||
    address.tourism ||
    address.leisure ||
    address.road ||
    address.suburb ||
    address.neighbourhood ||
    address.village ||
    address.town ||
    address.city ||
    address.municipality;
  const locality =
    address.city ||
    address.town ||
    address.municipality ||
    address.village ||
    address.county ||
    address.state;
  const country = address.country;

  return [primary, locality, country]
    .filter((value, index, values) => Boolean(value) && values.indexOf(value) === index)
    .join(", ");
}

function AnimatedHeartIcon({ liked }: { liked: boolean }) {
  return (
    <span className="relative flex h-6 w-6 items-center justify-center">
      <svg
        aria-hidden="true"
        className={liked ? "h-5 w-5 fill-current opacity-0" : "h-5 w-5 fill-current opacity-100"}
        viewBox="0 0 24 24"
      >
        <path d={heartOutlinePath} />
      </svg>
      {liked ? (
        <>
          <svg
            aria-hidden="true"
            className="dispatch-heart-filled absolute h-5 w-5 fill-current text-[#d97757]"
            viewBox="0 0 24 24"
          >
            <path d={heartFilledPath} />
          </svg>
          <svg aria-hidden="true" className="dispatch-heart-burst absolute h-10 w-10" viewBox="0 0 100 100">
            <polygon points="10,10 20,20" />
            <polygon points="10,50 20,50" />
            <polygon points="20,80 30,70" />
            <polygon points="90,10 80,20" />
            <polygon points="90,50 80,50" />
            <polygon points="80,80 70,70" />
          </svg>
        </>
      ) : null}
    </span>
  );
}

function AnimatedBookmarkIcon({ bookmarked, animate }: { bookmarked: boolean; animate: boolean }) {
  return (
    <span className="relative flex h-6 w-6 items-center justify-center">
      <svg
        aria-hidden="true"
        className={animate ? "dispatch-bookmark-active h-5 w-5 transition-colors duration-200" : "h-5 w-5 transition-colors duration-200"}
        viewBox="0 0 32 32"
      >
        <path d={bookmarkPath} fill={bookmarked ? "#d97757" : "currentColor"} />
      </svg>
      {animate ? (
        <>
          <span className="dispatch-bookmark-ring absolute rounded-full border border-[#d97757]" />
          <span className="dispatch-bookmark-spark absolute" />
        </>
      ) : null}
    </span>
  );
}

export function ProfileInteractivePostStack({
  posts,
  department,
  cardClassName,
  hoverClassName,
  emptyMessage,
}: ProfileInteractivePostStackProps) {
  const [localPosts, setLocalPosts] = useState<ProfileInteractivePost[]>(posts);
  const [activeCommentPostId, setActiveCommentPostId] = useState<string | number | null>(null);
  const [likedPostIds, setLikedPostIds] = useState<Array<string | number>>([]);
  const [bookmarkedPostIds, setBookmarkedPostIds] = useState<Array<string | number>>([]);
  const [bookmarkAnimatingPostIds, setBookmarkAnimatingPostIds] = useState<Array<string | number>>([]);
  const [reactingPostIds, setReactingPostIds] = useState<Array<string | number>>([]);
  const [postPhotoIndices, setPostPhotoIndices] = useState<Record<string, number>>({});
  const [comments, setComments] = useState<CommentThreadItem[]>([]);
  const [commentsLoading, setCommentsLoading] = useState(false);
  const [commentDraft, setCommentDraft] = useState("");
  const [commentSubmitting, setCommentSubmitting] = useState(false);
  const [commentError, setCommentError] = useState<string | null>(null);
  const [commentModalOrigin, setCommentModalOrigin] = useState({ x: 0, y: 0 });
  const [activeImageViewer, setActiveImageViewer] = useState<ActiveImageViewer>(null);
  const [resolvedLocations, setResolvedLocations] = useState<Record<string, string>>({});
  const resolvingLocationsRef = useRef(new Set<string>());

  useEffect(() => {
    setLocalPosts(posts);
    setLikedPostIds(posts.filter((post) => post.liked_by_me).map((post) => post.id));
  }, [posts]);

  const activeCommentPost = useMemo(
    () => localPosts.find((post) => post.id === activeCommentPostId) ?? null,
    [activeCommentPostId, localPosts],
  );
  const activeCommentLocationLabel = activeCommentPost?.location
    ? resolvedLocations[activeCommentPost.location.trim()] ?? formatCoordinateFallback(activeCommentPost.location)
    : null;

  function getPhotoIndex(postId: string | number, photoCount: number) {
    if (photoCount <= 0) {
      return 0;
    }
    return Math.min(postPhotoIndices[String(postId)] ?? 0, photoCount - 1);
  }

  function shiftPostPhoto(postId: string | number, photoCount: number, direction: "next" | "prev") {
    if (photoCount <= 1) {
      return;
    }
    setPostPhotoIndices((prev) => {
      const current = prev[String(postId)] ?? 0;
      const next = direction === "next" ? (current + 1) % photoCount : (current - 1 + photoCount) % photoCount;
      return { ...prev, [String(postId)]: next };
    });
  }

  function openCommentModal(postId: string | number, button?: HTMLElement | null) {
    if (button) {
      const rect = button.getBoundingClientRect();
      setCommentModalOrigin({
        x: rect.left + rect.width / 2 - window.innerWidth / 2,
        y: rect.top + rect.height / 2 - window.innerHeight / 2,
      });
    } else {
      setCommentModalOrigin({ x: 0, y: 0 });
    }
    setActiveCommentPostId(postId);
  }

  function handlePostCardActivate(
    event: MouseEvent<HTMLElement> | KeyboardEvent<HTMLElement>,
    postId: string | number,
  ) {
    const target = event.target instanceof Element ? event.target : null;
    if (target?.closest("button, a, input, textarea, select, label, details, summary")) {
      return;
    }
    if ("key" in event && event.key && event.key !== "Enter" && event.key !== " ") {
      return;
    }
    if ("key" in event && event.key) {
      event.preventDefault();
    }
    openCommentModal(postId, event.currentTarget);
  }

  function openImageViewer(
    photos: string[],
    index: number,
    title: string,
    event?: { preventDefault?: () => void; stopPropagation?: () => void },
  ) {
    event?.preventDefault?.();
    event?.stopPropagation?.();
    setActiveImageViewer({ title, photos, index });
  }

  function shiftImageViewer(direction: "next" | "prev") {
    setActiveImageViewer((current) => {
      if (!current || current.photos.length <= 1) {
        return current;
      }
      const nextIndex =
        direction === "next"
          ? (current.index + 1) % current.photos.length
          : (current.index - 1 + current.photos.length) % current.photos.length;
      return { ...current, index: nextIndex };
    });
  }

  function toggleBookmarked(postId: string | number) {
    setBookmarkedPostIds((prev) => {
      const isBookmarked = prev.includes(postId);
      const next = isBookmarked ? prev.filter((id) => id !== postId) : [...prev, postId];
      if (!isBookmarked) {
        setBookmarkAnimatingPostIds((current) => (current.includes(postId) ? current : [...current, postId]));
        window.setTimeout(() => {
          setBookmarkAnimatingPostIds((current) => current.filter((id) => id !== postId));
        }, 650);
      }
      return next;
    });
  }

  async function handleReact(postId: string | number) {
    if (reactingPostIds.includes(postId)) {
      return;
    }
    const currentPost = localPosts.find((post) => post.id === postId);
    if (!currentPost) {
      return;
    }
    const wasLiked = likedPostIds.includes(postId);
    const previousReactionCount = currentPost.reaction ?? 0;
    const optimisticReactionCount = Math.max(0, previousReactionCount + (wasLiked ? -1 : 1));

    setReactingPostIds((prev) => [...prev, postId]);
    setLocalPosts((prev) =>
      prev.map((post) =>
        post.id === postId ? { ...post, reaction: optimisticReactionCount, liked_by_me: !wasLiked } : post,
      ),
    );
    setLikedPostIds((prev) => (wasLiked ? prev.filter((id) => id !== postId) : [...prev, postId]));

    try {
      const response = await apiRequest<{ post: ProfileInteractivePost }>(`/api/feed/${postId}/reaction`, {
        method: "POST",
      });
      setLocalPosts((prev) =>
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
    } catch {
      setLocalPosts((prev) =>
        prev.map((post) =>
          post.id === postId ? { ...post, reaction: previousReactionCount, liked_by_me: wasLiked } : post,
        ),
      );
      setLikedPostIds((prev) =>
        wasLiked ? (prev.includes(postId) ? prev : [...prev, postId]) : prev.filter((id) => id !== postId),
      );
    } finally {
      setReactingPostIds((prev) => prev.filter((id) => id !== postId));
    }
  }

  async function fetchComments(postId: string | number, showLoader = true) {
    if (showLoader) {
      setCommentsLoading(true);
    }
    try {
      const response = await apiRequest<{ comments: CommentThreadItem[] }>(`/api/feed/${postId}/comments`);
      setComments(response.comments);
    } catch {
      setComments([]);
    } finally {
      if (showLoader) {
        setCommentsLoading(false);
      }
    }
  }

  async function handleSubmitComment() {
    if (!activeCommentPostId || !commentDraft.trim()) {
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
      await fetchComments(activeCommentPostId, false);
      setLocalPosts((prev) =>
        prev.map((post) =>
          post.id === activeCommentPostId ? { ...post, comment_count: (post.comment_count ?? 0) + 1 } : post,
        ),
      );
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
  }, [activeCommentPostId]);

  useEffect(() => {
    const coordinateLocations = new Set<string>();

    for (const post of localPosts) {
      if (parseCoordinateLocation(post.location)) {
        coordinateLocations.add(post.location!.trim());
      }
    }

    if (activeCommentPost?.location && parseCoordinateLocation(activeCommentPost.location)) {
      coordinateLocations.add(activeCommentPost.location.trim());
    }

    coordinateLocations.forEach((location) => {
      if (resolvedLocations[location] || resolvingLocationsRef.current.has(location)) {
        return;
      }

      const parsed = parseCoordinateLocation(location);
      if (!parsed) {
        return;
      }

      resolvingLocationsRef.current.add(location);

      void fetch(
        `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${parsed.lat}&lon=${parsed.lng}&zoom=16&addressdetails=1`,
      )
        .then(async (response) => {
          if (!response.ok) {
            throw new Error("Reverse geocoding failed.");
          }
          const data = (await response.json()) as {
            name?: string;
            display_name?: string;
            address?: Record<string, string | undefined>;
          };
          const summary =
            summarizeResolvedLocation(data) || data.display_name || formatCoordinateFallback(location);
          setResolvedLocations((current) => ({
            ...current,
            [location]: summary,
          }));
        })
        .catch(() => {
          setResolvedLocations((current) => ({
            ...current,
            [location]: formatCoordinateFallback(location),
          }));
        })
        .finally(() => {
          resolvingLocationsRef.current.delete(location);
        });
    });
  }, [activeCommentPost, localPosts, resolvedLocations]);

  return (
    <>
      <style>{`
        @keyframes dispatch-heart-pop { 0% { transform: scale(0); } 25% { transform: scale(1.2); } 50% { transform: scale(1); filter: brightness(1.15); } 100% { transform: scale(1); } }
        @keyframes dispatch-heart-burst { 0% { transform: scale(0); opacity: 0; } 50% { opacity: 1; filter: brightness(1.12); } 100% { transform: scale(1.35); opacity: 0; } }
        .dispatch-heart-filled { animation: dispatch-heart-pop 0.45s ease-out; transform-origin: center; }
        .dispatch-heart-burst { animation: dispatch-heart-burst 0.5s ease-out forwards; fill: #d97757; stroke: #d97757; stroke-width: 2px; transform-origin: center; }
        @keyframes dispatch-bookmark-pop { 50% { transform: scaleY(0.6); } 100% { transform: scaleY(1); } }
        @keyframes dispatch-bookmark-ring { from { width: 0; height: 0; opacity: 0; } 90% { width: 2.2rem; height: 2.2rem; opacity: 1; } to { opacity: 0; } }
        @keyframes dispatch-bookmark-spark { from { transform: scale(0); opacity: 0; } 40% { opacity: 1; } to { transform: scale(0.8); opacity: 0; } }
        .dispatch-bookmark-ring { animation: dispatch-bookmark-ring 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards; animation-delay: 0.3s; }
        .dispatch-bookmark-active { animation: dispatch-bookmark-pop 0.3s forwards; transform-origin: top; }
        .dispatch-bookmark-spark { width: 0.625rem; height: 0.625rem; border-radius: 9999px; box-shadow: 0 1.875rem 0 -4px #d97757, 1.875rem 0 0 -4px #d97757, 0 -1.875rem 0 -4px #d97757, -1.875rem 0 0 -4px #d97757, -1.375rem 1.375rem 0 -4px #d97757, -1.375rem -1.375rem 0 -4px #d97757, 1.375rem -1.375rem 0 -4px #d97757, 1.375rem 1.375rem 0 -4px #d97757; animation: dispatch-bookmark-spark 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards; animation-delay: 0.3s; }
        @keyframes dispatch-comment-overlay-in { 0% { opacity: 0; backdrop-filter: blur(0px); } 100% { opacity: 1; backdrop-filter: blur(12px); } }
        @keyframes dispatch-comment-modal-pop { 0% { opacity: 0; transform: translate3d(var(--dispatch-comment-from-x, 0px), var(--dispatch-comment-from-y, 0px), 0) scale(0.14); } 100% { opacity: 1; transform: translate3d(0, 0, 0) scale(1); } }
        .dispatch-comment-overlay { animation: dispatch-comment-overlay-in 0.24s ease-out both; }
        .dispatch-comment-modal { animation: dispatch-comment-modal-pop 0.28s cubic-bezier(0.22, 0.61, 0.36, 1) both; transform-origin: center center; will-change: transform, opacity; }
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-inline-avatar {
          background: #2a2724 !important;
          color: #d59b7c !important;
        }
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-media-surface,
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-comment-box,
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-comment-item,
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-empty-surface {
          background: #2a2724 !important;
          border-color: #3b3732 !important;
        }
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-comment-input {
          background: #23211f !important;
          border-color: #3b3732 !important;
          color: #f4eee8 !important;
        }
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-modal-surface {
          background: #23211f !important;
          border-color: #34302b !important;
        }
        .dispatch-shell-dark .dispatch-profile-page .dispatch-profile-post-stack .dispatch-profile-divider {
          border-color: rgba(255,255,255,0.08) !important;
        }
      `}</style>
      <div className="dispatch-profile-post-stack space-y-5">
        {localPosts.length === 0 ? (
          <Card className={cardClassName}>
            <div className="py-14 text-center text-on-surface-variant">
              <span className="material-symbols-outlined mb-4 block text-4xl text-outline">campaign</span>
              {emptyMessage}
            </div>
          </Card>
        ) : (
          localPosts.map((post) => {
            const categoryStyle = categoryStyles[post.category] ?? { accentClassName: "bg-[#f2e7de] text-[#8f4427]", icon: "article" };
            const displayPhotos = post.photos?.slice(0, 4) ?? [];
            const hasMorePhotos = (post.photos?.length ?? 0) > 4;
            const locationChip = post.location
              ? resolvedLocations[post.location.trim()] ?? formatCoordinateFallback(post.location)
              : null;
            const assessmentPost = isAssessmentPost(post);
            const profilePicture = department.profile_picture || department.profile_photo;
            const previewDepartment: FeedDepartmentPreview = {
              id: department.id,
              name: department.name,
              type: department.type ?? "other",
              profile_picture: department.profile_picture ?? department.profile_photo,
              verification_status: department.verification_status,
            };

            return (
              <Card
                key={post.id}
                className={`${cardClassName} ${hoverClassName} cursor-pointer`}
                onClick={(event) => handlePostCardActivate(event, post.id)}
                onKeyDown={(event) => handlePostCardActivate(event, post.id)}
                role="button"
                tabIndex={0}
              >
                <article className="space-y-5">
                  <div className="flex items-start gap-4">
                    <DepartmentHoverPreview
                      className="shrink-0"
                      department={previewDepartment}
                      panelClassName="left-1/2 -translate-x-1/2"
                    >
                      <div className="dispatch-profile-inline-avatar flex h-11 w-11 items-center justify-center overflow-hidden rounded-full bg-[#f2e7de] text-[#8f4427]">
                        {profilePicture ? (
                          <img alt={`${department.name} profile`} className="h-full w-full object-cover" src={profilePicture} />
                        ) : (
                          <span className="material-symbols-outlined">campaign</span>
                        )}
                      </div>
                    </DepartmentHoverPreview>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div className="min-w-0">
                          <DepartmentHoverPreview
                            className="inline-flex max-w-full"
                            department={previewDepartment}
                            panelClassName="left-1/2 -translate-x-1/2"
                          >
                            <div className="inline-flex min-w-0 flex-col items-start">
                              <p className="font-semibold text-on-surface transition-colors duration-200 ease-out group-hover/publisher:text-[#a14b2f]">
                                {department.name}
                              </p>
                            </div>
                          </DepartmentHoverPreview>
                          <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                            {new Date(post.created_at).toLocaleString()}
                          </p>
                        </div>
                        <div className="flex flex-wrap items-center justify-end gap-2">
                          {locationChip && !assessmentPost ? (
                            <span className="dispatch-profile-pill inline-flex max-w-[250px] items-center gap-1 rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-2.5 py-1 text-[10px] text-[#6f625b]">
                              <span className="material-symbols-outlined text-[13px]">location_on</span>
                              <span className="truncate">{locationChip}</span>
                            </span>
                          ) : null}
                          <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${categoryStyle.accentClassName}`}>
                            <span className="material-symbols-outlined text-[13px]">{categoryStyle.icon}</span>
                            {post.category.replaceAll("_", " ")}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="pl-0 md:pl-14">
                    <h3 className="font-headline text-3xl leading-tight text-on-surface">{post.title}</h3>
                    {assessmentPost && post.assessment_details ? (
                      <AssessmentPostSummary
                        className="mt-4"
                        compact
                        details={post.assessment_details}
                        locationLabel={locationChip}
                      />
                    ) : null}
                    <p className="mt-3 whitespace-pre-wrap text-base leading-relaxed text-on-surface-variant">{post.content}</p>

                    {displayPhotos.length > 0 ? (
                      <div className="mt-5">
                        {displayPhotos.length >= 2 ? (
                          <div className="dispatch-profile-media-surface grid grid-cols-2 gap-2 overflow-hidden rounded-[24px] border border-[#e2d1c7] bg-[#f3ebe4] p-2">
                            {displayPhotos.map((photo, index) => (
                              <button
                                key={`${post.id}-photo-${index}`}
                                type="button"
                                className={`group relative overflow-hidden rounded-[20px] bg-[#eadfd6] ${getFeedPhotoGridTileClassName(index, displayPhotos.length)}`}
                                onClick={(event) => openImageViewer(post.photos ?? [], index, post.title, event)}
                              >
                                <img
                                  alt={`${post.title} photo ${index + 1}`}
                                  className="h-full w-full object-cover transition-transform duration-300 ease-out group-hover:scale-[1.02]"
                                  src={photo}
                                />
                                {hasMorePhotos && index === displayPhotos.length - 1 ? (
                                  <div className="absolute inset-0 flex items-center justify-center bg-black/45 text-lg font-semibold text-white">
                                    +{(post.photos?.length ?? 0) - 4}
                                  </div>
                                ) : null}
                              </button>
                            ))}
                          </div>
                        ) : (
                          <button
                            type="button"
                            className="dispatch-profile-media-surface group relative overflow-hidden rounded-[24px] border border-[#e2d1c7] bg-[#f3ebe4]"
                            onClick={(event) =>
                              openImageViewer(post.photos ?? [], getPhotoIndex(post.id, post.photos?.length ?? 0), post.title, event)
                            }
                          >
                            <img
                              alt={post.title}
                              className="block h-auto max-h-[420px] w-full object-cover transition-transform duration-300 ease-out group-hover:scale-[1.01]"
                              src={post.photos?.[getPhotoIndex(post.id, post.photos.length)]}
                            />
                            {(post.photos?.length ?? 0) > 1 ? (
                              <>
                                <button
                                  type="button"
                                  className="absolute left-4 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm transition-colors hover:bg-black/60"
                                  onClick={(event) => {
                                    event.preventDefault();
                                    event.stopPropagation();
                                    shiftPostPhoto(post.id, post.photos?.length ?? 0, "prev");
                                  }}
                                >
                                  <span className="material-symbols-outlined">chevron_left</span>
                                </button>
                                <button
                                  type="button"
                                  className="absolute right-4 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm transition-colors hover:bg-black/60"
                                  onClick={(event) => {
                                    event.preventDefault();
                                    event.stopPropagation();
                                    shiftPostPhoto(post.id, post.photos?.length ?? 0, "next");
                                  }}
                                >
                                  <span className="material-symbols-outlined">chevron_right</span>
                                </button>
                              </>
                            ) : null}
                          </button>
                        )}
                      </div>
                    ) : null}

                    {post.attachments && post.attachments.length > 0 ? (
                      <div className="mt-5" onClick={(event) => event.stopPropagation()} onKeyDown={(event) => event.stopPropagation()}>
                        <AttachmentList attachments={post.attachments} />
                      </div>
                    ) : null}

                    <div className="dispatch-profile-divider mt-5 flex items-center justify-between border-t border-[#ecd8cf] pt-4">
                      <div className="flex items-center gap-6 text-on-surface-variant">
                        <button
                          className="group flex items-center gap-2 text-on-surface transition-colors"
                          disabled={reactingPostIds.includes(post.id)}
                          onClick={(event) => {
                            event.stopPropagation();
                            void handleReact(post.id);
                          }}
                          type="button"
                        >
                          <AnimatedHeartIcon liked={likedPostIds.includes(post.id)} />
                          <span className="text-xs font-bold uppercase tracking-widest">{post.reaction ?? 0}</span>
                        </button>
                        <button
                          className="group flex items-center gap-2 text-on-surface transition-colors"
                          onClick={(event) => {
                            event.stopPropagation();
                            openCommentModal(post.id, event.currentTarget);
                          }}
                          type="button"
                        >
                          <span className="material-symbols-outlined">chat_bubble</span>
                          <span className="text-xs font-bold uppercase tracking-widest">{post.comment_count ?? 0}</span>
                        </button>
                      </div>
                      <button
                        className="text-on-surface-variant transition-colors hover:text-on-surface"
                        onClick={(event) => {
                          event.stopPropagation();
                          toggleBookmarked(post.id);
                        }}
                        type="button"
                      >
                        <AnimatedBookmarkIcon animate={bookmarkAnimatingPostIds.includes(post.id)} bookmarked={bookmarkedPostIds.includes(post.id)} />
                      </button>
                    </div>
                  </div>
                </article>
              </Card>
            );
          })
        )}
      </div>
      {activeImageViewer ? (
        <div className="fixed inset-0 z-[72] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md md:p-8">
          <button
            aria-label="Close image viewer"
            className="absolute left-4 top-4 flex h-11 w-11 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
            onClick={() => setActiveImageViewer(null)}
            type="button"
          >
            <span className="material-symbols-outlined">close</span>
          </button>
          {activeImageViewer.photos.length > 1 ? (
            <button
              aria-label="Previous image"
              className="absolute left-4 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
              onClick={() => shiftImageViewer("prev")}
              type="button"
            >
              <span className="material-symbols-outlined">chevron_left</span>
            </button>
          ) : null}
          <div className="flex max-h-full max-w-[min(92vw,960px)] flex-col items-center gap-4">
            <img
              alt={`${activeImageViewer.title} image ${activeImageViewer.index + 1}`}
              className="max-h-[78vh] w-auto max-w-full rounded-[28px] object-contain shadow-[0_24px_60px_rgba(0,0,0,0.4)]"
              src={activeImageViewer.photos[activeImageViewer.index]}
            />
            {activeImageViewer.photos.length > 1 ? (
              <div className="rounded-full bg-white/10 px-4 py-2 text-sm font-medium text-white backdrop-blur-sm">
                {activeImageViewer.index + 1} / {activeImageViewer.photos.length}
              </div>
            ) : null}
          </div>
          {activeImageViewer.photos.length > 1 ? (
            <button
              aria-label="Next image"
              className="absolute right-4 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
              onClick={() => shiftImageViewer("next")}
              type="button"
            >
              <span className="material-symbols-outlined">chevron_right</span>
            </button>
          ) : null}
        </div>
      ) : null}

      {activeCommentPost ? (
        <div className="dispatch-comment-overlay fixed inset-0 z-[70] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div
            className="dispatch-comment-modal dispatch-profile-modal-surface relative flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl border border-[#e2d1c7] bg-[#fff8f3] text-on-surface shadow-[rgba(0,0,0,0.4)_0px_2px_4px,rgba(0,0,0,0.3)_0px_7px_13px_-3px,rgba(0,0,0,0.2)_0px_-3px_0px_inset]"
            style={
              {
                "--dispatch-comment-from-x": `${commentModalOrigin.x}px`,
                "--dispatch-comment-from-y": `${commentModalOrigin.y}px`,
              } as CSSProperties
            }
          >
            <div className="dispatch-profile-divider flex items-center gap-4 border-b border-[#e2d1c7] bg-[#fff8f3]/95 px-6 py-5 backdrop-blur-sm">
              <div className="dispatch-profile-inline-avatar flex h-12 w-12 items-center justify-center overflow-hidden rounded-full bg-[#f2e7de] text-[#8f4427]">
                {department.profile_picture || department.profile_photo ? (
                  <img
                    alt={`${department.name} profile`}
                    className="h-full w-full object-cover"
                    src={department.profile_picture || department.profile_photo || undefined}
                  />
                ) : (
                  <span className="material-symbols-outlined">campaign</span>
                )}
              </div>
              <div className="min-w-0">
                <p className="text-base font-semibold text-on-surface">{department.name}</p>
                <p className="mt-0.5 text-[10px] font-bold uppercase tracking-widest text-outline">
                  {new Date(activeCommentPost.created_at).toLocaleString()}
                </p>
              </div>
              <div className="ml-auto flex flex-wrap items-center justify-end gap-2">
                {activeCommentLocationLabel ? (
                  <span className="dispatch-profile-pill inline-flex max-w-[260px] items-center gap-1 rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-2.5 py-1 text-[10px] text-[#6f625b]">
                    <span className="material-symbols-outlined text-[13px]">location_on</span>
                    <span className="truncate">{activeCommentLocationLabel}</span>
                  </span>
                ) : null}
                <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${(categoryStyles[activeCommentPost.category] ?? { accentClassName: "bg-[#f2e7de] text-[#8f4427]" }).accentClassName}`}>
                  <span className="material-symbols-outlined text-[13px]">
                    {(categoryStyles[activeCommentPost.category] ?? { icon: "article" }).icon}
                  </span>
                  {activeCommentPost.category.replace("_", " ")}
                </span>
                <button
                  className="dispatch-profile-pill rounded-full border border-[#ecd8cf] bg-[#f7efe7] p-2 text-on-surface-variant transition-colors hover:text-on-surface"
                  onClick={() => setActiveCommentPostId(null)}
                  type="button"
                >
                  <span className="material-symbols-outlined">close</span>
                </button>
              </div>
            </div>

            <div className="min-h-0 overflow-y-auto px-6 pb-8 pt-6">
              <div className="space-y-6">
                <h3 className="text-3xl text-on-surface">{activeCommentPost.title}</h3>
                <p className="whitespace-pre-wrap text-[1.125rem] leading-[1.6] text-on-surface">
                  {activeCommentPost.content}
                </p>

                {activeCommentPost.photos && activeCommentPost.photos.length > 0 ? (
                  activeCommentPost.photos.length >= 4 ? (
                    <div className="dispatch-profile-media-surface grid grid-cols-2 gap-2 overflow-hidden rounded-[24px] border border-outline-variant/10 bg-[#f3ebe4] p-2">
                      {activeCommentPost.photos.map((photo, index) => (
                        <button
                          key={`detail-grid-photo-${index}`}
                          type="button"
                          className={`group relative overflow-hidden rounded-[20px] bg-[#eadfd6] ${getFeedPhotoGridTileClassName(index, activeCommentPost.photos!.length)}`}
                          onClick={(event) => openImageViewer(activeCommentPost.photos ?? [], index, activeCommentPost.title, event)}
                        >
                          <img
                            alt={`${activeCommentPost.title} photo ${index + 1}`}
                            className="h-full w-full object-cover transition-transform duration-300 ease-out group-hover:scale-[1.02]"
                            src={photo}
                          />
                        </button>
                      ))}
                    </div>
                  ) : (
                    <button
                      type="button"
                      className="dispatch-profile-media-surface group relative overflow-hidden rounded-[24px] border border-[#e2d1c7] bg-[#f3ebe4]"
                      onClick={(event) =>
                        openImageViewer(
                          activeCommentPost.photos ?? [],
                          getPhotoIndex(activeCommentPost.id, activeCommentPost.photos?.length ?? 0),
                          activeCommentPost.title,
                          event,
                        )
                      }
                    >
                      <img
                        alt={activeCommentPost.title}
                        className="block h-auto w-full"
                        src={activeCommentPost.photos[getPhotoIndex(activeCommentPost.id, activeCommentPost.photos.length)]}
                      />
                    </button>
                  )
                ) : null}

                {activeCommentPost.attachments && activeCommentPost.attachments.length > 0 ? (
                  <AttachmentList attachments={activeCommentPost.attachments} />
                ) : null}

                <div className="dispatch-profile-divider flex items-center justify-between border-y border-[#ecd8cf] py-4">
                  <div className="flex items-center gap-6 text-on-surface-variant">
                    <button
                      className="group flex items-center gap-2 text-on-surface transition-colors"
                      disabled={reactingPostIds.includes(activeCommentPost.id)}
                      onClick={() => void handleReact(activeCommentPost.id)}
                      type="button"
                    >
                      <AnimatedHeartIcon liked={likedPostIds.includes(activeCommentPost.id)} />
                      <span className="text-xs font-bold uppercase tracking-widest">{activeCommentPost.reaction ?? 0}</span>
                    </button>
                    <button className="group flex items-center gap-2 text-on-surface transition-colors" type="button">
                      <span className="material-symbols-outlined">chat_bubble</span>
                      <span className="text-xs font-bold uppercase tracking-widest">{activeCommentPost.comment_count ?? comments.length}</span>
                    </button>
                  </div>
                  <button
                    className="text-on-surface-variant transition-colors hover:text-on-surface"
                    onClick={() => toggleBookmarked(activeCommentPost.id)}
                    type="button"
                  >
                    <AnimatedBookmarkIcon animate={bookmarkAnimatingPostIds.includes(activeCommentPost.id)} bookmarked={bookmarkedPostIds.includes(activeCommentPost.id)} />
                  </button>
                </div>

                <div className="space-y-4">
                  <div className="flex items-center justify-between gap-3">
                    <h4 className="text-lg font-semibold text-on-surface">Comments</h4>
                    <span className="text-xs font-bold uppercase tracking-widest text-outline">{comments.length} total</span>
                  </div>
                  <div className="dispatch-profile-comment-box rounded-[24px] border border-[#e2d1c7] bg-[#f7efe7] p-4">
                    <textarea
                      className="dispatch-profile-comment-input min-h-[112px] w-full resize-none rounded-[20px] border border-[#e2d1c7] bg-[#fff8f3] px-4 py-3 text-sm text-on-surface outline-none transition-colors focus:border-[#a14b2f]"
                      onChange={(event) => setCommentDraft(event.target.value)}
                      placeholder="Share a response note or coordination detail..."
                      value={commentDraft}
                    />
                    <div className="mt-3 flex items-center justify-between gap-3">
                      {commentError ? <p className="text-sm text-[#a14b2f]">{commentError}</p> : <span />}
                      <button
                        className="rounded-full bg-[#a14b2f] px-5 py-2 text-xs font-semibold uppercase tracking-wide text-white transition-colors hover:bg-[#914024] disabled:cursor-not-allowed disabled:opacity-70"
                        disabled={commentSubmitting}
                        onClick={() => void handleSubmitComment()}
                        type="button"
                      >
                        {commentSubmitting ? "Posting..." : "Comment"}
                      </button>
                    </div>
                  </div>
                  <div className="space-y-3">
                    {commentsLoading ? (
                      <div className="dispatch-profile-empty-surface rounded-[20px] border border-dashed border-[#e2d1c7] bg-[#fff8f3] px-4 py-8 text-center text-sm text-on-surface-variant">
                        Loading comments...
                      </div>
                    ) : comments.length === 0 ? (
                      <div className="dispatch-profile-empty-surface rounded-[20px] border border-dashed border-[#e2d1c7] bg-[#fff8f3] px-4 py-8 text-center text-sm text-on-surface-variant">
                        No comments yet. Be the first to respond.
                      </div>
                    ) : (
                      comments.map((comment) => (
                        <div key={comment.id} className="dispatch-profile-comment-item rounded-[22px] border border-[#e2d1c7] bg-[#fff8f3] px-4 py-4">
                          <div className="flex items-center justify-between gap-4">
                            <p className="font-semibold text-on-surface">{comment.user_name}</p>
                            <p className="text-[11px] font-bold uppercase tracking-widest text-outline">
                              {new Date(comment.created_at).toLocaleString()}
                            </p>
                          </div>
                          <p className="mt-3 whitespace-pre-wrap text-sm leading-relaxed text-on-surface-variant">
                            {comment.comment}
                          </p>
                        </div>
                      ))
                    )}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}

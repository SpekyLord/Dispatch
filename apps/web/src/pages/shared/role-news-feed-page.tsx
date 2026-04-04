import { Link } from "react-router-dom";
import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties } from "react";

import { AttachmentList } from "@/components/feed/attachment-list";
import {
  DepartmentHoverPreview,
  type FeedDepartmentPreview,
} from "@/components/feed/department-hover-preview";
import { DepartmentCreatePostForm } from "@/components/feed/department-create-post-form";
import { AppShell } from "@/components/layout/app-shell";
import { useAppShellTheme } from "@/components/layout/app-shell-theme";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
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

type FollowDepartment = FeedDepartmentPreview & {
  user_id: string;
  profile_photo?: string | null;
  post_count?: number | null;
};

type ActiveImageViewer = {
  title: string;
  photos: string[];
  index: number;
} | null;

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

const readinessCategories = ["alert", "warning", "situational_report"] as const;
const readinessCategorySet = new Set<string>(readinessCategories);
const readinessCategoryLabels: Record<(typeof readinessCategories)[number], string> = {
  alert: "Alert",
  warning: "Warning",
  situational_report: "Situational Report",
};

const footerLinks = ["Standard Ops", "Ethics Policy", "Command Chain"] as const;
const baseWarmPanelClassName = "dispatch-news-feed-surface border-[#efd8d0] bg-[#fff8f3]";
const baseWarmTabClassName = "dispatch-news-feed-pill border border-[#ecd8cf] bg-[#f7efe7] text-[#6f625b]";
const baseWarmActionTabClassName =
  "dispatch-news-feed-pill border border-[#ecd8cf] bg-[#f7efe7] text-[#8a5a40] transition-colors hover:bg-[#f2e7de]";
const basePopupPanelShadowClassName =
  "shadow-[rgba(0,0,0,0.4)_0px_2px_4px,rgba(0,0,0,0.3)_0px_7px_13px_-3px,rgba(0,0,0,0.2)_0px_-3px_0px_inset]";
const baseRaisedFeedCardClassName =
  "shadow-[15px_15px_30px_rgba(208,191,179,0.78),-15px_-15px_30px_rgba(255,255,255,0.96)]";
const publishedFeedCardShadowClassName =
  "shadow-[0_8px_18px_-12px_rgba(120,78,58,0.42),0_5px_15px_0_#00000026]";
const basePublishLaneEffectClassName =
  "dispatch-news-feed-publish-lane space-y-5 overflow-visible rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset] md:mr-2 xl:mr-4";
const basePublishedTabHighlightClassName =
  "transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#e7c7b8] hover:bg-[#fffaf6] hover:shadow-[0_10px_22px_-12px_rgba(120,78,58,0.48),0_5px_5px_0_#00000026]";
const heartOutlinePath =
  "M17.5,1.917a6.4,6.4,0,0,0-5.5,3.3,6.4,6.4,0,0,0-5.5-3.3A6.8,6.8,0,0,0,0,8.967c0,4.547,4.786,9.513,8.8,12.88a4.974,4.974,0,0,0,6.4,0C19.214,18.48,24,13.514,24,8.967A6.8,6.8,0,0,0,17.5,1.917Zm-3.585,18.4a2.973,2.973,0,0,1-3.83,0C4.947,16.006,2,11.87,2,8.967a4.8,4.8,0,0,1,4.5-5.05A4.8,4.8,0,0,1,11,8.967a1,1,0,0,0,2,0,4.8,4.8,0,0,1,4.5-5.05A4.8,4.8,0,0,1,22,8.967C22,11.87,19.053,16.006,13.915,20.313Z";
const heartFilledPath =
  "M17.5,1.917a6.4,6.4,0,0,0-5.5,3.3,6.4,6.4,0,0,0-5.5-3.3A6.8,6.8,0,0,0,0,8.967c0,4.547,4.786,9.513,8.8,12.88a4.974,4.974,0,0,0,6.4,0C19.214,18.48,24,13.514,24,8.967A6.8,6.8,0,0,0,17.5,1.917Z";
const bookmarkPath =
  "M27 4v27a1 1 0 0 1-1.625.781L16 24.281l-9.375 7.5A1 1 0 0 1 5 31V4a4 4 0 0 1 4-4h14a4 4 0 0 1 4 4z";

function summarizePostContent(content: string, maxLength = 72) {
  const collapsed = content.replace(/\s+/g, " ").trim();
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return `${collapsed.slice(0, maxLength).trimEnd()}...`;
}

function formatDepartmentHandle(name?: string | null) {
  if (!name) {
    return "@department";
  }
  const normalized = name.toLowerCase().replace(/[^a-z0-9]+/g, "");
  return `@${normalized || "department"}`;
}

function getFollowAccent(type?: string | null) {
  switch (type) {
    case "fire":
    case "disaster":
      return "from-[#f7d1b5] to-[#f3b7a0]";
    case "police":
      return "from-[#d8c6ff] to-[#b39ddb]";
    case "medical":
    case "health":
      return "from-[#ffd5dc] to-[#f3b2c0]";
    default:
      return "from-[#c4ead9] to-[#8ec5a6]";
  }
}

function getFollowSymbol(type?: string | null) {
  switch (type) {
    case "fire":
      return "local_fire_department";
    case "police":
      return "local_police";
    case "medical":
    case "health":
      return "medical_services";
    case "disaster":
      return "shield_person";
    default:
      return "domain";
  }
}

function buildReadinessMeta(post: FeedPost) {
  const departmentName = post.department?.name ?? "Department update";
  const timestamp = new Date(post.created_at).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

  if (post.location?.trim()) {
    return `${departmentName} • ${post.location}`;
  }

  return `${departmentName} • ${timestamp}`;
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

function getFeedPhotoGridTileClassName(index: number, photoCount: number) {
  if (photoCount === 2) {
    return "aspect-[4/3]";
  }

  if (photoCount === 3) {
    return index === 0 ? "col-span-2 aspect-[2.2/1]" : "aspect-square";
  }

  return "aspect-square";
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
            className="dispatch-heart-filled absolute h-5 w-5 fill-[#d97757]"
            viewBox="0 0 24 24"
          >
            <path d={heartFilledPath} />
          </svg>
          <svg
            aria-hidden="true"
            className="dispatch-heart-burst pointer-events-none absolute -inset-4 h-14 w-14"
            viewBox="0 0 100 100"
          >
            <polygon points="18,18 30,30 22,34 14,22" />
            <polygon points="18,50 34,50 34,56 18,56" />
            <polygon points="22,76 34,66 38,72 26,82" />
            <polygon points="82,18 70,30 78,34 86,22" />
            <polygon points="82,50 66,50 66,56 82,56" />
            <polygon points="78,76 66,66 62,72 74,82" />
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
        <path
          d={bookmarkPath}
          className={bookmarked ? "fill-[#d97757]" : "fill-[#6f625b]"}
        />
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

export function RoleNewsFeedPage({ role }: { role: NewsFeedRole }) {
  const copy = roleCopy[role];
  const canPost = role === "department";
  const departmentLayout = role === "department";
  const { isDarkMode } = useAppShellTheme();
  const accessToken = useSessionStore((state) => state.accessToken);
  const currentUser = useSessionStore((state) => state.user);
  const [posts, setPosts] = useState<FeedPost[]>([]);
  const [followDepartments, setFollowDepartments] = useState<FollowDepartment[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeCommentPostId, setActiveCommentPostId] = useState<string | number | null>(null);
  const [isCreatePostOpen, setIsCreatePostOpen] = useState(false);
  const [likedPostIds, setLikedPostIds] = useState<Array<string | number>>([]);
  const [bookmarkedPostIds, setBookmarkedPostIds] = useState<Array<string | number>>([]);
  const [bookmarkAnimatingPostIds, setBookmarkAnimatingPostIds] = useState<Array<string | number>>([]);
  const [reactingPostIds, setReactingPostIds] = useState<Array<string | number>>([]);
  const [comments, setComments] = useState<CommentThreadItem[]>([]);
  const [commentsLoading, setCommentsLoading] = useState(false);
  const [commentDraft, setCommentDraft] = useState("");
  const [commentError, setCommentError] = useState<string | null>(null);
  const [commentSubmitting, setCommentSubmitting] = useState(false);
  const [deleteConfirmPost, setDeleteConfirmPost] = useState<FeedPost | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [deletingPostId, setDeletingPostId] = useState<string | number | null>(null);
  const [menuOpenPostId, setMenuOpenPostId] = useState<string | number | null>(null);
  const [editPost, setEditPost] = useState<FeedPost | null>(null);
  const [commentModalOrigin, setCommentModalOrigin] = useState({ x: 0, y: 0 });
  const [createModalOrigin, setCreateModalOrigin] = useState({ x: 0, y: 0 });
  const [postPhotoIndices, setPostPhotoIndices] = useState<Record<string, number>>({});
  const [activeImageViewer, setActiveImageViewer] = useState<ActiveImageViewer>(null);
  const [resolvedLocations, setResolvedLocations] = useState<Record<string, string>>({});
  const resolvingLocationsRef = useRef(new Set<string>());
  const warmPanelClassName = isDarkMode
    ? "border-[#34302b] bg-[#23211f]"
    : baseWarmPanelClassName;
  const warmTabClassName = isDarkMode
    ? "border border-[#3b3732] bg-[#2a2724] text-[#d7c4b7]"
    : baseWarmTabClassName;
  const warmActionTabClassName = isDarkMode
    ? "border border-[#3b3732] bg-[#2a2724] text-[#d59b7c] transition-colors hover:bg-[#332f2b]"
    : baseWarmActionTabClassName;
  const popupPanelShadowClassName = isDarkMode
    ? "shadow-[rgba(0,0,0,0.55)_0px_16px_40px,rgba(255,255,255,0.04)_0px_1px_0px_inset]"
    : basePopupPanelShadowClassName;
  const raisedFeedCardClassName = isDarkMode
    ? "shadow-[14px_14px_28px_rgba(0,0,0,0.34),-10px_-10px_22px_rgba(255,255,255,0.02)]"
    : baseRaisedFeedCardClassName;
  const publishLaneEffectClassName = isDarkMode
    ? "space-y-5 overflow-visible rounded-[34px] bg-[#1d1b1a] p-3 shadow-[rgba(255,255,255,0.04)_0px_1px_0px_inset,rgba(0,0,0,0.48)_0px_24px_48px_-18px_inset] md:mr-2 xl:mr-4"
    : basePublishLaneEffectClassName;
  const publishedTabHighlightClassName = isDarkMode
    ? "transform-gpu transition-all duration-200 ease-out hover:scale-[1.004] hover:border-[#4a433d] hover:bg-[#292624] hover:shadow-[0_10px_22px_-12px_rgba(120,78,58,0.48),0_5px_5px_0_#00000026]"
    : basePublishedTabHighlightClassName;
  const composerInnerPanelClassName = isDarkMode
    ? "dispatch-news-feed-composer-inner rounded-[28px] border border-[#3b3732] bg-[#262321] px-4 py-4"
    : "dispatch-news-feed-composer-inner rounded-[28px] border border-[#ecd8cf] bg-[#fff8f3] px-4 py-4";
  const composerPromptClassName = isDarkMode
    ? "dispatch-news-feed-composer-prompt min-h-[56px] flex-1 rounded-full border border-[#3b3732] bg-[#2a2724] px-5 text-left text-base text-[#d7c4b7] transition-colors hover:bg-[#332f2b] hover:text-[#f4eee8] lg:text-lg"
    : "dispatch-news-feed-composer-prompt min-h-[56px] flex-1 rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-5 text-left text-base text-[#7a6b63] transition-colors hover:bg-[#f2e7de] hover:text-[#5f4f46] lg:text-lg";
  const popupSurfaceClassName = isDarkMode
    ? "border border-[#34302b] bg-[#23211f]"
    : "border border-[#efd8d0] bg-[#fff8f3]";
  const popupHeaderClassName = isDarkMode
    ? "border-b border-[#3b3732] bg-[#23211f]/95"
    : "border-b border-[#ecd8cf] bg-[#fff8f3]/95";
  const menuSurfaceClassName = isDarkMode
    ? "absolute right-0 top-full z-20 mt-2 min-w-[180px] overflow-hidden rounded-2xl border border-[#3b3732] bg-[#23211f] shadow-[0_16px_30px_rgba(0,0,0,0.34)]"
    : "absolute right-0 top-full z-20 mt-2 min-w-[180px] overflow-hidden rounded-2xl border border-[#ecd8cf] bg-[#fff8f3] shadow-[0_12px_24px_rgba(56,56,49,0.12)]";

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

  const fetchFollowDepartments = useCallback(() => {
    return apiRequest<{ departments: FollowDepartment[] }>("/api/departments/directory")
      .then((res) => {
        setFollowDepartments(
          (res.departments ?? [])
            .filter((department) => department.user_id && department.user_id !== currentUser?.id)
            .slice(0, 3),
        );
      })
      .catch(() => {
        setFollowDepartments([]);
      });
  }, [currentUser?.id]);

  useEffect(() => {
    queueMicrotask(() => {
      void fetchPosts();
      void fetchFollowDepartments();
    });
  }, [fetchFollowDepartments, fetchPosts]);

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
  const readinessPosts = useMemo(
    () => posts.filter((post) => readinessCategorySet.has(post.category)).slice(0, 3),
    [posts],
  );
  const readinessCount = useMemo(
    () => posts.filter((post) => readinessCategorySet.has(post.category)).length,
    [posts],
  );
  const activeCommentLocationLabel = activeCommentPost?.location
    ? resolvedLocations[activeCommentPost.location.trim()] ?? formatCoordinateFallback(activeCommentPost.location)
    : null;

  useEffect(() => {
    const coordinateLocations = new Set<string>();

    for (const post of posts) {
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
  }, [activeCommentPost, posts, resolvedLocations]);

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

    const currentPost = posts.find((post) => post.id === postId);
    if (!currentPost) {
      return;
    }

    const wasLiked = likedPostIds.includes(postId);
    const previousReactionCount = currentPost.reaction ?? 0;
    const optimisticReactionCount = Math.max(0, previousReactionCount + (wasLiked ? -1 : 1));

    setReactingPostIds((prev) => [...prev, postId]);
    setPosts((prev) =>
      prev.map((post) =>
        post.id === postId
          ? {
              ...post,
              reaction: optimisticReactionCount,
              liked_by_me: !wasLiked,
            }
          : post,
      ),
    );
    setLikedPostIds((prev) =>
      wasLiked ? prev.filter((id) => id !== postId) : [...prev, postId],
    );

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
    } catch {
      setPosts((prev) =>
        prev.map((post) =>
          post.id === postId
            ? {
                ...post,
                reaction: previousReactionCount,
                liked_by_me: wasLiked,
              }
            : post,
        ),
      );
      setLikedPostIds((prev) =>
        wasLiked ? (prev.includes(postId) ? prev : [...prev, postId]) : prev.filter((id) => id !== postId),
      );
    } finally {
      setReactingPostIds((prev) => prev.filter((id) => id !== postId));
    }
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

  function openCreatePostModal(button?: HTMLElement | null) {
    if (button) {
      const rect = button.getBoundingClientRect();
      setCreateModalOrigin({
        x: rect.left + rect.width / 2 - window.innerWidth / 2,
        y: rect.top + rect.height / 2 - window.innerHeight / 2,
      });
    } else {
      setCreateModalOrigin({ x: 0, y: 0 });
    }

    setIsCreatePostOpen(true);
  }

  function handlePostCardActivate(
    event: {
      currentTarget: EventTarget & HTMLElement;
      target: EventTarget | null;
      key?: string;
      preventDefault: () => void;
    },
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

  function getPhotoIndex(postId: string | number, photoCount: number) {
    if (photoCount <= 0) {
      return 0;
    }
    const storedIndex = postPhotoIndices[String(postId)] ?? 0;
    return Math.min(storedIndex, photoCount - 1);
  }

  function shiftPostPhoto(
    postId: string | number,
    photoCount: number,
    direction: "next" | "prev",
  ) {
    if (photoCount <= 1) {
      return;
    }

    setPostPhotoIndices((prev) => {
      const current = prev[String(postId)] ?? 0;
      const next =
        direction === "next"
          ? (current + 1) % photoCount
          : (current - 1 + photoCount) % photoCount;
      return {
        ...prev,
        [String(postId)]: next,
      };
    });
  }

  function openImageViewer(
    photos: string[],
    index: number,
    title: string,
    event?: { stopPropagation?: () => void; preventDefault?: () => void },
  ) {
    event?.preventDefault?.();
    event?.stopPropagation?.();
    setActiveImageViewer({
      title,
      photos,
      index,
    });
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
      return {
        ...current,
        index: nextIndex,
      };
    });
  }

  function toggleBookmarked(postId: string | number) {
    setBookmarkedPostIds((prev) => {
      const isBookmarked = prev.includes(postId);
      const next = isBookmarked ? prev.filter((id) => id !== postId) : [...prev, postId];

      if (!isBookmarked) {
        setBookmarkAnimatingPostIds((current) =>
          current.includes(postId) ? current : [...current, postId],
        );
        window.setTimeout(() => {
          setBookmarkAnimatingPostIds((current) => current.filter((id) => id !== postId));
        }, 650);
      }

      return next;
    });
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

  async function handleDeletePost() {
    if (!deleteConfirmPost) {
      return;
    }

    setDeleteError(null);
    setDeletingPostId(deleteConfirmPost.id);
    try {
      await apiRequest<{ deleted: boolean }>(`/api/feed/${deleteConfirmPost.id}`, {
        method: "DELETE",
      });
      if (activeCommentPostId === deleteConfirmPost.id) {
        setActiveCommentPostId(null);
      }
      setDeleteConfirmPost(null);
      setMenuOpenPostId(null);
      await fetchPosts(false);
    } catch (error) {
      setDeleteError(error instanceof Error ? error.message : "Failed to delete post.");
    } finally {
      setDeletingPostId(null);
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
    <>
      <style>{`
        @keyframes dispatch-heart-pop {
          0% { transform: scale(0); }
          25% { transform: scale(1.2); }
          50% { transform: scale(1); filter: brightness(1.15); }
          100% { transform: scale(1); }
        }

        @keyframes dispatch-heart-burst {
          0% { transform: scale(0); opacity: 0; }
          50% { opacity: 1; filter: brightness(1.12); }
          100% { transform: scale(1.35); opacity: 0; }
        }

        .dispatch-heart-filled {
          animation: dispatch-heart-pop 0.45s ease-out;
          transform-origin: center;
        }

        .dispatch-heart-burst {
          animation: dispatch-heart-burst 0.5s ease-out forwards;
          fill: #d97757;
          stroke: #d97757;
          stroke-width: 2px;
          transform-origin: center;
        }

        @keyframes dispatch-bookmark-pop {
          50% { transform: scaleY(0.6); }
          100% { transform: scaleY(1); }
        }

        @keyframes dispatch-bookmark-ring {
          from {
            width: 0;
            height: 0;
            opacity: 0;
          }
          90% {
            width: 2.2rem;
            height: 2.2rem;
            opacity: 1;
          }
          to {
            opacity: 0;
          }
        }

        @keyframes dispatch-bookmark-spark {
          from {
            transform: scale(0);
            opacity: 0;
          }
          40% {
            opacity: 1;
          }
          to {
            transform: scale(0.8);
            opacity: 0;
          }
        }

        .dispatch-bookmark-ring {
          animation: dispatch-bookmark-ring 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards;
          animation-delay: 0.3s;
        }

        .dispatch-bookmark-active {
          animation: dispatch-bookmark-pop 0.3s forwards;
          transform-origin: top;
        }

        .dispatch-bookmark-spark {
          width: 0.625rem;
          height: 0.625rem;
          border-radius: 9999px;
          box-shadow:
            0 1.875rem 0 -4px #d97757,
            1.875rem 0 0 -4px #d97757,
            0 -1.875rem 0 -4px #d97757,
            -1.875rem 0 0 -4px #d97757,
            -1.375rem 1.375rem 0 -4px #d97757,
            -1.375rem -1.375rem 0 -4px #d97757,
            1.375rem -1.375rem 0 -4px #d97757,
            1.375rem 1.375rem 0 -4px #d97757;
          animation: dispatch-bookmark-spark 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards;
          animation-delay: 0.3s;
        }

        @keyframes dispatch-comment-overlay-in {
          0% {
            opacity: 0;
            backdrop-filter: blur(0px);
          }
          100% {
            opacity: 1;
            backdrop-filter: blur(12px);
          }
        }

        @keyframes dispatch-comment-modal-pop {
          0% {
            opacity: 0;
            transform: translate3d(var(--dispatch-comment-from-x, 0px), var(--dispatch-comment-from-y, 0px), 0) scale(0.14);
          }
          100% {
            opacity: 1;
            transform: translate3d(0, 0, 0) scale(1);
          }
        }

        .dispatch-comment-overlay {
          animation: dispatch-comment-overlay-in 0.24s ease-out both;
        }

        .dispatch-comment-modal {
          animation: dispatch-comment-modal-pop 0.28s cubic-bezier(0.22, 0.61, 0.36, 1) both;
          transform-origin: center center;
          will-change: transform, opacity;
        }
      `}</style>
      <AppShell subtitle={copy.subtitle} title="News Feed">
      <div className={isDarkMode ? "dispatch-news-feed-page dispatch-news-feed-dark space-y-8" : "dispatch-news-feed-page space-y-8"}>
        <style>{`
          .dispatch-shell-dark .dispatch-news-feed-page .text-on-surface { color: #f4eee8 !important; }
          .dispatch-shell-dark .dispatch-news-feed-page .text-on-surface-variant { color: #c6b8ac !important; }
          .dispatch-shell-dark .dispatch-news-feed-page .text-outline,
          .dispatch-shell-dark .dispatch-news-feed-page .text-outline-variant { color: #9d8d80 !important; }
          .dispatch-shell-dark .dispatch-news-feed-page .border-outline-variant\\/10 { border-color: rgba(255,255,255,0.08) !important; }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-publish-lane {
            background: #1d1b1a !important;
            box-shadow:
              rgba(255,255,255,0.04) 0px 1px 0px inset,
              rgba(0,0,0,0.48) 0px 24px 48px -18px inset !important;
          }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-surface,
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-card {
            background: #23211f !important;
            border-color: #34302b !important;
          }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-card {
            box-shadow:
              14px 14px 28px rgba(0,0,0,0.34),
              -10px -10px 22px rgba(255,255,255,0.02) !important;
          }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-published-card {
            box-shadow: 0 8px 18px -12px rgba(120,78,58,0.42), 0 5px 15px 0 #00000026 !important;
          }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-card:hover {
            background: #292624 !important;
            border-color: #4a433d !important;
          }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-published-card:hover {
            box-shadow: 0 10px 22px -12px rgba(120,78,58,0.48), 0 5px 5px 0 #00000026 !important;
          }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-composer-inner {
            background: #262321 !important;
            border-color: #3b3732 !important;
          }
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-composer-prompt,
          .dispatch-shell-dark .dispatch-news-feed-page .dispatch-news-feed-pill {
            background: #2a2724 !important;
            border-color: #3b3732 !important;
            color: #d7c4b7 !important;
          }
        `}</style>
        {!departmentLayout && (
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
                <p className="mt-2 font-headline text-4xl">{loading ? "..." : String(readinessCount).padStart(2, "0")}</p>
                <p className="mt-1 text-xs text-white/70">Live alerts, warnings, and situational reports</p>
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
        )}

        <div
          className={departmentLayout
            ? "grid gap-6 md:grid-cols-[minmax(0,1fr)_18rem] md:items-start xl:grid-cols-[minmax(0,1fr)_20rem]"
            : "grid gap-6 xl:grid-cols-12"}
        >
          <div className={`min-w-0 space-y-6 ${departmentLayout ? "" : "xl:col-span-8"}`}>
            {!departmentLayout && (
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
                        <div className={`mt-4 ${composerInnerPanelClassName}`}>
                          <div className="flex flex-col gap-4 md:flex-row md:items-center">
                            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[#ffefe6] text-[#a14b2f]">
                              <span className="material-symbols-outlined">edit_square</span>
                            </div>
                            <button
                              type="button"
                              onClick={(event) => openCreatePostModal(event.currentTarget)}
                              className={isDarkMode
                                ? "min-h-[56px] flex-1 rounded-full border border-[#3b3732] bg-[#2a2724] px-5 text-left text-lg text-[#d7c4b7] transition-colors hover:bg-[#332f2b] hover:text-[#f4eee8]"
                                : "min-h-[56px] flex-1 rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-5 text-left text-lg text-[#7a6b63] transition-colors hover:bg-[#f2e7de] hover:text-[#5f4f46]"}
                            >
                              Anything urgent to share?
                            </button>
                            <Button
                              type="button"
                              variant="secondary"
                              className="min-w-[96px] self-end md:self-auto"
                              onClick={(event) => openCreatePostModal(event.currentTarget)}
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
                        <div className={`mt-4 rounded-2xl px-4 py-4 ${isDarkMode ? "border border-[#3b3732] bg-[#262321]" : "border border-[#ecd8cf] bg-white"}`}>
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
            )}

            <div className={departmentLayout ? publishLaneEffectClassName : "space-y-5"}>
              {departmentLayout && (
                <Card className={`dispatch-news-feed-card ${warmPanelClassName} ${raisedFeedCardClassName}`}>
                  <div className="flex flex-col gap-4 md:flex-row md:items-start">
                    <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[#ffdbd0] text-[#89391e]">
                      <span className="material-symbols-outlined">campaign</span>
                    </div>
                    <div className="flex-1">
                      <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                        Department composer
                      </p>
                      <div className={`mt-4 ${composerInnerPanelClassName}`}>
                        <div className="flex flex-col gap-4 lg:flex-row lg:items-center">
                          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[#ffefe6] text-[#a14b2f]">
                            <span className="material-symbols-outlined">edit_square</span>
                          </div>
                          <button
                            type="button"
                            onClick={(event) => openCreatePostModal(event.currentTarget)}
                            className={composerPromptClassName}
                          >
                            Anything urgent to share?
                          </button>
                          <Button
                            type="button"
                            variant="secondary"
                            className="min-w-[96px] self-end lg:self-auto"
                            onClick={(event) => openCreatePostModal(event.currentTarget)}
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
                    </div>
                  </div>
                </Card>
              )}
              {loading ? (
                <Card className={`${warmPanelClassName} py-16 text-center text-on-surface-variant`}>
                  <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
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
                  const canDeletePost = currentUser?.role === "department" && String(currentUser.id) === String(post.uploader);
                  const isMenuOpen = menuOpenPostId === post.id;
                  const locationLabel = post.location
                    ? resolvedLocations[post.location.trim()] ?? formatCoordinateFallback(post.location)
                    : null;

                  return (
                    <Card key={post.id} className={`dispatch-news-feed-card dispatch-news-feed-published-card ${warmPanelClassName} ${publishedFeedCardShadowClassName} ${publishedTabHighlightClassName} relative overflow-visible`}>
                      <article
                        className="cursor-pointer space-y-5"
                        role="button"
                        tabIndex={0}
                        onClick={(event) => handlePostCardActivate(event, post.id)}
                        onKeyDown={(event) => handlePostCardActivate(event, post.id)}
                      >
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
                                <p className="mt-0.5 text-[11px] font-bold uppercase tracking-widest text-outline transition-opacity duration-200 ease-out group-hover/publisher:opacity-55">
                                  {new Date(post.created_at).toLocaleString()}
                                </p>
                              </Link>
                            </DepartmentHoverPreview>
                          </div>
                          <div className="ml-auto flex flex-wrap items-center justify-end gap-2">
                            {locationLabel ? (
                              <span className={`inline-flex max-w-[260px] items-center gap-1 rounded-full px-2.5 py-1 text-[10px] ${warmTabClassName}`}>
                                <span className="material-symbols-outlined text-[14px]">location_on</span>
                                <span className="truncate normal-case tracking-normal">{locationLabel}</span>
                              </span>
                            ) : null}
                            <span className={`inline-flex items-center gap-1 rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${warmTabClassName}`}>
                              <span className="material-symbols-outlined text-[14px]">{categoryStyle.icon}</span>
                              {post.category.replace("_", " ")}
                            </span>
                            {canDeletePost && (
                              <div className="relative">
                                <button
                                  type="button"
                                  className={`inline-flex items-center gap-2 rounded-full px-3 py-1 font-medium ${warmActionTabClassName}`}
                                  onClick={(event) => {
                                    event.stopPropagation();
                                    setMenuOpenPostId((current) => (current === post.id ? null : post.id));
                                  }}
                                  title="Post actions"
                                >
                                  <span className="material-symbols-outlined text-[18px]">more_horiz</span>
                                </button>
                                {isMenuOpen && (
                                  <div className={menuSurfaceClassName}>
                                    <button
                                      type="button"
                                      aria-label="Edit post"
                                      className="flex w-full items-center gap-3 px-4 py-3 text-left text-sm text-on-surface transition-colors hover:bg-[#f7efe7]"
                                      onClick={() => {
                                        setMenuOpenPostId(null);
                                        setDeleteError(null);
                                        setEditPost(post);
                                      }}
                                    >
                                      <span className="material-symbols-outlined text-[18px] text-[#a14b2f]">edit</span>
                                      Edit post
                                    </button>
                                    <button
                                      type="button"
                                      aria-label="Delete post"
                                      className="flex w-full items-center gap-3 border-t border-[#ecd8cf] px-4 py-3 text-left text-sm text-on-surface transition-colors hover:bg-[#f7efe7]"
                                      onClick={() => {
                                        setMenuOpenPostId(null);
                                        setDeleteError(null);
                                        setDeleteConfirmPost(post);
                                      }}
                                    >
                                      <span className="material-symbols-outlined text-[18px] text-[#a14b2f]">delete</span>
                                      Delete post
                                    </button>
                                  </div>
                                )}
                              </div>
                            )}
                          </div>
                        </div>

                        <div className="space-y-4 pl-0 md:pl-12">
                          <div>
                            <h3 className="text-2xl text-on-surface">{post.title}</h3>
                          </div>

                          <p className="text-base leading-relaxed text-on-surface-variant whitespace-pre-wrap">
                            {post.content}
                          </p>

                          {post.photos && post.photos.length > 0 && (
                            <div className="space-y-3">
                              {post.photos.length > 1 ? (
                                <div className="grid grid-cols-2 gap-1 overflow-hidden rounded-[28px] border border-outline-variant/10 bg-[#f3ebe4] p-1">
                                  {post.photos.slice(0, 4).map((photo, index) => {
                                    const previewCount = Math.min(post.photos!.length, 4);
                                    const hiddenPhotoCount = post.photos!.length - 4;

                                    return (
                                      <button
                                        key={`${post.id}-grid-photo-${index}`}
                                        type="button"
                                        className={`group relative overflow-hidden rounded-[22px] bg-[#eadfd6] ${getFeedPhotoGridTileClassName(index, previewCount)}`}
                                        onClick={(event) => openImageViewer(post.photos ?? [], index, post.title, event)}
                                      >
                                        <img
                                          src={photo}
                                          alt={`${post.title} photo ${index + 1}`}
                                          className="h-full w-full object-cover transition-transform duration-300 ease-out group-hover:scale-[1.02]"
                                        />
                                        {index === previewCount - 1 && hiddenPhotoCount > 0 ? (
                                          <span className="absolute inset-0 flex items-center justify-center bg-black/45 text-2xl font-semibold text-white backdrop-blur-[2px]">
                                            +{hiddenPhotoCount}
                                          </span>
                                        ) : null}
                                      </button>
                                    );
                                  })}
                                </div>
                              ) : (
                                <div className="relative overflow-hidden rounded-[28px] border border-outline-variant/10 bg-[#f3ebe4]">
                                  <button
                                    type="button"
                                    className="block w-full"
                                    onClick={(event) =>
                                      openImageViewer(
                                        post.photos ?? [],
                                        getPhotoIndex(post.id, post.photos?.length ?? 0),
                                        post.title,
                                        event,
                                      )}
                                  >
                                    <img
                                      src={post.photos[getPhotoIndex(post.id, post.photos.length)]}
                                      alt={`${post.title} photo ${getPhotoIndex(post.id, post.photos.length) + 1}`}
                                      className="h-[320px] w-full object-cover md:h-[420px]"
                                    />
                                  </button>
                                  {post.photos.length > 1 && (
                                    <>
                                      <button
                                        type="button"
                                        className="absolute left-4 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm transition-colors hover:bg-black/60"
                                        onClick={(event) => {
                                          event.stopPropagation();
                                          shiftPostPhoto(post.id, post.photos?.length ?? 0, "prev");
                                        }}
                                        aria-label="Previous image"
                                      >
                                        <span className="material-symbols-outlined">chevron_left</span>
                                      </button>
                                      <button
                                        type="button"
                                        className="absolute right-4 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm transition-colors hover:bg-black/60"
                                        onClick={(event) => {
                                          event.stopPropagation();
                                          shiftPostPhoto(post.id, post.photos?.length ?? 0, "next");
                                        }}
                                        aria-label="Next image"
                                      >
                                        <span className="material-symbols-outlined">chevron_right</span>
                                      </button>
                                      <div className="absolute bottom-4 left-1/2 flex -translate-x-1/2 items-center gap-2 rounded-full bg-black/35 px-3 py-2 text-white/90 backdrop-blur-sm">
                                        {post.photos.map((_, index) => (
                                          <button
                                            key={`${post.id}-photo-dot-${index}`}
                                            type="button"
                                            className={`h-2.5 w-2.5 rounded-full transition-all ${
                                              index === getPhotoIndex(post.id, post.photos!.length)
                                                ? "bg-white"
                                                : "bg-white/45 hover:bg-white/70"
                                            }`}
                                            aria-label={`View image ${index + 1}`}
                                            onClick={(event) => {
                                              event.stopPropagation();
                                              setPostPhotoIndices((prev) => ({
                                                ...prev,
                                                [String(post.id)]: index,
                                              }));
                                            }}
                                          />
                                        ))}
                                      </div>
                                    </>
                                  )}
                                </div>
                              )}
                            </div>
                          )}

                          {post.attachments && post.attachments.length > 0 && (
                            <div
                              className={`rounded-2xl px-4 py-1 ${isDarkMode ? "border border-[#3b3732] bg-[#262321]" : "border border-[#ecd8cf] bg-[#fff8f3]"}`}
                              onClick={(event) => {
                                event.stopPropagation();
                              }}
                              onKeyDown={(event) => {
                                event.stopPropagation();
                              }}
                            >
                              <AttachmentList attachments={post.attachments} />
                            </div>
                          )}

                          <div className="flex items-center justify-between border-t border-outline-variant/10 pt-4 text-outline">
                            <div className="flex items-center gap-8">
                              <button
                                className="flex items-center gap-2 transition-colors hover:text-[#a14b2f]"
                                type="button"
                                onClick={(event) => {
                                  event.stopPropagation();
                                  void handleReact(post.id);
                                }}
                                disabled={reactingPostIds.includes(post.id)}
                              >
                                <AnimatedHeartIcon liked={likedPostIds.includes(post.id)} />
                                <span className="text-xs font-bold uppercase tracking-widest">
                                  {post.reaction ?? 0}
                                </span>
                              </button>
                              <button
                                className="flex items-center gap-2 text-on-surface transition-colors hover:text-[#a14b2f]"
                                type="button"
                                onClick={(event) => {
                                  event.stopPropagation();
                                  openCommentModal(post.id, event.currentTarget);
                                }}
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
                              onClick={(event) => {
                                event.stopPropagation();
                                toggleBookmarked(post.id);
                              }}
                              title="Bookmark announcement"
                            >
                              <AnimatedBookmarkIcon
                                bookmarked={bookmarkedPostIds.includes(post.id)}
                                animate={bookmarkAnimatingPostIds.includes(post.id)}
                              />
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
          <div className={`min-w-0 ${departmentLayout ? "md:-mt-20" : "xl:col-span-4"}`}>
            <div className={`space-y-6 ${departmentLayout ? "md:sticky md:top-28 md:max-h-[calc(100vh-8rem)] md:overflow-y-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden" : ""}`}>
            {departmentLayout && (
              <section className="overflow-hidden rounded-[28px] border border-[#e4c0ae] bg-gradient-to-br from-[#d98d63] via-[#bf6e49] to-[#a86446] p-4 text-white shadow-xl">
                <div className="mx-auto flex max-w-[17rem] items-center justify-center gap-3 rounded-2xl border border-white/10 bg-white/10 px-4 py-3 backdrop-blur-sm">
                  <span className="material-symbols-outlined text-white/75">search</span>
                  <input
                    aria-label="Temporary news search"
                    className="w-full bg-transparent text-center text-sm text-white outline-none placeholder:text-center placeholder:text-white/55"
                    placeholder={copy.searchPlaceholder}
                    readOnly
                  />
                </div>
              </section>
            )}
            {departmentLayout && (
              <section className="overflow-hidden rounded-[28px] border border-[#e4c0ae] bg-gradient-to-br from-[#d98d63] via-[#bf6e49] to-[#a86446] p-5 text-white shadow-xl">
                <div className="flex flex-col items-center gap-4 text-center">
                  <div className="mx-auto max-w-[17rem]">
                    <span className="inline-flex rounded-full border border-white/20 bg-white/10 px-3 py-1 text-[10px] font-bold uppercase tracking-[0.22em] text-white/90">
                      {copy.badge}
                    </span>
                    <h2 className="mt-3 font-headline text-[1.8rem] leading-[1.02]">ResilienceHub Temporary News Desk</h2>
                    <p className="mt-3 text-sm leading-relaxed text-white/80">
                      {copy.intro}
                    </p>
                  </div>

                  <div className="grid w-full max-w-[17rem] gap-3">
                    <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                      <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">
                        Active advisories
                      </p>
                      <p className="mt-2 font-headline text-4xl">{loading ? "..." : String(readinessCount).padStart(2, "0")}</p>
                      <p className="mt-1 text-xs text-white/70">Live alerts, warnings, and situational reports</p>
                    </div>
                    <div className="rounded-2xl border border-white/10 bg-white/10 p-4 text-center backdrop-blur-sm">
                      <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">
                        Coordination mode
                      </p>
                      <p className="mt-2 font-headline text-2xl">Steady Watch</p>
                      <p className="mt-1 text-xs text-white/70">Preparedness bulletin enabled</p>
                    </div>
                  </div>
                </div>
              </section>
            )}
            <Card className={warmPanelClassName}>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                Active Readiness
              </p>
              <div className="mt-5 space-y-5">
                {readinessPosts.length === 0 ? (
                  <div className={`rounded-2xl p-4 ${isDarkMode ? "border border-[#3b3732] bg-[#2a2724]" : "border border-[#ecd8cf] bg-[#f7efe7]"}`}>
                    <p className="text-sm leading-relaxed text-on-surface-variant">
                      Published summaries for Alert, Warning, and Situational Report posts will appear here once departments publish them.
                    </p>
                  </div>
                ) : (
                  readinessPosts.map((post) => (
                    <div
                      key={post.id}
                      className={`group cursor-default rounded-2xl p-4 transition-shadow hover:shadow-sm ${isDarkMode ? "border border-[#3b3732] bg-[#2a2724]" : "border border-[#ecd8cf] bg-[#f7efe7]"}`}
                    >
                      <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                        {readinessCategoryLabels[post.category as keyof typeof readinessCategoryLabels] ?? post.category.replace("_", " ")}
                      </p>
                      <p className="mt-2 text-lg leading-tight text-on-surface transition-colors group-hover:text-[#a14b2f]">
                        {summarizePostContent(post.content)}
                      </p>
                      <p className="mt-2 text-xs text-outline">{buildReadinessMeta(post)}</p>
                    </div>
                  ))
                )}
              </div>
            </Card>

            <Card className={warmPanelClassName}>
              <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">
                Who to follow
              </p>
              <div className="mt-5 space-y-4">
                {followDepartments.length === 0 ? (
                  <div className={`rounded-2xl p-4 ${isDarkMode ? "border border-[#3b3732] bg-[#2a2724]" : "border border-[#ecd8cf] bg-[#f7efe7]"}`}>
                    <p className="text-sm leading-relaxed text-on-surface-variant">
                      Department accounts will appear here once profiles are available in the directory.
                    </p>
                  </div>
                ) : (
                  followDepartments.map((department) => {
                    const publisherPath = `/departments/${department.user_id}`;
                    const profileImage = department.profile_picture || department.profile_photo;

                    return (
                      <Link
                        key={department.id}
                        className="flex items-center gap-3 rounded-2xl transition-colors hover:bg-[#fffaf6]"
                        to={publisherPath}
                      >
                        <div className={`flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-full bg-gradient-to-br ${getFollowAccent(department.type)} text-[#5b3427] shadow-sm`}>
                          {profileImage ? (
                            <img
                              alt={`${department.name} profile`}
                              className="h-full w-full object-cover"
                              src={profileImage}
                            />
                          ) : (
                            <span className="material-symbols-outlined text-[22px]">{getFollowSymbol(department.type)}</span>
                          )}
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-base font-semibold text-on-surface">{department.name}</p>
                          <p className="truncate text-sm text-on-surface-variant">{formatDepartmentHandle(department.name)}</p>
                        </div>
                        <span className={`shrink-0 rounded-full px-4 py-2 text-sm font-semibold transition-colors ${isDarkMode ? "border border-[#3b3732] bg-[#2a2724] text-[#f0e2d6] hover:bg-[#332f2b]" : "border border-[#d7c1b5] bg-white text-[#5f4f46] hover:bg-[#f8efe8]"}`}>
                          Follow
                        </span>
                      </Link>
                    );
                  })
                )}
              </div>
              {followDepartments.length > 0 && (
                <button
                  type="button"
                  className="mt-5 text-sm font-medium text-[#a14b2f] transition-colors hover:text-[#7b3822]"
                >
                  Show more
                </button>
              )}
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
      </div>

      {activeImageViewer && (
        <div className="fixed inset-0 z-[72] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md md:p-8">
          <button
            type="button"
            className="absolute left-4 top-4 flex h-11 w-11 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
            aria-label="Close image viewer"
            onClick={() => setActiveImageViewer(null)}
          >
            <span className="material-symbols-outlined">close</span>
          </button>

          {activeImageViewer.photos.length > 1 && (
            <button
              type="button"
              className="absolute left-4 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
              aria-label="Previous image"
              onClick={() => shiftImageViewer("prev")}
            >
              <span className="material-symbols-outlined">arrow_back</span>
            </button>
          )}

          <div className="flex max-h-[90vh] w-full max-w-6xl flex-col items-center justify-center gap-4">
            <img
              src={activeImageViewer.photos[activeImageViewer.index]}
              alt={`${activeImageViewer.title} image ${activeImageViewer.index + 1}`}
              className="max-h-[78vh] w-auto max-w-full rounded-[28px] object-contain shadow-[0_24px_60px_rgba(0,0,0,0.4)]"
            />
            {activeImageViewer.photos.length > 1 && (
              <div className="rounded-full bg-white/10 px-4 py-2 text-sm font-medium text-white backdrop-blur-sm">
                {activeImageViewer.index + 1} / {activeImageViewer.photos.length}
              </div>
            )}
          </div>

          {activeImageViewer.photos.length > 1 && (
            <button
              type="button"
              className="absolute right-4 top-1/2 flex h-12 w-12 -translate-y-1/2 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
              aria-label="Next image"
              onClick={() => shiftImageViewer("next")}
            >
              <span className="material-symbols-outlined">arrow_forward</span>
            </button>
          )}
        </div>
      )}

      {activeCommentPost && (
        <div className="dispatch-comment-overlay fixed inset-0 z-[70] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div
            className={`dispatch-comment-modal relative flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl ${popupSurfaceClassName} ${popupPanelShadowClassName}`}
            style={
              {
                "--dispatch-comment-from-x": `${commentModalOrigin.x}px`,
                "--dispatch-comment-from-y": `${commentModalOrigin.y}px`,
              } as CSSProperties
            }
          >
              {(() => {
                const publisherPath = `/departments/${activeCommentPost.uploader}`;
                return (
              <div className={`flex items-center gap-4 px-8 py-6 backdrop-blur-sm ${popupHeaderClassName}`}>
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
                    <p className="mt-0.5 text-[10px] font-bold uppercase tracking-widest text-outline transition-opacity duration-200 ease-out group-hover/publisher:opacity-55">
                      {new Date(activeCommentPost.created_at).toLocaleString()}
                    </p>
                  </Link>
                </DepartmentHoverPreview>
                {activeCommentLocationLabel ? (
                  <span className={`ml-auto inline-flex max-w-[260px] items-center gap-1 rounded-full px-2.5 py-1 text-[10px] ${warmTabClassName}`}>
                    <span className="material-symbols-outlined text-[14px]">location_on</span>
                    <span className="truncate normal-case tracking-normal">{activeCommentLocationLabel}</span>
                  </span>
                ) : null}
                <span className={`ml-auto inline-flex items-center gap-1 rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${warmTabClassName}`}>
                  <span className="material-symbols-outlined text-[14px]">
                    {(categoryStyles[activeCommentPost.category] ?? { icon: "article" }).icon}
                  </span>
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
                  </div>

                  <p className="text-[1.125rem] leading-[1.6] text-on-surface whitespace-pre-wrap">
                    {activeCommentPost.content}
                  </p>

                  {activeCommentPost.photos && activeCommentPost.photos.length > 0 && (
                    <>
                      {activeCommentPost.photos.length >= 4 ? (
                        <div className="grid grid-cols-2 gap-2 overflow-hidden rounded-[24px] border border-outline-variant/10 bg-[#f3ebe4] p-2">
                          {activeCommentPost.photos.map((photo, index) => (
                            <button
                              key={`detail-grid-photo-${index}`}
                              type="button"
                              className={`group relative overflow-hidden rounded-[20px] bg-[#eadfd6] ${getFeedPhotoGridTileClassName(index, activeCommentPost.photos!.length)}`}
                              onClick={(event) =>
                                openImageViewer(activeCommentPost.photos ?? [], index, activeCommentPost.title, event)
                              }
                            >
                              <img
                                src={photo}
                                alt={`${activeCommentPost.title} photo ${index + 1}`}
                                className="h-full w-full object-cover transition-transform duration-300 ease-out group-hover:scale-[1.02]"
                              />
                            </button>
                          ))}
                        </div>
                      ) : (
                        <div className="relative overflow-hidden rounded-[24px] border border-outline-variant/10 bg-[#f3ebe4]">
                          <button
                            type="button"
                            className="block w-full"
                            onClick={(event) =>
                              openImageViewer(
                                activeCommentPost.photos ?? [],
                                getPhotoIndex(activeCommentPost.id, activeCommentPost.photos?.length ?? 0),
                                activeCommentPost.title,
                                event,
                              )}
                          >
                            <img
                              src={activeCommentPost.photos[getPhotoIndex(activeCommentPost.id, activeCommentPost.photos.length)]}
                              alt={activeCommentPost.title}
                              className="block h-auto w-full"
                            />
                          </button>
                          {activeCommentPost.photos.length > 1 && (
                            <>
                              <button
                                type="button"
                                className="absolute left-4 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm transition-colors hover:bg-black/60"
                                onClick={() => shiftPostPhoto(activeCommentPost.id, activeCommentPost.photos?.length ?? 0, "prev")}
                                aria-label="Previous image"
                              >
                                <span className="material-symbols-outlined">chevron_left</span>
                              </button>
                              <button
                                type="button"
                                className="absolute right-4 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm transition-colors hover:bg-black/60"
                                onClick={() => shiftPostPhoto(activeCommentPost.id, activeCommentPost.photos?.length ?? 0, "next")}
                                aria-label="Next image"
                              >
                                <span className="material-symbols-outlined">chevron_right</span>
                              </button>
                              <div className="absolute bottom-4 left-1/2 flex -translate-x-1/2 items-center gap-2 rounded-full bg-black/35 px-3 py-2 text-white/90 backdrop-blur-sm">
                                {activeCommentPost.photos.map((_, index) => (
                                  <button
                                    key={`detail-photo-dot-${index}`}
                                    type="button"
                                    className={`h-2.5 w-2.5 rounded-full transition-all ${
                                      index === getPhotoIndex(activeCommentPost.id, activeCommentPost.photos!.length)
                                        ? "bg-white"
                                        : "bg-white/45 hover:bg-white/70"
                                    }`}
                                    aria-label={`View image ${index + 1}`}
                                    onClick={() =>
                                      setPostPhotoIndices((prev) => ({
                                        ...prev,
                                        [String(activeCommentPost.id)]: index,
                                      }))
                                    }
                                  />
                                ))}
                              </div>
                            </>
                          )}
                        </div>
                      )}
                    </>
                  )}

                  <div className="flex items-center justify-between border-y border-outline-variant/10 py-4">
                    <div className="flex items-center gap-8">
                      <button
                        className="group flex items-center gap-2 text-on-surface-variant transition-colors hover:text-[#a14b2f]"
                        type="button"
                        onClick={() => void handleReact(activeCommentPost.id)}
                        disabled={reactingPostIds.includes(activeCommentPost.id)}
                      >
                        <AnimatedHeartIcon liked={likedPostIds.includes(activeCommentPost.id)} />
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
                    <button
                      className="text-on-surface-variant transition-colors hover:text-on-surface"
                      type="button"
                      onClick={() => toggleBookmarked(activeCommentPost.id)}
                    >
                      <AnimatedBookmarkIcon
                        bookmarked={bookmarkedPostIds.includes(activeCommentPost.id)}
                        animate={bookmarkAnimatingPostIds.includes(activeCommentPost.id)}
                      />
                    </button>
                  </div>
                </div>

              </article>

              <section className={`px-8 py-10 ${isDarkMode ? "bg-[#1f1d1b]" : "bg-[#f7efe7]"}`}>
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
        <div className="dispatch-comment-overlay fixed inset-0 z-[75] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div
            className={`dispatch-comment-modal relative flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl ${popupSurfaceClassName} ${popupPanelShadowClassName}`}
            style={
              {
                "--dispatch-comment-from-x": `${createModalOrigin.x}px`,
                "--dispatch-comment-from-y": `${createModalOrigin.y}px`,
              } as CSSProperties
            }
          >
            <div className={`flex items-center gap-4 px-8 py-6 backdrop-blur-sm ${popupHeaderClassName}`}>
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

      {deleteConfirmPost && (
        <div className="fixed inset-0 z-[75] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div className={`w-full max-w-md rounded-[28px] p-6 ${popupSurfaceClassName} ${popupPanelShadowClassName}`}>
            <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
              Delete post
            </p>
            <h3 className="mt-3 text-2xl text-on-surface">Are you sure you want to delete this post?</h3>
            <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">
              This will remove the announcement, its comments, its reaction records, and the related feed data connected to it.
            </p>
            {deleteError && (
              <div className="mt-4 rounded-2xl border border-[#d8b7aa] bg-[#fff1e9] px-4 py-3 text-sm text-[#89391e]">
                {deleteError}
              </div>
            )}
            <div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
              <button
                type="button"
                className={`rounded-full px-5 py-3 text-sm font-semibold ${warmTabClassName}`}
                onClick={() => {
                  if (deletingPostId !== deleteConfirmPost.id) {
                    setDeleteConfirmPost(null);
                    setDeleteError(null);
                  }
                }}
                disabled={deletingPostId === deleteConfirmPost.id}
              >
                Cancel
              </button>
              <button
                type="button"
                className="rounded-full bg-[#a14b2f] px-5 py-3 text-sm font-semibold text-white transition-colors hover:bg-[#89391e] disabled:cursor-not-allowed disabled:opacity-70"
                onClick={() => void handleDeletePost()}
                disabled={deletingPostId === deleteConfirmPost.id}
              >
                {deletingPostId === deleteConfirmPost.id ? "Deleting..." : "Delete post"}
              </button>
            </div>
          </div>
        </div>
      )}

      {editPost && (
        <div className="fixed inset-0 z-[74] flex items-center justify-center bg-on-surface/40 p-4 backdrop-blur-md md:p-8">
          <div className={`relative flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-xl ${popupSurfaceClassName} ${popupPanelShadowClassName}`}>
            <div className={`flex items-center justify-between px-8 py-6 backdrop-blur-sm ${popupHeaderClassName}`}>
              <div>
                <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                  Edit post
                </p>
                <h3 className="mt-2 text-2xl text-on-surface">Update this announcement</h3>
              </div>
              <button
                className={`rounded-full p-2 transition-colors hover:text-on-surface ${warmTabClassName}`}
                type="button"
                onClick={() => setEditPost(null)}
              >
                <span className="material-symbols-outlined">close</span>
              </button>
            </div>

            <div className="min-h-0 overflow-y-auto px-8 py-6">
              <DepartmentCreatePostForm
                mode="edit"
                postId={editPost.id}
                initialValues={{
                  title: editPost.title,
                  content: editPost.content,
                  category: editPost.category,
                  location: editPost.location ?? "",
                }}
                submitLabel="Save changes"
                onCancel={() => setEditPost(null)}
                onSuccess={async () => {
                  setEditPost(null);
                  await fetchPosts(false);
                }}
              />
            </div>
          </div>
        </div>
      )}
      </AppShell>
    </>
  );
}

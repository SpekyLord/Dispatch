// Feed post detail — full view of a single department announcement.

import { useCallback, useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";

import type { FeedDepartmentPreview } from "@/components/feed/department-hover-preview";
import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { AttachmentList } from "@/components/feed/attachment-list";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type Post = {
  id: string | number;
  uploader: string;
  title: string;
  content: string;
  category: string;
  location?: string | null;
  is_pinned: boolean;
  created_at: string;
  photos?: string[];
  attachments?: string[];
  image_urls?: string[];
  department?: FeedDepartmentPreview | null;
};

const categoryStyles: Record<string, { bg: string; text: string }> = {
  alert: { bg: "bg-red-100", text: "text-red-800" },
  warning: { bg: "bg-orange-100", text: "text-orange-800" },
  safety_tip: { bg: "bg-blue-100", text: "text-blue-800" },
  update: { bg: "bg-green-100", text: "text-green-800" },
  situational_report: { bg: "bg-purple-100", text: "text-purple-800" },
};

export function FeedDetailPage() {
  const { postId } = useParams<{ postId: string }>();
  const accessToken = useSessionStore((state) => state.accessToken);
  const [post, setPost] = useState<Post | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchPost = useCallback((showLoader = true) => {
    if (!postId) {
      return Promise.resolve();
    }
    if (showLoader) {
      setLoading(true);
    }

    return apiRequest<{ post: Post }>(`/api/feed/${postId}`)
      .then((res) => setPost(res.post))
      .catch(() => {})
      .finally(() => {
        if (showLoader) {
          setLoading(false);
        }
      });
  }, [postId]);

  useEffect(() => {
    if (!postId) return;
    queueMicrotask(() => {
      void fetchPost();
    });
  }, [postId, fetchPost]);

  useEffect(() => {
    if (!postId) {
      return;
    }

    const subscription = subscribeToTable(
      "department_feed_posts",
      () => {
        void fetchPost(false);
      },
      { accessToken, filter: `id=eq.${postId}` },
    );
    return () => subscription.unsubscribe();
  }, [accessToken, postId, fetchPost]);

  if (loading) {
    return (
      <AppShell subtitle="Announcement" title="Loading...">
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl animate-pulse">hourglass_empty</span>
        </Card>
      </AppShell>
    );
  }

  if (!post) {
    return (
      <AppShell subtitle="Announcement" title="Not Found">
        <Card className="py-16 text-center text-on-surface-variant">Post not found.</Card>
      </AppShell>
    );
  }

  const catStyle = categoryStyles[post.category] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant" };

  return (
    <AppShell subtitle="Announcement" title={post.title}>
      <Link to="/feed" className="text-sm text-[#D97757] hover:underline mb-6 inline-flex items-center gap-1">
        <span className="material-symbols-outlined text-[16px]">arrow_back</span>
        Back to Feed
      </Link>

      <Card className="mx-auto max-w-3xl">
        <div className="flex items-center gap-3 mb-4">
          <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${catStyle.bg} ${catStyle.text}`}>
            {post.category.replace("_", " ")}
          </span>
          {post.is_pinned && (
            <span className="flex items-center gap-0.5 text-[10px] text-[#D97757] font-semibold uppercase">
              <span className="material-symbols-outlined text-[14px]">push_pin</span>
              Pinned
            </span>
          )}
          <span className="ml-auto text-[10px] text-outline">{new Date(post.created_at).toLocaleString()}</span>
        </div>

        <h2 className="font-headline text-2xl text-on-surface mb-2">{post.title}</h2>

        {post.department && (
          <div className="mb-6 flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center overflow-hidden rounded-full bg-surface-container-highest text-on-surface-variant">
              <Link className="flex h-full w-full items-center justify-center" to={`/departments/${post.uploader}`}>
                {post.department.profile_picture ? (
                  <img
                    src={post.department.profile_picture}
                    alt={`${post.department.name} profile`}
                    className="h-full w-full object-cover"
                  />
                ) : (
                  <span className="material-symbols-outlined">campaign</span>
                )}
              </Link>
            </div>
            <p className="text-xs text-on-surface-variant">
              Published by{" "}
              <Link className="font-semibold capitalize text-on-surface hover:text-[#a14b2f]" to={`/departments/${post.uploader}`}>
                {post.department.name}
              </Link>{" "}
              ({post.department.type})
            </p>
          </div>
        )}

        {post.location && (
          <p className="mb-6 text-sm text-on-surface-variant">
            <span className="font-semibold text-on-surface">Location:</span> {post.location}
          </p>
        )}

        <div className="prose prose-sm text-on-surface-variant leading-relaxed whitespace-pre-wrap">{post.content}</div>

        {post.photos && post.photos.length > 0 && (
          <div className="mt-6 flex gap-3 overflow-x-auto">
            {post.photos.map((url, i) => (
              <img key={i} src={url} alt={`Attachment ${i + 1}`} className="h-48 rounded-lg object-cover border border-outline-variant/10" />
            ))}
          </div>
        )}

        {post.attachments && post.attachments.length > 0 && (
          <div className="mt-6">
            <AttachmentList attachments={post.attachments} />
          </div>
        )}
      </Card>
    </AppShell>
  );
}

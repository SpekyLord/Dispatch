// Feed post detail — full view of a single department announcement.

import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";

type Post = {
  id: string;
  title: string;
  content: string;
  category: string;
  is_pinned: boolean;
  created_at: string;
  image_urls?: string[];
  department?: { id: string; name: string; type: string } | null;
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
  const [post, setPost] = useState<Post | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!postId) return;
    apiRequest<{ post: Post }>(`/api/feed/${postId}`)
      .then((res) => setPost(res.post))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [postId]);

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
          <p className="text-xs text-on-surface-variant mb-6">
            Published by <span className="font-semibold capitalize">{post.department.name}</span> ({post.department.type})
          </p>
        )}

        <div className="prose prose-sm text-on-surface-variant leading-relaxed whitespace-pre-wrap">{post.content}</div>

        {post.image_urls && post.image_urls.length > 0 && (
          <div className="mt-6 flex gap-3 overflow-x-auto">
            {post.image_urls.map((url, i) => (
              <img key={i} src={url} alt={`Attachment ${i + 1}`} className="h-48 rounded-lg object-cover border border-outline-variant/10" />
            ))}
          </div>
        )}
      </Card>
    </AppShell>
  );
}

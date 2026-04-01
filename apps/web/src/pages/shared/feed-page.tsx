// Public feed — lists department announcements with category filter and post detail view.

import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";

import type { FeedDepartmentPreview } from "@/components/feed/department-hover-preview";
import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
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
  is_mesh_origin?: boolean;
};

// Category badge styles
const categoryStyles: Record<string, { bg: string; text: string; icon: string }> = {
  alert: { bg: "bg-red-100", text: "text-red-800", icon: "warning" },
  warning: { bg: "bg-orange-100", text: "text-orange-800", icon: "error_outline" },
  safety_tip: { bg: "bg-blue-100", text: "text-blue-800", icon: "health_and_safety" },
  update: { bg: "bg-green-100", text: "text-green-800", icon: "info" },
  situational_report: { bg: "bg-purple-100", text: "text-purple-800", icon: "summarize" },
};

export function FeedPage() {
  const accessToken = useSessionStore((state) => state.accessToken);
  const [posts, setPosts] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [categoryFilter, setCategoryFilter] = useState("");

  const fetchPosts = useCallback((showLoader = true) => {
    if (showLoader) {
      setLoading(true);
    }
    const qs = categoryFilter ? `?category=${categoryFilter}` : "";
    return apiRequest<{ posts: Post[] }>(`/api/feed${qs}`)
      .then((res) => setPosts(res.posts))
      .catch(() => {})
      .finally(() => {
        if (showLoader) {
          setLoading(false);
        }
      });
  }, [categoryFilter]);

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

  return (
    <AppShell subtitle="Public information" title="Community Feed">
      {/* Category filter */}
      <div className="flex items-center gap-3 mb-8">
        <select
          className="aegis-input w-auto min-w-[160px]"
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
        >
          <option value="">All categories</option>
          <option value="alert">Alerts</option>
          <option value="warning">Warnings</option>
          <option value="safety_tip">Safety Tips</option>
          <option value="update">Updates</option>
          <option value="situational_report">Situational Reports</option>
        </select>
        <span className="text-xs text-on-surface-variant">{posts.length} post{posts.length !== 1 ? "s" : ""}</span>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots className="mb-4" sizeClassName="h-5 w-5" />
          Loading feed...
        </Card>
      ) : posts.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">newspaper</span>
          <p className="text-on-surface-variant">No announcements yet. Check back later.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {posts.map((post) => {
            const catStyle = categoryStyles[post.category] ?? { bg: "bg-surface-container-highest", text: "text-on-surface-variant", icon: "article" };
            return (
              <Link key={post.id} to={`/feed/${post.id}`}>
                <Card className="hover:shadow-glass transition-all hover:-translate-y-0.5 cursor-pointer">
                  <div className="flex items-start gap-4">
                    <div className={`flex-shrink-0 w-10 h-10 overflow-hidden rounded-lg flex items-center justify-center ${catStyle.bg} ${catStyle.text}`}>
                      {post.department?.profile_picture ? (
                        <img
                          src={post.department.profile_picture}
                          alt={`${post.department.name} profile`}
                          className="h-full w-full object-cover"
                        />
                      ) : (
                        <span className="material-symbols-outlined">{catStyle.icon}</span>
                      )}
                    </div>
                    <div className="flex-grow min-w-0">
                      <div className="flex items-start justify-between gap-3">
                        <h3 className="text-sm font-semibold text-on-surface">
                          {post.is_pinned && <span className="material-symbols-outlined text-[14px] text-[#D97757] mr-1 align-middle">push_pin</span>}
                          {post.title}
                        </h3>
                        <div className="flex items-center gap-1.5 shrink-0">
                          {post.is_mesh_origin && (
                            <span className="rounded-md bg-cyan-100 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-cyan-800">Mesh</span>
                          )}
                          <span className={`rounded-md px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest ${catStyle.bg} ${catStyle.text}`}>
                            {post.category.replace("_", " ")}
                          </span>
                        </div>
                      </div>
                      <p className="text-xs text-on-surface-variant mt-1 line-clamp-2">{post.content}</p>
                      {post.photos && post.photos.length > 0 && (
                        <div className="mt-3 overflow-hidden rounded-lg border border-outline-variant/10">
                          <img
                            src={post.photos[0]}
                            alt={post.title}
                            className="h-40 w-full object-cover"
                          />
                        </div>
                      )}
                      <div className="mt-2 flex items-center gap-2 text-[10px] text-outline">
                        {post.department && (
                          <span className="font-medium capitalize">{post.department.name}</span>
                        )}
                        {post.location && <span>{post.location}</span>}
                        {post.attachments && post.attachments.length > 0 && (
                          <span>{post.attachments.length} attachment{post.attachments.length !== 1 ? "s" : ""}</span>
                        )}
                        <span>{new Date(post.created_at).toLocaleString()}</span>
                      </div>
                    </div>
                  </div>
                </Card>
              </Link>
            );
          })}
        </div>
      )}
    </AppShell>
  );
}

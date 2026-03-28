// Department post creation — verified departments can publish announcements to the citizen feed.

import { useState } from "react";
import { useNavigate } from "react-router-dom";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";

const POST_CATEGORIES = [
  { value: "alert", label: "Alert" },
  { value: "warning", label: "Warning" },
  { value: "safety_tip", label: "Safety Tip" },
  { value: "update", label: "Update" },
  { value: "situational_report", label: "Situational Report" },
];

export function DepartmentCreatePostPage() {
  const navigate = useNavigate();
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [category, setCategory] = useState("update");
  const [isPinned, setIsPinned] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim() || !content.trim()) { setError("Title and content are required."); return; }
    setLoading(true); setError(null);
    try {
      await apiRequest("/api/departments/posts", {
        method: "POST",
        body: JSON.stringify({
          title: title.trim(),
          content: content.trim(),
          category,
          is_pinned: isPinned,
        }),
      });
      navigate("/feed");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to create post.");
    } finally { setLoading(false); }
  }

  return (
    <AppShell subtitle="Publish announcement" title="Create Post">
      <Card className="mx-auto max-w-2xl">
        <form className="space-y-5" onSubmit={handleSubmit}>
          {error && (
            <div className="rounded-md bg-error-container/20 border border-error/20 px-4 py-3 text-sm text-error">{error}</div>
          )}

          <div>
            <label className="aegis-label">Title</label>
            <input type="text" className="aegis-input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Announcement title" />
          </div>

          <div>
            <label className="aegis-label">Content</label>
            <textarea className="aegis-input min-h-[120px]" value={content} onChange={(e) => setContent(e.target.value)} placeholder="Write your announcement..." />
          </div>

          <div>
            <label className="aegis-label">Category</label>
            <select className="aegis-input" value={category} onChange={(e) => setCategory(e.target.value)}>
              {POST_CATEGORIES.map((c) => (
                <option key={c.value} value={c.value}>{c.label}</option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2">
            <input type="checkbox" id="pinned" checked={isPinned} onChange={(e) => setIsPinned(e.target.checked)} className="rounded border-outline-variant" />
            <label htmlFor="pinned" className="text-sm text-on-surface-variant">Pin this post</label>
          </div>

          <div className="flex gap-3 pt-2">
            <Button type="submit" variant="secondary" disabled={loading}>
              {loading ? "Publishing..." : "Publish"}
            </Button>
            <Button type="button" variant="outline" onClick={() => navigate(-1)}>Cancel</Button>
          </div>
        </form>
      </Card>
    </AppShell>
  );
}

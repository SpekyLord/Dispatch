// Department post creation — verified departments can publish announcements to the citizen feed.

import { useNavigate } from "react-router-dom";

import { DepartmentCreatePostForm } from "@/components/feed/department-create-post-form";
import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";

export function DepartmentCreatePostPage() {
  const navigate = useNavigate();

  return (
    <AppShell subtitle="Publish announcement" title="Create Post">
      <Card className="mx-auto max-w-2xl">
        <DepartmentCreatePostForm
          onCancel={() => navigate(-1)}
          onSuccess={() => navigate("/department/news-feed")}
        />
      </Card>
    </AppShell>
  );
}

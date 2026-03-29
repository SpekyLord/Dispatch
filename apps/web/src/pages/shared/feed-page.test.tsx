import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { FeedPage } from "./feed-page";

const realtimeMock = vi.hoisted(() => ({
  subscriptions: [] as Array<{
    table: string;
    onChange: (payload: unknown) => void;
    options?: { accessToken?: string | null; filter?: string };
  }>,
}));

vi.mock("@/lib/realtime/supabase", () => ({
  subscribeToTable: (
    table: string,
    onChange: (payload: unknown) => void,
    options?: { accessToken?: string | null; filter?: string },
  ) => {
    realtimeMock.subscriptions.push({ table, onChange, options });
    return { unsubscribe: vi.fn() };
  },
}));

describe("FeedPage", () => {
  beforeEach(() => {
    localStorage.clear();
    realtimeMock.subscriptions.length = 0;
    useSessionStore.setState({
      user: { id: "citizen-1", email: "citizen@test.com", role: "citizen", full_name: "Citizen" },
      accessToken: "citizen-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("renders public posts and refreshes when a new announcement arrives", async () => {
    let posts = [
      {
        id: "post-1",
        title: "Flood Advisory",
        content: "Expect heavy rainfall in low-lying areas.",
        category: "warning",
        is_pinned: true,
        created_at: "2026-03-29T02:00:00Z",
        department: { id: "dept-1", name: "MDRRMO", type: "disaster" },
      },
    ];

    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      new Response(JSON.stringify({ posts }), { status: 200 }),
    );

    render(
      <MemoryRouter>
        <FeedPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("Flood Advisory")).toBeInTheDocument();
    });
    expect(screen.getByText("1 post")).toBeInTheDocument();
    expect(realtimeMock.subscriptions.map((subscription) => subscription.table)).toEqual(["department_feed_posts"]);

    posts = [
      ...posts,
      {
        id: "post-2",
        title: "Road Closure",
        content: "Avoid the east bridge while clearing operations continue.",
        category: "update",
        is_pinned: false,
        created_at: "2026-03-29T02:05:00Z",
        department: { id: "dept-2", name: "Traffic Unit", type: "police" },
      },
    ];

    realtimeMock.subscriptions[0]?.onChange({});

    await waitFor(() => {
      expect(screen.getByText("Road Closure")).toBeInTheDocument();
    });
    expect(screen.getByText("2 posts")).toBeInTheDocument();
  });
});

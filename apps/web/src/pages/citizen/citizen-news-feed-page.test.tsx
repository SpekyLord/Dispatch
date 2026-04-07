import { render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { CitizenNewsFeedPage } from "./citizen-news-feed-page";

vi.mock("@/lib/realtime/supabase", () => ({
  subscribeToTable: () => ({ unsubscribe: vi.fn() }),
}));

describe("CitizenNewsFeedPage", () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
    useSessionStore.setState({
      user: { id: "citizen-1", email: "citizen@test.com", role: "citizen", full_name: "Citizen User" },
      accessToken: "citizen-token",
      refreshToken: null,
      department: null,
    });
  });

  it("renders the temporary news feed content and readiness summaries", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;

      if (url.includes("/api/departments/directory")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              departments: [
                {
                  id: "dept-fire",
                  user_id: "dept-1",
                  name: "MDRRMO",
                  type: "disaster",
                  verification_status: "approved",
                },
                {
                  id: "dept-eng",
                  user_id: "dept-2",
                  name: "Engineering",
                  type: "public_works",
                  verification_status: "approved",
                },
              ],
            }),
            { status: 200 },
          ),
        );
      }

      return Promise.resolve(
        new Response(
          JSON.stringify({
            posts: [
              {
                id: "post-1",
                uploader: "dept-1",
                title: "Flash flood warning",
                content: "Water levels in the eastern basin are rising quickly. Evacuation teams are on standby for nearby households.",
                category: "warning",
                created_at: "2026-04-01T01:00:00Z",
                department: { id: "dept-1", name: "MDRRMO", type: "disaster" },
              },
              {
                id: "post-2",
                uploader: "dept-2",
                title: "Road clearing update",
                content: "Clearing operations continue.",
                category: "update",
                created_at: "2026-04-01T00:00:00Z",
                department: { id: "dept-2", name: "Engineering", type: "public_works" },
              },
            ],
          }),
          { status: 200 },
        ),
      );
    });

    render(
      <MemoryRouter initialEntries={["/citizen/news-feed"]}>
        <CitizenNewsFeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByRole("heading", { name: "News Feed" })).toBeInTheDocument();
    expect(screen.getByTestId("department-news-feed-hero")).toBeInTheDocument();
    expect(
      screen.getByRole("textbox", { name: "Temporary news search" }),
    ).toBeInTheDocument();
    expect(screen.queryByText("Department composer")).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /anything urgent to share/i }),
    ).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Post" })).not.toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: /news feed/i }).length).toBeGreaterThan(0);
    await screen.findByText(/you've catched up with the news chu2/i);

    await waitFor(() => {
      const readinessPanel = screen.getByText("Active Readiness").closest("section, article, div");
      expect(readinessPanel).not.toBeNull();
      expect(within(readinessPanel as HTMLElement).getByText("Warning")).toBeInTheDocument();
      expect(within(readinessPanel as HTMLElement).getByText(/Water levels in the eastern basin are rising quickly/i)).toBeInTheDocument();
      expect(within(readinessPanel as HTMLElement).queryByText(/Clearing operations continue/i)).not.toBeInTheDocument();
    });

    await waitFor(() => {
      const whoToFollowPanel = screen.getByText("Who to follow").closest("section, article, div");
      expect(whoToFollowPanel).not.toBeNull();
      expect(within(whoToFollowPanel as HTMLElement).getByText("MDRRMO")).toBeInTheDocument();
      expect(within(whoToFollowPanel as HTMLElement).getByText("@mdrrmo")).toBeInTheDocument();
    });
  });
});

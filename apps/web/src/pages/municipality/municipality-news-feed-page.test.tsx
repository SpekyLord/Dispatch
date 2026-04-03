import { render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { MunicipalityNewsFeedPage } from "./municipality-news-feed-page";

vi.mock("@/lib/realtime/supabase", () => ({
  subscribeToTable: () => ({ unsubscribe: vi.fn() }),
}));

describe("MunicipalityNewsFeedPage", () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
    useSessionStore.setState({
      user: { id: "muni-1", email: "municipality@test.com", role: "municipality", full_name: "Municipality User" },
      accessToken: "municipality-token",
      refreshToken: null,
      department: null,
    });
  });

  it("keeps the news feed read-only for municipality users and shows situational summaries", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;

      if (url.includes("/api/departments/directory")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              departments: [
                {
                  id: "dept-rescue",
                  user_id: "dept-1",
                  name: "Rescue Unit",
                  type: "disaster",
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
                title: "River status",
                content: "River monitoring teams confirmed the overflow has stabilized and downstream barangays remain under close observation.",
                category: "situational_report",
                created_at: "2026-04-01T02:30:00Z",
                department: { id: "dept-1", name: "Rescue Unit", type: "disaster" },
              },
            ],
          }),
          { status: 200 },
        ),
      );
    });

    render(
      <MemoryRouter initialEntries={["/municipality/news-feed"]}>
        <MunicipalityNewsFeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText("Observation-only access")).toBeInTheDocument();
    expect(screen.getByText(/Only department accounts can create awareness posts/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Create Post" })).not.toBeInTheDocument();

    await waitFor(() => {
      const readinessPanel = screen.getByText("Active Readiness").closest("section, article, div");
      expect(readinessPanel).not.toBeNull();
      expect(within(readinessPanel as HTMLElement).getByText("Situational Report")).toBeInTheDocument();
      expect(within(readinessPanel as HTMLElement).getByText(/River monitoring teams confirmed the overflow has stabilized/i)).toBeInTheDocument();
    });

    await waitFor(() => {
      const whoToFollowPanel = screen.getByText("Who to follow").closest("section, article, div");
      expect(whoToFollowPanel).not.toBeNull();
      expect(within(whoToFollowPanel as HTMLElement).getByText("Rescue Unit")).toBeInTheDocument();
    });
  });
});

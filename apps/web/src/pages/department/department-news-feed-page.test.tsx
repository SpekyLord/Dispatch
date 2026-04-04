import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { DepartmentNewsFeedPage } from "./department-news-feed-page";

vi.mock("@/lib/realtime/supabase", () => ({
  subscribeToTable: () => ({ unsubscribe: vi.fn() }),
}));

describe("DepartmentNewsFeedPage", () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
    useSessionStore.setState({
      user: {
        id: "dept-1",
        email: "department@test.com",
        role: "department",
        full_name: "Department User",
      },
      accessToken: "department-token",
      refreshToken: null,
      department: null,
    });
  });

  it("shows department-only publishing controls", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;

      if (url.includes("/api/departments/directory")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              departments: [
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
                title: "Storm alert",
                content: "High-wind response teams are prepositioned near the western coastal corridor for rapid deployment.",
                category: "alert",
                created_at: "2026-04-01T03:00:00Z",
                department: { id: "dept-1", name: "MDRRMO", type: "disaster" },
              },
            ],
          }),
          { status: 200 },
        ),
      );
    });

    render(
      <MemoryRouter initialEntries={["/department/news-feed"]}>
        <DepartmentNewsFeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText("Department composer")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Post" })).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /anything urgent to share/i }),
    ).toBeInTheDocument();
    await screen.findByText(/you've catched up with the news chu2/i);

    await waitFor(() => {
      const readinessPanel = screen.getByText("Active Readiness").closest("section, article, div");
      expect(readinessPanel).not.toBeNull();
      expect(within(readinessPanel as HTMLElement).getByText("Alert")).toBeInTheDocument();
      expect(within(readinessPanel as HTMLElement).getByText(/High-wind response teams are prepositioned/i)).toBeInTheDocument();
    });

    await waitFor(() => {
      const whoToFollowPanel = screen.getByText("Who to follow").closest("section, article, div");
      expect(whoToFollowPanel).not.toBeNull();
      expect(within(whoToFollowPanel as HTMLElement).getByText("Engineering")).toBeInTheDocument();
      expect(within(whoToFollowPanel as HTMLElement).queryByText("MDRRMO")).not.toBeInTheDocument();
    });
  });

  it("opens the create post modal from the feed", () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ posts: [] }), { status: 200 }),
    );

    render(
      <MemoryRouter initialEntries={["/department/news-feed"]}>
        <DepartmentNewsFeedPage />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Post" }));

    expect(screen.getByText("Department Command Desk")).toBeInTheDocument();
    expect(
      screen.getByText(
        /create a public announcement without leaving the feed/i,
      ),
    ).toBeInTheDocument();
  });

  it("opens the same command desk when compose is requested from the route", () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ posts: [] }), { status: 200 }),
    );

    render(
      <MemoryRouter initialEntries={["/department/news-feed?compose=1"]}>
        <DepartmentNewsFeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText("Department Command Desk")).toBeInTheDocument();
    expect(
      screen.getByText(
        /create a public announcement without leaving the feed/i,
      ),
    ).toBeInTheDocument();
  });

  it("shows post actions for the publisher and opens the delete confirmation modal", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          posts: [
            {
              id: "post-1",
              uploader: "dept-1",
              title: "Storm alert",
              content: "High-wind response teams are prepositioned near the western coastal corridor for rapid deployment.",
              category: "alert",
              created_at: "2026-04-01T03:00:00Z",
              department: { id: "dept-1", name: "MDRRMO", type: "disaster" },
            },
          ],
        }),
        { status: 200 },
      ),
    );

    render(
      <MemoryRouter initialEntries={["/department/news-feed"]}>
        <DepartmentNewsFeedPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByTitle("Post actions")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByTitle("Post actions"));

    expect(screen.getByRole("button", { name: "Edit post" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Delete post" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Delete post" }));

    expect(screen.getByText(/are you sure you want to delete this post/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Delete post" })).toBeInTheDocument();
  });

  it("opens the edit modal from the post actions menu", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          posts: [
            {
              id: "post-1",
              uploader: "dept-1",
              title: "Storm alert",
              content: "High-wind response teams are prepositioned near the western coastal corridor for rapid deployment.",
              category: "alert",
              location: "Central Station",
              created_at: "2026-04-01T03:00:00Z",
              department: { id: "dept-1", name: "MDRRMO", type: "disaster" },
            },
          ],
        }),
        { status: 200 },
      ),
    );

    render(
      <MemoryRouter initialEntries={["/department/news-feed"]}>
        <DepartmentNewsFeedPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByTitle("Post actions")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByTitle("Post actions"));
    fireEvent.click(screen.getByRole("button", { name: "Edit post" }));

    expect(screen.getByText("Update this announcement")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Storm alert")).toBeInTheDocument();
    expect(screen.getByDisplayValue("Central Station")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Save changes" })).toBeInTheDocument();
  });
});

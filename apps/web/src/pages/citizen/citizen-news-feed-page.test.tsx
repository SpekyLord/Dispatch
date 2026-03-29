import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { CitizenNewsFeedPage } from "./citizen-news-feed-page";

describe("CitizenNewsFeedPage", () => {
  beforeEach(() => {
    localStorage.clear();
    useSessionStore.setState({
      user: { id: "citizen-1", email: "citizen@test.com", role: "citizen", full_name: "Citizen User" },
      accessToken: "citizen-token",
      refreshToken: null,
      department: null,
    });
  });

  it("renders the temporary news feed content and navigation entry", () => {
    render(
      <MemoryRouter initialEntries={["/citizen/news-feed"]}>
        <CitizenNewsFeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByRole("heading", { name: "News Feed" })).toBeInTheDocument();
    expect(screen.getByText("Citizen View")).toBeInTheDocument();
    expect(screen.getByText(/ResilienceHub Temporary News Desk/i)).toBeInTheDocument();
    expect(screen.getByText("Read-only access")).toBeInTheDocument();
    expect(screen.getByText(/Only department accounts can create awareness posts/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Create Post" })).not.toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "News Feed" }).length).toBeGreaterThan(0);
  });
});

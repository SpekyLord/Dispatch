import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { MunicipalityNewsFeedPage } from "./municipality-news-feed-page";

describe("MunicipalityNewsFeedPage", () => {
  beforeEach(() => {
    localStorage.clear();
    useSessionStore.setState({
      user: { id: "muni-1", email: "municipality@test.com", role: "municipality", full_name: "Municipality User" },
      accessToken: "municipality-token",
      refreshToken: null,
      department: null,
    });
  });

  it("keeps the news feed read-only for municipality users", () => {
    render(
      <MemoryRouter initialEntries={["/municipality/news-feed"]}>
        <MunicipalityNewsFeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText("Observation-only access")).toBeInTheDocument();
    expect(screen.getByText(/Only department accounts can create awareness posts/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Create Post" })).not.toBeInTheDocument();
  });
});

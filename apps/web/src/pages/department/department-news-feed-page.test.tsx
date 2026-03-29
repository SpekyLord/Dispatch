import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { DepartmentNewsFeedPage } from "./department-news-feed-page";

describe("DepartmentNewsFeedPage", () => {
  beforeEach(() => {
    localStorage.clear();
    useSessionStore.setState({
      user: { id: "dept-1", email: "department@test.com", role: "department", full_name: "Department User" },
      accessToken: "department-token",
      refreshToken: null,
      department: null,
    });
  });

  it("shows department-only publishing controls", () => {
    render(
      <MemoryRouter initialEntries={["/department/news-feed"]}>
        <DepartmentNewsFeedPage />
      </MemoryRouter>,
    );

    expect(screen.getByText("Department publishing")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create Post" })).toBeInTheDocument();
    expect(screen.getByLabelText("Department posting prompt")).toBeInTheDocument();
  });

  it("opens the create post modal from the feed", () => {
    render(
      <MemoryRouter initialEntries={["/department/news-feed"]}>
        <DepartmentNewsFeedPage />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Create Post" }));

    expect(screen.getByText("Department Command Desk")).toBeInTheDocument();
    expect(screen.getByText(/create a public announcement without leaving the feed/i)).toBeInTheDocument();
  });
});

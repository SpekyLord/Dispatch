import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";

import { ProtectedRoute } from "@/lib/auth/protected-route";
import { useSessionStore } from "@/lib/auth/session-store";
import { LandingPage } from "@/pages/shared/landing-page";

describe("Dispatch web shell", () => {
  beforeEach(() => {
    useSessionStore.setState({ accessToken: null, user: null, refreshToken: null, department: null });
  });

  it("renders the landing page shell", () => {
    render(
      <MemoryRouter>
        <LandingPage />
      </MemoryRouter>,
    );

    expect(screen.getByText(/Cultivating resilience through community-driven response/i)).toBeInTheDocument();
  });

  it("redirects protected routes when no session exists", () => {
    render(
      <MemoryRouter initialEntries={["/profile"]}>
        <Routes>
          <Route element={<ProtectedRoute />}>
            <Route element={<div>profile page</div>} path="/profile" />
          </Route>
          <Route element={<div>login page</div>} path="/auth/login" />
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByText("login page")).toBeInTheDocument();
  });
});

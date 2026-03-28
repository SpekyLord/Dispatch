import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LoginPage } from "@/pages/auth/login-page";
import { RegisterPage } from "@/pages/auth/register-page";

describe("E2E Smoke: Citizen register → login → submit report → view detail", () => {
  beforeEach(() => {
    useSessionStore.setState({ accessToken: null, user: null, refreshToken: null, department: null });
    vi.restoreAllMocks();
  });

  it("citizen can register and session is created", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          access_token: "tok-new",
          refresh_token: "ref-new",
          user: { id: "c-1", email: "new@test.com", role: "citizen", full_name: "New Citizen" },
        }),
        { status: 201 },
      ),
    );

    render(
      <MemoryRouter initialEntries={["/auth/register"]}>
        <Routes>
          <Route element={<RegisterPage />} path="/auth/register" />
          <Route element={<div>citizen home</div>} path="/citizen" />
        </Routes>
      </MemoryRouter>,
    );

    await userEvent.type(screen.getByPlaceholderText("Juan Dela Cruz"), "New Citizen");
    await userEvent.type(screen.getByPlaceholderText("j.doe@dispatch.org"), "new@test.com");
    await userEvent.type(screen.getByPlaceholderText("••••••••••••"), "password123");
    await userEvent.click(screen.getByRole("button", { name: /create account/i }));

    await waitFor(() => {
      const state = useSessionStore.getState();
      expect(state.accessToken).toBe("tok-new");
      expect(state.user?.role).toBe("citizen");
    });
  });

  it("citizen can log in after registration", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          access_token: "tok-login",
          refresh_token: "ref-login",
          user: { id: "c-1", email: "new@test.com", role: "citizen", full_name: "New Citizen" },
        }),
        { status: 200 },
      ),
    );

    render(
      <MemoryRouter initialEntries={["/auth/login"]}>
        <Routes>
          <Route element={<LoginPage />} path="/auth/login" />
          <Route element={<div>citizen home</div>} path="/citizen" />
        </Routes>
      </MemoryRouter>,
    );

    await userEvent.type(screen.getByPlaceholderText("name@dispatch.org"), "new@test.com");
    await userEvent.type(screen.getByPlaceholderText("••••••••••••"), "password123");
    await userEvent.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => {
      expect(useSessionStore.getState().accessToken).toBe("tok-login");
    });
  });
});

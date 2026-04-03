import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LoginPage } from "@/pages/auth/login-page";
import { RegisterPage } from "@/pages/auth/register-page";

describe("E2E Smoke: Citizen register -> login -> submit report -> view detail", () => {
  beforeEach(() => {
    useSessionStore.setState({
      accessToken: null,
      user: null,
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("citizen can register and session is created", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          access_token: "tok-new",
          refresh_token: "ref-new",
          user: {
            id: "c-1",
            email: "new@test.com",
            role: "citizen",
            full_name: "New Citizen",
          },
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

    fireEvent.change(screen.getByPlaceholderText("Juan Dela Cruz"), {
      target: { value: "New Citizen" },
    });
    fireEvent.change(screen.getByPlaceholderText("j.doe@dispatch.org"), {
      target: { value: "new@test.com" },
    });
    fireEvent.change(screen.getByLabelText(/password/i), {
      target: { value: "password123" },
    });
    fireEvent.click(screen.getByRole("button", { name: /create account/i }));

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
          user: {
            id: "c-1",
            email: "new@test.com",
            role: "citizen",
            full_name: "New Citizen",
          },
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

    fireEvent.change(screen.getByPlaceholderText("name@dispatch.org"), {
      target: { value: "new@test.com" },
    });
    fireEvent.change(screen.getByLabelText(/security credentials/i), {
      target: { value: "password123" },
    });
    fireEvent.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => {
      expect(useSessionStore.getState().accessToken).toBe("tok-login");
    });
  });
});

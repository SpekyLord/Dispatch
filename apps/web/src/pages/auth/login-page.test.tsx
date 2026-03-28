import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LoginPage } from "./login-page";

describe("LoginPage", () => {
  beforeEach(() => {
    useSessionStore.setState({ accessToken: null, user: null, refreshToken: null, department: null });
    vi.restoreAllMocks();
  });

  it("renders the login form", () => {
    render(
      <MemoryRouter>
        <LoginPage />
      </MemoryRouter>,
    );

    expect(screen.getByPlaceholderText("name@dispatch.org")).toBeInTheDocument();
    expect(screen.getByPlaceholderText("••••••••••••")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /sign in/i })).toBeInTheDocument();
  });

  it("shows error on failed login", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(JSON.stringify({ error: { message: "Invalid credentials" } }), { status: 401 }),
    );

    render(
      <MemoryRouter>
        <LoginPage />
      </MemoryRouter>,
    );

    await userEvent.type(screen.getByPlaceholderText("name@dispatch.org"), "bad@test.com");
    await userEvent.type(screen.getByPlaceholderText("••••••••••••"), "wrong");
    await userEvent.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => {
      expect(screen.getByText(/invalid credentials/i)).toBeInTheDocument();
    });
  });

  it("updates session store on successful login", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          access_token: "tok-123",
          refresh_token: "ref-456",
          user: { id: "u1", email: "citizen@test.com", role: "citizen", full_name: "Test Citizen" },
        }),
        { status: 200 },
      ),
    );

    render(
      <MemoryRouter>
        <LoginPage />
      </MemoryRouter>,
    );

    await userEvent.type(screen.getByPlaceholderText("name@dispatch.org"), "citizen@test.com");
    await userEvent.type(screen.getByPlaceholderText("••••••••••••"), "password");
    await userEvent.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => {
      const state = useSessionStore.getState();
      expect(state.accessToken).toBe("tok-123");
      expect(state.user?.email).toBe("citizen@test.com");
    });
  });
});

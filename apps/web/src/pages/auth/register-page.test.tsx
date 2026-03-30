import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { RegisterPage } from "./register-page";

describe("RegisterPage", () => {
  beforeEach(() => {
    useSessionStore.setState({
      accessToken: null,
      user: null,
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("defaults to citizen role and renders common fields", () => {
    render(
      <MemoryRouter>
        <RegisterPage />
      </MemoryRouter>,
    );

    expect(screen.getByPlaceholderText("Juan Dela Cruz")).toBeInTheDocument();
    expect(
      screen.getByPlaceholderText("j.doe@dispatch.org"),
    ).toBeInTheDocument();
    expect(
      screen.queryByPlaceholderText("Bureau of Emergency Management"),
    ).not.toBeInTheDocument();
  });

  it("shows department fields when department role is selected", async () => {
    render(
      <MemoryRouter>
        <RegisterPage />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: /department/i }));

    await waitFor(() => {
      expect(
        screen.getByPlaceholderText("Bureau of Emergency Management"),
      ).toBeInTheDocument();
    });
  });

  it("shows error on failed registration", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(
        JSON.stringify({ error: { message: "Email already exists" } }),
        { status: 409 },
      ),
    );

    render(
      <MemoryRouter>
        <RegisterPage />
      </MemoryRouter>,
    );

    fireEvent.change(screen.getByPlaceholderText("Juan Dela Cruz"), {
      target: { value: "Test" },
    });
    fireEvent.change(screen.getByPlaceholderText("j.doe@dispatch.org"), {
      target: { value: "dup@test.com" },
    });
    fireEvent.change(screen.getByLabelText(/password/i), {
      target: { value: "password123" },
    });
    fireEvent.click(screen.getByRole("button", { name: /create account/i }));

    await waitFor(() => {
      expect(screen.getByText(/email already exists/i)).toBeInTheDocument();
    });
  });
});

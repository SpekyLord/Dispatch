import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { MunicipalityVerificationPage } from "./municipality-verification-page";

const mockPendingDepartments = {
  departments: [
    {
      id: "dept-1",
      name: "BFP Station Alpha",
      type: "fire",
      contact_number: "+63 912 345 6789",
      address: "123 Main St",
      area_of_responsibility: "North District",
      verification_status: "pending",
      created_at: "2026-03-28T10:00:00Z",
    },
  ],
};

describe("MunicipalityVerificationPage", () => {
  beforeEach(() => {
    useSessionStore.setState({
      user: { id: "muni-1", email: "admin@dispatch.local", role: "municipality", full_name: "Admin" },
      accessToken: "valid-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("fetches and renders pending departments", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(JSON.stringify(mockPendingDepartments), { status: 200 }),
    );

    render(
      <MemoryRouter>
        <MunicipalityVerificationPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("BFP Station Alpha")).toBeInTheDocument();
    });
    expect(screen.getByRole("button", { name: /approve/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /reject/i })).toBeInTheDocument();
  });

  it("removes department from list on approve", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(mockPendingDepartments), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ department: {} }), { status: 200 }));

    render(
      <MemoryRouter>
        <MunicipalityVerificationPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("BFP Station Alpha")).toBeInTheDocument();
    });

    await userEvent.click(screen.getByRole("button", { name: /approve/i }));

    await waitFor(() => {
      expect(screen.queryByText("BFP Station Alpha")).not.toBeInTheDocument();
    });
  });

  it("shows rejection reason input when reject is clicked", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(JSON.stringify(mockPendingDepartments), { status: 200 }),
    );

    render(
      <MemoryRouter>
        <MunicipalityVerificationPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("BFP Station Alpha")).toBeInTheDocument();
    });

    await userEvent.click(screen.getByRole("button", { name: /reject/i }));

    expect(screen.getByPlaceholderText(/reason for rejection/i)).toBeInTheDocument();
  });

  it("shows empty state when no pending departments", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(JSON.stringify({ departments: [] }), { status: 200 }),
    );

    render(
      <MemoryRouter>
        <MunicipalityVerificationPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText(/no departments pending/i)).toBeInTheDocument();
    });
  });
});

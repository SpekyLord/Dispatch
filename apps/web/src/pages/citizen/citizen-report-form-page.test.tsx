import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { CitizenReportFormPage } from "./citizen-report-form-page";

describe("CitizenReportFormPage", () => {
  beforeEach(() => {
    useSessionStore.setState({
      user: { id: "cit-1", email: "citizen@test.com", role: "citizen", full_name: "Test Citizen" },
      accessToken: "valid-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
    // Mock geolocation
    Object.defineProperty(navigator, "geolocation", {
      value: {
        getCurrentPosition: vi.fn((cb: PositionCallback) =>
          cb({ coords: { latitude: 14.5995, longitude: 120.9842 } } as GeolocationPosition),
        ),
      },
      writable: true,
      configurable: true,
    });
  });

  it("renders the report form fields", () => {
    render(
      <MemoryRouter>
        <CitizenReportFormPage />
      </MemoryRouter>,
    );

    expect(screen.getByPlaceholderText(/describe the incident/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/category/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/severity/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /submit report/i })).toBeInTheDocument();
  });

  it("shows GPS status after detection", async () => {
    render(
      <MemoryRouter>
        <CitizenReportFormPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText(/14\.5995/)).toBeInTheDocument();
    });
  });

  it("rejects files that are not JPEG or PNG", async () => {
    render(
      <MemoryRouter>
        <CitizenReportFormPage />
      </MemoryRouter>,
    );

    const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
    expect(fileInput).not.toBeNull();

    const badFile = new File(["data"], "test.gif", { type: "image/gif" });
    // fireEvent.change works more reliably for hidden file inputs
    const { fireEvent } = await import("@testing-library/react");
    fireEvent.change(fileInput, { target: { files: [badFile] } });

    await waitFor(() => {
      expect(screen.getByText(/only jpeg and png/i)).toBeInTheDocument();
    });
  });
});

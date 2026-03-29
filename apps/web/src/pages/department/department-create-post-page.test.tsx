import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { DepartmentCreatePostPage } from "./department-create-post-page";

const apiUploadMock = vi.fn();

vi.mock("@/lib/api/client", () => ({
  apiUpload: (...args: unknown[]) => apiUploadMock(...args),
}));

describe("DepartmentCreatePostPage", () => {
  beforeEach(() => {
    localStorage.clear();
    apiUploadMock.mockReset();
    useSessionStore.setState({
      user: { id: "dept-1", email: "department@test.com", role: "department", full_name: "Department User" },
      accessToken: "department-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("requests browser access and imports the current device location", async () => {
    Object.defineProperty(navigator, "geolocation", {
      value: {
        getCurrentPosition: vi.fn((cb: PositionCallback) =>
          cb({ coords: { latitude: 14.5995, longitude: 120.9842 } } as GeolocationPosition),
        ),
      },
      writable: true,
      configurable: true,
    });

    render(
      <MemoryRouter>
        <DepartmentCreatePostPage />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: /request location access/i }));

    await waitFor(() => {
      expect(screen.getByDisplayValue("14.59950, 120.98420")).toBeInTheDocument();
    });
    expect(screen.getByText(/current location imported from this device/i)).toBeInTheDocument();
  });

  it("blocks publishing when location access is unavailable", async () => {
    Object.defineProperty(navigator, "geolocation", {
      value: {
        getCurrentPosition: vi.fn((_success: PositionCallback, error?: PositionErrorCallback) =>
          error?.({ code: 1, message: "Denied", PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 } as GeolocationPositionError),
        ),
      },
      writable: true,
      configurable: true,
    });

    render(
      <MemoryRouter>
        <DepartmentCreatePostPage />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: /request location access/i }));

    fireEvent.change(screen.getByPlaceholderText(/announcement title/i), { target: { value: "Road advisory" } });
    fireEvent.change(screen.getByPlaceholderText(/write your announcement/i), {
      target: { value: "Road access will be limited while clearing operations continue." },
    });

    await waitFor(() => {
      expect(screen.getByText(/location access was denied or unavailable/i)).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole("button", { name: /publish/i }));

    await waitFor(() => {
      expect(screen.getByText(/turn on location services and import your current location before publishing/i)).toBeInTheDocument();
    });
    expect(apiUploadMock).not.toHaveBeenCalled();
  });
});

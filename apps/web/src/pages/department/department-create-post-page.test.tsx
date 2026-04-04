import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { DepartmentCreatePostForm } from "@/components/feed/department-create-post-form";
import { useSessionStore } from "@/lib/auth/session-store";

const apiUploadMock = vi.fn();

vi.mock("@/lib/api/client", () => ({
  apiUpload: (...args: unknown[]) => apiUploadMock(...args),
}));

describe("DepartmentCreatePostForm", () => {
  beforeEach(() => {
    localStorage.clear();
    apiUploadMock.mockReset();
    useSessionStore.setState({
      user: {
        id: "dept-1",
        email: "department@test.com",
        role: "department",
        full_name: "Department User",
      },
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
        <DepartmentCreatePostForm />
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
          error?.({
            code: 1,
            message: "Denied",
            PERMISSION_DENIED: 1,
            POSITION_UNAVAILABLE: 2,
            TIMEOUT: 3,
          } as GeolocationPositionError),
        ),
      },
      writable: true,
      configurable: true,
    });

    render(
      <MemoryRouter>
        <DepartmentCreatePostForm />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: /request location access/i }));

    fireEvent.change(screen.getByPlaceholderText(/announcement title/i), {
      target: { value: "Road advisory" },
    });
    fireEvent.change(screen.getByPlaceholderText(/write your announcement/i), {
      target: {
        value: "Road access will be limited while clearing operations continue.",
      },
    });

    await waitFor(() => {
      expect(screen.getByText(/location access was denied or unavailable/i)).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole("button", { name: /publish/i }));

    await waitFor(() => {
      expect(screen.getByText(/location is required/i)).toBeInTheDocument();
    });
    expect(apiUploadMock).not.toHaveBeenCalled();
  });

  it("submits assessment post details through the same publish flow", async () => {
    Object.defineProperty(navigator, "geolocation", {
      value: {
        getCurrentPosition: vi.fn((cb: PositionCallback) =>
          cb({ coords: { latitude: 14.6101, longitude: 121.0012 } } as GeolocationPosition),
        ),
      },
      writable: true,
      configurable: true,
    });
    apiUploadMock.mockResolvedValue({ post: { id: "post-assessment-1" } });

    render(
      <MemoryRouter>
        <DepartmentCreatePostForm />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Assessment Post" }));
    fireEvent.change(screen.getByPlaceholderText(/assessment headline/i), {
      target: { value: "Rapid damage assessment bulletin" },
    });
    fireEvent.change(screen.getByPlaceholderText(/operational summary/i), {
      target: { value: "Field teams are consolidating rescue priorities." },
    });
    fireEvent.change(screen.getByLabelText("Affected Area"), {
      target: { value: "Barangay Riverside" },
    });
    fireEvent.change(screen.getByLabelText("Damage Level"), {
      target: { value: "critical" },
    });
    fireEvent.change(screen.getByLabelText("Estimated Casualties"), {
      target: { value: "3" },
    });
    fireEvent.change(screen.getByLabelText("Displaced Persons"), {
      target: { value: "14" },
    });
    fireEvent.change(screen.getByPlaceholderText(/damage observations/i), {
      target: { value: "Flood damage has cut road access." },
    });

    fireEvent.click(screen.getByRole("button", { name: /request location access/i }));

    await waitFor(() => {
      expect(screen.getByDisplayValue("14.61010, 121.00120")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole("button", { name: /publish/i }));

    await waitFor(() => {
      expect(apiUploadMock).toHaveBeenCalledTimes(1);
    });

    const formData = apiUploadMock.mock.calls[0]?.[1] as FormData;
    expect(formData.get("post_kind")).toBe("assessment");
    expect(formData.get("location")).toBe("14.61010, 121.00120");
    expect(JSON.parse(String(formData.get("assessment_details")))).toMatchObject({
      affected_area: "Barangay Riverside",
      damage_level: "critical",
      estimated_casualties: 3,
      displaced_persons: 14,
      description: "Flood damage has cut road access.",
    });
  });
});

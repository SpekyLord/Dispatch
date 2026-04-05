import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LocaleProvider } from "@/lib/i18n/locale-context";
import { DepartmentHomePage } from "./department-home-page";

vi.mock("leaflet", () => ({
  divIcon: (options: unknown) => options,
  latLngBounds: (points: unknown) => points,
}));

vi.mock("react-leaflet", () => ({
  MapContainer: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="dashboard-leaflet-map">{children}</div>
  ),
  TileLayer: () => <div data-testid="dashboard-leaflet-tiles" />,
  Marker: ({
    children,
    title,
  }: {
    children?: React.ReactNode;
    title?: string;
  }) => (
    <div data-testid="dashboard-leaflet-marker" data-title={title ?? ""}>
      {children}
    </div>
  ),
  Popup: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  useMap: () => ({
    fitBounds: vi.fn(),
    setView: vi.fn(),
  }),
}));

describe("DepartmentHomePage", () => {
  beforeEach(() => {
    localStorage.clear();
    useSessionStore.setState({
      user: {
        id: "dept-user-1",
        email: "fire@test.com",
        role: "department",
        full_name: "BFP Alpha",
      },
      accessToken: "dept-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("renders the redesigned department dashboard with the map placeholder, quick access, and profile rail", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);

      if (url.includes("/api/departments/profile")) {
        return new Response(
          JSON.stringify({
            department: {
              id: "dept-1",
              user_id: "dept-user-1",
              name: "BFP Alpha",
              type: "fire",
              description:
                "Primary response unit for urban fire suppression and rescue support.",
              verification_status: "approved",
              contact_number: "(02) 8426-0219",
              address: "Agham Road, Quezon City",
              area_of_responsibility: "North District, East Sector",
            },
          }),
          { status: 200 },
        );
      }

      if (url.includes("/api/departments/reports")) {
        return new Response(
          JSON.stringify({
            reports: [
              {
                id: "rep-1",
                title: "Warehouse Fire",
                description: "Smoke spreading near the warehouse loading dock.",
                category: "fire",
                severity: "critical",
                status: "pending",
                address: "North Avenue",
                created_at: "2026-04-05T04:20:00Z",
                visible_via: "primary",
                latitude: 14.6396,
                longitude: 121.0387,
              },
              {
                id: "rep-2",
                title: "Clinic Fire",
                description: "Small kitchen fire reported in the clinic annex.",
                category: "fire",
                severity: "high",
                status: "accepted",
                address: "East Service Road",
                created_at: "2026-04-05T03:55:00Z",
                visible_via: "primary",
                latitude: 14.6501,
                longitude: 121.0488,
              },
            ],
          }),
          { status: 200 },
        );
      }

      throw new Error(`Unhandled fetch: ${url}`);
    });

    render(
      <LocaleProvider>
        <MemoryRouter>
          <DepartmentHomePage />
        </MemoryRouter>
      </LocaleProvider>,
    );

    await waitFor(() => {
      expect(screen.getByText("Department Command Center")).toBeInTheDocument();
    });

    expect(
      screen.getByTestId("department-live-map-placeholder"),
    ).toBeInTheDocument();
    expect(
      screen.getByTestId("department-operations-shell"),
    ).toBeInTheDocument();
    expect(
      screen.getByTestId("department-map-stats-panel"),
    ).toBeInTheDocument();
    expect(screen.getByTestId("department-map-view-panel")).toBeInTheDocument();
    expect(screen.getByTestId("dashboard-leaflet-map")).toBeInTheDocument();
    expect(screen.getByTestId("department-page-hero")).toBeInTheDocument();
    expect(screen.getByTestId("department-quick-access")).toBeInTheDocument();
    expect(screen.getAllByText("Department Profile").length).toBeGreaterThan(0);
    expect(screen.getByText("Registry ID")).toBeInTheDocument();
    expect(screen.getByText("Quick Access")).toBeInTheDocument();
    expect(screen.getByText("Recent Incident Activity")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getAllByText("Warehouse Fire").length).toBeGreaterThan(0);
    });
  });
});

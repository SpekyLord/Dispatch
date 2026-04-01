import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { CitizenReportDetailPage } from "./citizen-report-detail-page";

const realtimeMock = vi.hoisted(() => ({
  subscriptions: [] as Array<{
    table: string;
    onChange: (payload: unknown) => void;
    options?: { accessToken?: string | null; filter?: string };
  }>,
}));

vi.mock("@/lib/realtime/supabase", () => ({
  subscribeToTable: (
    table: string,
    onChange: (payload: unknown) => void,
    options?: { accessToken?: string | null; filter?: string },
  ) => {
    realtimeMock.subscriptions.push({ table, onChange, options });
    return { unsubscribe: vi.fn() };
  },
}));

vi.mock("@/components/maps/location-map", () => ({
  LocationMap: () => <div data-testid="location-map">Map</div>,
}));

describe("CitizenReportDetailPage", () => {
  beforeEach(() => {
    localStorage.clear();
    realtimeMock.subscriptions.length = 0;
    useSessionStore.setState({
      user: { id: "citizen-1", email: "citizen@test.com", role: "citizen", full_name: "Citizen" },
      accessToken: "citizen-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("re-fetches report detail when realtime status updates arrive", async () => {
    let payload = {
      report: {
        id: "rep-1",
        description: "Smoke reported near the bus terminal.",
        category: "fire",
        severity: "medium",
        status: "pending",
        address: "Bus Terminal",
        latitude: null,
        longitude: null,
        is_escalated: false,
        image_urls: [],
        created_at: "2026-03-29T04:00:00Z",
        updated_at: "2026-03-29T04:00:00Z",
      },
      status_history: [
        {
          id: "hist-1",
          new_status: "pending",
          notes: "Report received.",
          created_at: "2026-03-29T04:00:00Z",
        },
      ],
    };

    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      new Response(JSON.stringify(payload), { status: 200 }),
    );

    render(
      <MemoryRouter initialEntries={["/citizen/report/rep-1"]}>
        <Routes>
          <Route element={<CitizenReportDetailPage />} path="/citizen/report/:reportId" />
        </Routes>
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("Incident Details")).toBeInTheDocument();
    });
    expect(screen.getByText("Report received.")).toBeInTheDocument();
    expect(realtimeMock.subscriptions).toEqual([
      {
        table: "incident_reports",
        onChange: expect.any(Function),
        options: { accessToken: "citizen-token", filter: "id=eq.rep-1" },
      },
      {
        table: "report_status_history",
        onChange: expect.any(Function),
        options: { accessToken: "citizen-token", filter: "report_id=eq.rep-1" },
      },
    ]);

    payload = {
      report: {
        ...payload.report,
        status: "responding",
        updated_at: "2026-03-29T04:05:00Z",
      },
      status_history: [
        ...payload.status_history,
        {
          id: "hist-2",
          new_status: "responding",
          notes: "Responders are now en route.",
          created_at: "2026-03-29T04:05:00Z",
        },
      ],
    };

    realtimeMock.subscriptions.find((subscription) => subscription.table === "report_status_history")?.onChange({});

    await waitFor(() => {
      expect(screen.getByText("Responders are now en route.")).toBeInTheDocument();
    });
    expect(screen.getAllByText("Responding").length).toBeGreaterThan(0);
  });
});

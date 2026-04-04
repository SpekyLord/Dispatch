import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { CitizenReportDetailPage } from "./citizen-report-detail-page";

type CitizenDetailTestPayload = {
  report: {
    id: string;
    description: string;
    category: string;
    severity: string;
    status: string;
    address: string;
    latitude: number | null;
    longitude: number | null;
    is_escalated: boolean;
    image_urls: string[];
    created_at: string;
    updated_at: string;
  };
  status_history: Array<{
    id: string;
    new_status: string;
    notes: string;
    created_at: string;
  }>;
  timeline: Array<
    | {
        type: "status_change";
        timestamp: string;
        new_status: string;
        notes: string;
      }
    | {
        type: "department_response";
        timestamp: string;
        action: string;
        department_name: string;
        notes: string;
      }
  >;
};

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

  it("re-fetches citizen report detail when department updates arrive", async () => {
    let payload: CitizenDetailTestPayload = {
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
      timeline: [
        {
          type: "status_change",
          timestamp: "2026-03-29T04:00:00Z",
          new_status: "pending",
          notes: "Report received.",
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
      expect(screen.getByText("Report Details")).toBeInTheDocument();
    });
    expect(screen.getByText("Report Timeline")).toBeInTheDocument();
    expect(screen.getByText("Awaiting department acceptance.")).toBeInTheDocument();
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
      {
        table: "department_responses",
        onChange: expect.any(Function),
        options: { accessToken: "citizen-token", filter: "report_id=eq.rep-1" },
      },
      {
        table: "notifications",
        onChange: expect.any(Function),
        options: { accessToken: "citizen-token", filter: "user_id=eq.citizen-1" },
      },
    ]);

    payload = {
      report: {
        ...payload.report,
        status: "accepted",
        updated_at: "2026-03-29T04:03:00Z",
      },
      status_history: [
        ...payload.status_history,
        {
          id: "hist-2",
          new_status: "accepted",
          notes: "Department accepted the report.",
          created_at: "2026-03-29T04:03:00Z",
        },
      ],
      timeline: [
        ...payload.timeline,
        {
          type: "department_response",
          timestamp: "2026-03-29T04:03:00Z",
          action: "accepted",
          department_name: "BFP Central Station",
          notes: "Unit notified.",
        },
      ],
    };

    realtimeMock.subscriptions.find((subscription) => subscription.table === "department_responses")?.onChange({});

    await waitFor(() => {
      expect(screen.getByText("A department has accepted your report.")).toBeInTheDocument();
    });
    expect(screen.getAllByText("Accepted").length).toBeGreaterThan(0);

    payload = {
      report: {
        ...payload.report,
        status: "responding",
        updated_at: "2026-03-29T04:05:00Z",
      },
      status_history: [
        ...payload.status_history,
        {
          id: "hist-3",
          new_status: "responding",
          notes: "Responders are now en route.",
          created_at: "2026-03-29T04:05:00Z",
        },
      ],
      timeline: [
        ...payload.timeline,
        {
          type: "status_change",
          timestamp: "2026-03-29T04:05:00Z",
          new_status: "responding",
          notes: "Responders are now en route.",
        },
      ],
    };

    realtimeMock.subscriptions.find((subscription) => subscription.table === "notifications")?.onChange({
      new: {
        id: "notif-1",
        user_id: "citizen-1",
        reference_id: "rep-1",
        reference_type: "report",
      },
    });

    await waitFor(() => {
      expect(screen.getByText("Emergency responders are moving to the incident.")).toBeInTheDocument();
    });
  });
});

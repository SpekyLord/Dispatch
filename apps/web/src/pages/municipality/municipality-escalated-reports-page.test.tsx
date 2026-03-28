import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { MunicipalityEscalatedReportsPage } from "./municipality-escalated-reports-page";

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

describe("MunicipalityEscalatedReportsPage", () => {
  beforeEach(() => {
    localStorage.clear();
    realtimeMock.subscriptions.length = 0;
    useSessionStore.setState({
      user: { id: "muni-1", email: "admin@test.com", role: "municipality", full_name: "Municipal Admin" },
      accessToken: "municipality-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("renders escalated incidents and refreshes when the queue changes", async () => {
    let reports = [
      {
        id: "rep-1",
        title: "Bridge Collapse",
        description: "Structural damage reported after the quake.",
        category: "structural",
        severity: "critical",
        status: "pending",
        address: "River Road",
        created_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
        is_escalated: true,
        response_summary: { accepted: 0, declined: 2, pending: 1 },
      },
    ];

    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      new Response(JSON.stringify({ reports }), { status: 200 }),
    );

    render(
      <MemoryRouter>
        <MunicipalityEscalatedReportsPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("Bridge Collapse")).toBeInTheDocument();
    });
    expect(screen.getByText("Accepted")).toBeInTheDocument();
    expect(screen.getByText("Declined")).toBeInTheDocument();
    expect(realtimeMock.subscriptions.map((subscription) => subscription.table)).toEqual([
      "incident_reports",
      "department_responses",
    ]);

    reports = [
      ...reports,
      {
        id: "rep-2",
        title: "Flash Flood",
        description: "Water is rising near the market district.",
        category: "flood",
        severity: "high",
        status: "accepted",
        address: "Market District",
        created_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
        is_escalated: true,
        response_summary: { accepted: 1, declined: 1, pending: 0 },
      },
    ];

    realtimeMock.subscriptions.find((subscription) => subscription.table === "incident_reports")?.onChange({});

    await waitFor(() => {
      expect(screen.getByText("Flash Flood")).toBeInTheDocument();
    });
  });
});

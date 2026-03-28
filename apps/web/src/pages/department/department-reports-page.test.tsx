import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { DepartmentReportsPage } from "./department-reports-page";

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

describe("DepartmentReportsPage", () => {
  beforeEach(() => {
    localStorage.clear();
    realtimeMock.subscriptions.length = 0;
    useSessionStore.setState({
      user: { id: "dept-user-1", email: "fire@test.com", role: "department", full_name: "BFP Alpha" },
      accessToken: "dept-token",
      refreshToken: null,
      department: {
        id: "dept-1",
        user_id: "dept-user-1",
        name: "BFP Alpha",
        type: "fire",
        verification_status: "approved",
      },
    });
    vi.restoreAllMocks();
  });

  it("renders routed reports and refreshes when realtime callbacks fire", async () => {
    let reports: Array<{
      id: string;
      title: string;
      description: string;
      category: string;
      severity: string;
      status: string;
      address: string;
      created_at: string;
      is_escalated: boolean;
      visible_via: string;
      current_response: { action: string } | null;
      response_summary: { accepted: number; declined: number; pending: number };
    }> = [
      {
        id: "rep-1",
        title: "Warehouse Fire",
        description: "Smoke near the warehouse.",
        category: "fire",
        severity: "critical",
        status: "pending",
        address: "North Avenue",
        created_at: "2026-03-29T01:00:00Z",
        is_escalated: false,
        visible_via: "primary",
        current_response: null,
        response_summary: { accepted: 0, declined: 0, pending: 1 },
      },
    ];

    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      new Response(JSON.stringify({ reports }), { status: 200 }),
    );

    render(
      <MemoryRouter>
        <DepartmentReportsPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("Warehouse Fire")).toBeInTheDocument();
    });
    expect(screen.getByText("1 report")).toBeInTheDocument();
    expect(realtimeMock.subscriptions.map((subscription) => subscription.table)).toEqual([
      "incident_reports",
      "department_responses",
    ]);

    reports = [
      ...reports,
      {
        id: "rep-2",
        title: "Clinic Fire",
        description: "Small fire in the clinic kitchen.",
        category: "fire",
        severity: "high",
        status: "accepted",
        address: "South Road",
        created_at: "2026-03-29T01:05:00Z",
        is_escalated: true,
        visible_via: "escalation",
        current_response: { action: "accepted" },
        response_summary: { accepted: 1, declined: 0, pending: 0 },
      },
    ];

    realtimeMock.subscriptions.find((subscription) => subscription.table === "department_responses")?.onChange({});

    await waitFor(() => {
      expect(screen.getByText("Clinic Fire")).toBeInTheDocument();
    });
    expect(screen.getByText("2 reports")).toBeInTheDocument();
  });
});

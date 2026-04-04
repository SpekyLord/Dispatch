import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { NotificationsPage } from "./notifications-page";

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

describe("NotificationsPage", () => {
  beforeEach(() => {
    localStorage.clear();
    realtimeMock.subscriptions.length = 0;
    useSessionStore.setState({
      user: {
        id: "citizen-1",
        email: "citizen@test.com",
        role: "citizen",
        full_name: "Citizen",
      },
      accessToken: "citizen-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("marks notifications read and refreshes on realtime updates", async () => {
    let notifications = [
      {
        id: "notif-1",
        type: "report_update",
        title: "Team dispatched",
        message: "Responders are now en route.",
        is_read: false,
        created_at: "2026-03-29T03:00:00Z",
      },
    ];

    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      const method = init?.method ?? "GET";

      if (url.endsWith("/api/notifications") && method === "GET") {
        return new Response(
          JSON.stringify({
            notifications,
            unread_count: notifications.filter(
              (notification) => !notification.is_read,
            ).length,
          }),
          { status: 200 },
        );
      }

      if (url.endsWith("/api/notifications/read-all") && method === "PUT") {
        notifications = notifications.map((notification) => ({
          ...notification,
          is_read: true,
        }));
        return new Response(JSON.stringify({ ok: true }), { status: 200 });
      }

      throw new Error(`Unhandled request: ${method} ${url}`);
    });

    render(
      <MemoryRouter>
        <NotificationsPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("Team dispatched")).toBeInTheDocument();
    });
    expect(screen.getByText("Showing 1 notification")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Unread" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /mark all read/i }));

    await waitFor(() => {
      expect(screen.queryByRole("button", { name: /mark all read/i })).not.toBeInTheDocument();
    });

    notifications = [
      ...notifications,
      {
        id: "notif-2",
        type: "announcement",
        title: "New advisory posted",
        message: "A fresh department advisory is now available.",
        is_read: false,
        created_at: "2026-03-29T03:15:00Z",
      },
    ];

    realtimeMock.subscriptions[0]?.onChange({});

    await waitFor(() => {
      expect(screen.getByText("New advisory posted")).toBeInTheDocument();
    });
    expect(screen.getByText("Showing 2 notifications")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /mark all read/i })).toBeInTheDocument();
  });

  it("filters notifications through the new bar controls", async () => {
    const notifications = [
      {
        id: "notif-1",
        type: "new_report",
        title: "New fire report",
        message: "Citizen report needs response.",
        is_read: false,
        created_at: "2026-03-29T03:00:00Z",
      },
      {
        id: "notif-2",
        type: "announcement",
        title: "Advisory posted",
        message: "Fresh public advisory is available.",
        is_read: true,
        created_at: "2026-03-29T04:00:00Z",
      },
    ];

    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      const method = init?.method ?? "GET";

      if (url.endsWith("/api/notifications") && method === "GET") {
        return new Response(
          JSON.stringify({
            notifications,
            unread_count: 1,
          }),
          { status: 200 },
        );
      }

      throw new Error(`Unhandled request: ${method} ${url}`);
    });

    render(
      <MemoryRouter>
        <NotificationsPage />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("New fire report")).toBeInTheDocument();
      expect(screen.getByText("Advisory posted")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByRole("button", { name: "Unread" }));

    await waitFor(() => {
      expect(screen.getByText("New fire report")).toBeInTheDocument();
      expect(screen.queryByText("Advisory posted")).not.toBeInTheDocument();
    });

    fireEvent.change(screen.getByDisplayValue("Category"), {
      target: { value: "announcement" },
    });

    await waitFor(() => {
      expect(
        screen.getByText("No notifications match the current filters or search."),
      ).toBeInTheDocument();
    });
  });

  it("opens linked report notifications for department users", async () => {
    const notifications = [
      {
        id: "notif-report-1",
        type: "new_report",
        title: "New fire report",
        message: "Citizen report needs department response.",
        is_read: false,
        reference_id: "report-123",
        reference_type: "report",
        created_at: "2026-03-29T03:00:00Z",
      },
    ];

    useSessionStore.setState({
      user: {
        id: "department-1",
        email: "department@test.com",
        role: "department",
        full_name: "Department",
      },
      accessToken: "department-token",
      refreshToken: null,
      department: null,
    });

    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      const method = init?.method ?? "GET";

      if (url.endsWith("/api/notifications") && method === "GET") {
        return new Response(
          JSON.stringify({
            notifications,
            unread_count: 1,
          }),
          { status: 200 },
        );
      }

      if (url.endsWith("/api/notifications/notif-report-1/read") && method === "PUT") {
        return new Response(
          JSON.stringify({
            notification: {
              ...notifications[0],
              is_read: true,
            },
          }),
          { status: 200 },
        );
      }

      throw new Error(`Unhandled request: ${method} ${url}`);
    });

    render(
      <MemoryRouter initialEntries={["/notifications"]}>
        <Routes>
          <Route element={<NotificationsPage />} path="/notifications" />
          <Route element={<div>Department report detail</div>} path="/department/reports/:reportId" />
        </Routes>
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(screen.getByText("New fire report")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("New fire report"));

    await waitFor(() => {
      expect(screen.getByText("Department report detail")).toBeInTheDocument();
    });
  });
});

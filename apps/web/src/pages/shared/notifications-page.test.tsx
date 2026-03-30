import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
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
    expect(screen.getByText("1 unread notification")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /mark all read/i }));

    await waitFor(() => {
      expect(screen.getByText("All caught up")).toBeInTheDocument();
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
    expect(screen.getByText("1 unread notification")).toBeInTheDocument();
  });
});

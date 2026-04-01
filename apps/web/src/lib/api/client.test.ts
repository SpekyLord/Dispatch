import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { apiRequest } from "./client";

describe("api client refresh handling", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    useSessionStore.setState({
      user: { id: "dept-1", email: "dept@test.com", role: "department", full_name: "Dept" },
      accessToken: "stale-token",
      refreshToken: "refresh-123",
      department: null,
    });
  });

  it("refreshes once after a 401 and retries the request", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");
    fetchMock
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ error: { message: "expired" } }), { status: 401 }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            access_token: "fresh-token",
            refresh_token: "refresh-456",
            user: {
              id: "dept-1",
              email: "dept@test.com",
              role: "department",
              full_name: "Dept",
            },
            department: null,
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ deleted: true }), { status: 200 }),
      );

    const response = await apiRequest<{ deleted: boolean }>("/api/feed/16", {
      method: "DELETE",
    });

    expect(response.deleted).toBe(true);
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "http://127.0.0.1:5000/api/auth/refresh",
      expect.objectContaining({
        method: "POST",
      }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      3,
      "http://127.0.0.1:5000/api/feed/16",
      expect.objectContaining({
        method: "DELETE",
        headers: expect.objectContaining({
          Authorization: "Bearer fresh-token",
        }),
      }),
    );
    expect(useSessionStore.getState().accessToken).toBe("fresh-token");
    expect(useSessionStore.getState().refreshToken).toBe("refresh-456");
  });
});

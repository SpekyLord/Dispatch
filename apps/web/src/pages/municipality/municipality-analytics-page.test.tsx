import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LocaleProvider } from "@/lib/i18n/locale-context";
import { MunicipalityAnalyticsPage } from "./municipality-analytics-page";

describe("MunicipalityAnalyticsPage", () => {
  beforeEach(() => {
    useSessionStore.setState({
      user: {
        id: "muni-1",
        email: "admin@dispatch.local",
        role: "municipality",
        full_name: "Municipal Admin",
      },
      accessToken: "municipality-token",
      refreshToken: null,
      department: null,
    });
    vi.restoreAllMocks();
  });

  it("renders analytics cards, charts, and department activity in Filipino", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          total_reports: 42,
          by_status: {
            pending: 8,
            accepted: 10,
            responding: 12,
            resolved: 12,
          },
          avg_response_time_hours: 1.5,
          by_category: {
            fire: 9,
            flood: 13,
          },
          department_activity: [
            { name: "BFP Alpha", accepts: 6, declines: 1 },
            { name: "MDRRMO", accepts: 7, declines: 0 },
          ],
          unattended_count: 2,
        }),
        { status: 200 },
      ),
    );

    render(
      <LocaleProvider initialLocale="fil">
        <MemoryRouter>
          <MunicipalityAnalyticsPage />
        </MemoryRouter>
      </LocaleProvider>,
    );

    await waitFor(() => {
      expect(
        screen.getByRole("heading", { name: "Analitika" }),
      ).toBeInTheDocument();
    });

    expect(screen.getByText("Kabuuang Ulat")).toBeInTheDocument();
    expect(screen.getByText("Mga Ulat Ayon sa Status")).toBeInTheDocument();
    expect(screen.getByText("BFP Alpha")).toBeInTheDocument();
    expect(screen.getByText("Sunog")).toBeInTheDocument();
    expect(screen.getByText("Departamento")).toBeInTheDocument();
  });
});


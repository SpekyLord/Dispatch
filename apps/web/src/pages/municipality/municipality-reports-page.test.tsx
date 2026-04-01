import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LocaleProvider } from "@/lib/i18n/locale-context";
import { MunicipalityReportsPage } from "./municipality-reports-page";

const reportFixtures = [
  {
    id: "rep-1",
    title: "River Road Fire",
    description: "Warehouse fire near the highway.",
    category: "fire",
    severity: "high",
    status: "pending",
    is_escalated: false,
    created_at: "2026-03-29T08:00:00Z",
  },
  {
    id: "rep-2",
    title: "Bridge Flooding",
    description: "Floodwaters have covered the bridge access road.",
    category: "flood",
    severity: "critical",
    status: "resolved",
    is_escalated: true,
    created_at: "2026-03-29T09:00:00Z",
  },
];

function renderPage() {
  return render(
    <LocaleProvider>
      <MemoryRouter>
        <MunicipalityReportsPage />
      </MemoryRouter>
    </LocaleProvider>,
  );
}

describe("MunicipalityReportsPage", () => {
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

  it("filters reports and supports locale switching", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = new URL(input.toString());
      const status = url.searchParams.get("status");
      const category = url.searchParams.get("category");
      const isEscalated = url.searchParams.get("is_escalated");

      const filtered = reportFixtures.filter((report) => {
        if (status && report.status !== status) {
          return false;
        }
        if (category && report.category !== category) {
          return false;
        }
        if (
          isEscalated &&
          String(report.is_escalated) !== isEscalated
        ) {
          return false;
        }
        return true;
      });

      return new Response(JSON.stringify({ reports: filtered }), {
        status: 200,
      });
    });

    renderPage();

    await waitFor(() => {
      expect(screen.getByText("River Road Fire")).toBeInTheDocument();
    });

    fireEvent.change(screen.getByLabelText("Category"), {
      target: { value: "flood" },
    });

    await waitFor(() => {
      expect(screen.getByText("Bridge Flooding")).toBeInTheDocument();
    });
    expect(screen.queryByText("River Road Fire")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "FIL" }));

    await waitFor(() => {
      expect(
        screen.getByRole("heading", { name: "Lahat ng Ulat" }),
      ).toBeInTheDocument();
    });
    expect(screen.getByText("Lahat ng kategorya")).toBeInTheDocument();
  });
});


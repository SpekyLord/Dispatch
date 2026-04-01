import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LocaleProvider } from "@/lib/i18n/locale-context";
import { MunicipalityAssessmentsPage } from "./municipality-assessments-page";

describe("MunicipalityAssessmentsPage", () => {
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

  it("renders submitted assessments with translated damage labels", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          assessments: [
            {
              id: "assess-1",
              affected_area: "Barangay Norte",
              damage_level: "severe",
              estimated_casualties: 4,
              displaced_persons: 18,
              location: "North Road",
              description: "Road access and nearby homes are heavily damaged.",
              department_name: "BFP Alpha",
              created_at: "2026-03-29T10:00:00Z",
            },
          ],
        }),
        { status: 200 },
      ),
    );

    render(
      <LocaleProvider initialLocale="fil">
        <MemoryRouter>
          <MunicipalityAssessmentsPage />
        </MemoryRouter>
      </LocaleProvider>,
    );

    await waitFor(() => {
      expect(screen.getByText("Barangay Norte")).toBeInTheDocument();
    });

    expect(screen.getByText("Ni BFP Alpha")).toBeInTheDocument();
    expect(screen.getByText("Malubha")).toBeInTheDocument();
    expect(screen.getByText("4 nasawi")).toBeInTheDocument();
  });

  it("shows an empty state when no assessments exist", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(JSON.stringify({ assessments: [] }), { status: 200 }),
    );

    render(
      <LocaleProvider>
        <MemoryRouter>
          <MunicipalityAssessmentsPage />
        </MemoryRouter>
      </LocaleProvider>,
    );

    await waitFor(() => {
      expect(
        screen.getByText("No damage assessments submitted yet."),
      ).toBeInTheDocument();
    });
  });
});


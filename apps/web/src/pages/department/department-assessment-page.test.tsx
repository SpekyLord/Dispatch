import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useSessionStore } from "@/lib/auth/session-store";
import { LocaleProvider } from "@/lib/i18n/locale-context";
import { DepartmentAssessmentPage } from "./department-assessment-page";

describe("DepartmentAssessmentPage", () => {
  beforeEach(() => {
    useSessionStore.setState({
      user: {
        id: "dept-user-1",
        email: "dept@dispatch.local",
        role: "department",
        full_name: "BFP Alpha",
      },
      accessToken: "department-token",
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

  it("submits a new assessment, refreshes history, and switches locale", async () => {
    const state = {
      assessments: [
        {
          id: "assess-1",
          affected_area: "Barangay Centro",
          damage_level: "moderate",
          estimated_casualties: 1,
          displaced_persons: 5,
          location: "Main Road",
          description: "Initial field survey completed.",
          created_at: "2026-03-29T10:00:00Z",
        },
      ],
    };

    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = new URL(input.toString());
      const method = init?.method ?? "GET";

      if (url.pathname === "/api/departments/assessments" && method === "GET") {
        return new Response(JSON.stringify({ assessments: state.assessments }), {
          status: 200,
        });
      }

      if (url.pathname === "/api/departments/assessments" && method === "POST") {
        state.assessments = [
          {
            id: "assess-2",
            affected_area: "Barangay Riverside",
            damage_level: "critical",
            estimated_casualties: 3,
            displaced_persons: 14,
            location: "Floodplain",
            description: "Flood damage has cut road access.",
            created_at: "2026-03-29T11:00:00Z",
          },
          ...state.assessments,
        ];
        return new Response(JSON.stringify({ ok: true }), { status: 200 });
      }

      return new Response("Not found", { status: 404 });
    });

    render(
      <LocaleProvider>
        <MemoryRouter>
          <DepartmentAssessmentPage />
        </MemoryRouter>
      </LocaleProvider>,
    );

    await waitFor(() => {
      expect(screen.getByText("Barangay Centro")).toBeInTheDocument();
    });

    fireEvent.change(screen.getByLabelText("Affected Area"), {
      target: { value: "Barangay Riverside" },
    });
    fireEvent.change(screen.getByLabelText("Damage Level"), {
      target: { value: "critical" },
    });
    fireEvent.change(screen.getByLabelText("Estimated Casualties"), {
      target: { value: "3" },
    });
    fireEvent.change(screen.getByLabelText("Displaced Persons"), {
      target: { value: "14" },
    });
    fireEvent.change(screen.getByLabelText("Location"), {
      target: { value: "Floodplain" },
    });
    fireEvent.change(screen.getByLabelText("Description"), {
      target: { value: "Flood damage has cut road access." },
    });

    fireEvent.click(
      screen.getByRole("button", { name: "Submit Assessment" }),
    );

    await waitFor(() => {
      expect(screen.getByText("Assessment submitted successfully.")).toBeInTheDocument();
    });
    expect(screen.getByText("Barangay Riverside")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "FIL" }));

    await waitFor(() => {
      expect(
        screen.getByRole("heading", { name: "Mga Pagtatasa" }),
      ).toBeInTheDocument();
    });
    expect(
      screen.getByRole("button", { name: "Isumite ang Pagtatasa" }),
    ).toBeInTheDocument();
  });
});

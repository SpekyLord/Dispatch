import { expect, test, type Page } from "@playwright/test";

type MockReport = {
  id: string;
  reporter_id: string;
  title: string;
  description: string;
  category: string;
  severity: string;
  status: string;
  address: string;
  latitude: number | null;
  longitude: number | null;
  image_urls: string[];
  is_escalated: boolean;
  created_at: string;
  updated_at: string;
};

type MockResponse = {
  department_id: string;
  department_name: string;
  department_type: string;
  state: string;
  decline_reason: string | null;
  notes: string | null;
  responded_at: string | null;
  is_requesting_department: boolean;
};

type MockHistoryEntry = {
  id: string;
  old_status: string | null;
  new_status: string;
  notes: string;
  created_at: string;
};

type MockState = {
  report: MockReport | null;
  responses: MockResponse[];
  history: MockHistoryEntry[];
  historyCounter: number;
};

function citizenSession() {
  return {
    user: {
      id: "citizen-1",
      email: "citizen@test.com",
      role: "citizen",
      full_name: "Citizen Reporter",
    },
    accessToken: "citizen-token",
    refreshToken: "citizen-refresh",
    department: null,
  };
}

function departmentSession() {
  return {
    user: {
      id: "dept-user-1",
      email: "fire@test.com",
      role: "department",
      full_name: "BFP Alpha",
    },
    accessToken: "department-token",
    refreshToken: "department-refresh",
    department: {
      id: "dept-1",
      user_id: "dept-user-1",
      name: "BFP Alpha",
      type: "fire",
      verification_status: "approved",
    },
  };
}

async function seedSession(page: Page, session: unknown) {
  await page.addInitScript((value) => {
    window.localStorage.setItem("dispatch_session", JSON.stringify(value));
  }, session);
}

function appendHistory(
  state: MockState,
  entry: Omit<MockHistoryEntry, "id">,
) {
  state.historyCounter += 1;
  state.history.push({
    id: `hist-${state.historyCounter}`,
    ...entry,
  });
}

async function attachApiRoutes(page: Page, state: MockState) {
  await page.route("http://127.0.0.1:5000/api/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const method = request.method();

    if (url.pathname === "/api/reports" && method === "POST") {
      const body = request.postDataJSON() as {
        description: string;
        category: string;
        severity?: string;
        address?: string;
        latitude?: number;
        longitude?: number;
      };

      const createdAt = "2026-03-29T06:00:00Z";
      state.report = {
        id: "rep-phase2-1",
        reporter_id: "citizen-1",
        title: "Warehouse Fire",
        description: body.description,
        category: body.category,
        severity: body.severity ?? "medium",
        status: "pending",
        address: body.address ?? "",
        latitude: body.latitude ?? null,
        longitude: body.longitude ?? null,
        image_urls: [],
        is_escalated: false,
        created_at: createdAt,
        updated_at: createdAt,
      };
      state.responses = [];
      state.history = [];
      state.historyCounter = 0;
      appendHistory(state, {
        old_status: null,
        new_status: "pending",
        notes: "Report submitted.",
        created_at: createdAt,
      });

      await route.fulfill({
        status: 201,
        contentType: "application/json",
        body: JSON.stringify({ report: { id: state.report.id } }),
      });
      return;
    }

    if (url.pathname === "/api/reports/rep-phase2-1" && method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          report: state.report,
          status_history: state.history,
        }),
      });
      return;
    }

    if (url.pathname === "/api/departments/reports/rep-phase2-1/responses" && method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          report: state.report,
          responses: state.responses,
        }),
      });
      return;
    }

    if (url.pathname === "/api/departments/reports/rep-phase2-1/accept" && method === "POST") {
      if (state.report) {
        state.report = {
          ...state.report,
          status: "accepted",
          updated_at: "2026-03-29T06:02:00Z",
        };
      }
      state.responses = [
        {
          department_id: "dept-1",
          department_name: "BFP Alpha",
          department_type: "fire",
          state: "accepted",
          decline_reason: null,
          notes: null,
          responded_at: "2026-03-29T06:02:00Z",
          is_requesting_department: true,
        },
      ];
      appendHistory(state, {
        old_status: "pending",
        new_status: "accepted",
        notes: "First department accepted the report.",
        created_at: "2026-03-29T06:02:00Z",
      });

      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ ok: true }),
      });
      return;
    }

    if (url.pathname === "/api/departments/reports/rep-phase2-1/status" && method === "PUT") {
      const body = request.postDataJSON() as { status: string };
      if (state.report) {
        state.report = {
          ...state.report,
          status: body.status,
          updated_at: "2026-03-29T06:05:00Z",
        };
      }
      appendHistory(state, {
        old_status: "accepted",
        new_status: body.status,
        notes: `Report marked as ${body.status}.`,
        created_at: "2026-03-29T06:05:00Z",
      });

      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ report: state.report }),
      });
      return;
    }

    await route.abort();
  });
}

test("citizen submit -> department accept -> responding -> citizen sees updated detail", async ({
  browser,
}) => {
  const state: MockState = {
    report: null,
    responses: [],
    history: [],
    historyCounter: 0,
  };

  const citizenContext = await browser.newContext();
  const departmentContext = await browser.newContext();
  const citizenPage = await citizenContext.newPage();
  const departmentPage = await departmentContext.newPage();

  await seedSession(citizenPage, citizenSession());
  await seedSession(departmentPage, departmentSession());
  await attachApiRoutes(citizenPage, state);
  await attachApiRoutes(departmentPage, state);

  await citizenPage.goto("/citizen/report/new");
  await citizenPage.getByLabel("Incident Description *").fill("Heavy smoke is coming from the warehouse.");
  await citizenPage.getByLabel("Category *").selectOption("fire");
  await citizenPage.getByLabel("Severity").selectOption("high");
  await citizenPage.getByLabel("Address / Location").fill("Warehouse District");
  await citizenPage.getByRole("button", { name: "Submit Report" }).click();

  await expect(citizenPage).toHaveURL(/\/citizen\/report\/rep-phase2-1$/);
  await expect(citizenPage.getByText("Report submitted.")).toBeVisible();

  await departmentPage.goto("/department/reports/rep-phase2-1");
  await expect(departmentPage.getByRole("button", { name: "Accept" })).toBeVisible();
  await departmentPage.getByRole("button", { name: "Accept" }).click();
  await expect(departmentPage.getByText("You accepted this report")).toBeVisible();

  await departmentPage.getByRole("button", { name: "Mark Responding" }).click();
  await expect(departmentPage.getByRole("button", { name: "Mark Resolved" })).toBeVisible();

  await citizenPage.reload();
  await expect(citizenPage.getByText("Report marked as responding.")).toBeVisible();

  await citizenContext.close();
  await departmentContext.close();
});

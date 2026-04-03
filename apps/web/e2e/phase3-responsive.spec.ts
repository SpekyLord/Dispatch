import { expect, test, type Page } from "@playwright/test";

const viewports = [
  { name: "phone", width: 390, height: 844 },
  { name: "tablet", width: 834, height: 1112 },
  { name: "desktop", width: 1440, height: 900 },
];

function municipalitySession() {
  return {
    user: {
      id: "muni-1",
      email: "admin@dispatch.local",
      role: "municipality",
      full_name: "Municipal Admin",
    },
    accessToken: "municipality-token",
    refreshToken: "municipality-refresh",
    department: null,
  };
}

function departmentSession() {
  return {
    user: {
      id: "dept-user-1",
      email: "dept@dispatch.local",
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

function citizenSession() {
  return {
    user: {
      id: "citizen-1",
      email: "citizen@dispatch.local",
      role: "citizen",
      full_name: "Citizen Reporter",
    },
    accessToken: "citizen-token",
    refreshToken: "citizen-refresh",
    department: null,
  };
}

async function seedSession(page: Page, session: unknown) {
  await page.addInitScript((value) => {
    window.localStorage.setItem("dispatch_session", JSON.stringify(value));
  }, session);
}

async function attachPhase3Routes(page: Page) {
  await page.route("http://127.0.0.1:5000/api/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const method = request.method();

    if (url.pathname === "/api/municipality/reports" && method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          reports: [
            {
              id: "rep-phase3-1",
              title: "River Road Fire",
              description: "Warehouse fire near the highway.",
              category: "fire",
              severity: "high",
              status: "pending",
              is_escalated: false,
              created_at: "2026-03-29T08:00:00Z",
            },
            {
              id: "rep-phase3-2",
              title: "Bridge Flooding",
              description: "Floodwaters have covered the bridge access road.",
              category: "flood",
              severity: "critical",
              status: "resolved",
              is_escalated: true,
              created_at: "2026-03-29T09:00:00Z",
            },
          ],
        }),
      });
      return;
    }

    if (url.pathname === "/api/municipality/analytics" && method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
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
            medical: 5,
          },
          department_activity: [
            { name: "BFP Alpha", accepts: 6, declines: 1 },
            { name: "MDRRMO", accepts: 7, declines: 0 },
          ],
          unattended_count: 2,
        }),
      });
      return;
    }

    if (url.pathname === "/api/departments/assessments" && method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
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
        }),
      });
      return;
    }

    if (url.pathname === "/api/reports/rep-phase3-1" && method === "GET") {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          report: {
            id: "rep-phase3-1",
            description: "Residents reported rising floodwater near the bridge.",
            category: "flood",
            severity: "high",
            status: "responding",
            address: "Bridge Access Road",
            latitude: null,
            longitude: null,
            is_escalated: true,
            image_urls: [],
            created_at: "2026-03-29T08:00:00Z",
            updated_at: "2026-03-29T08:15:00Z",
          },
          status_history: [
            {
              id: "hist-1",
              new_status: "pending",
              notes: "Report received.",
              created_at: "2026-03-29T08:00:00Z",
            },
          ],
          timeline: [
            {
              type: "status_change",
              timestamp: "2026-03-29T08:00:00Z",
              new_status: "pending",
              notes: "Report received.",
            },
            {
              type: "department_response",
              timestamp: "2026-03-29T08:05:00Z",
              action: "accepted",
              department_name: "MDRRMO",
              notes: "Rescue boat deployed.",
            },
            {
              type: "status_change",
              timestamp: "2026-03-29T08:15:00Z",
              new_status: "responding",
              notes: "Responders are now en route.",
            },
          ],
          department_responses: [
            {
              department_name: "MDRRMO",
              action: "accepted",
              notes: "Rescue boat deployed.",
              responded_at: "2026-03-29T08:05:00Z",
            },
          ],
        }),
      });
      return;
    }

    await route.abort();
  });
}

async function expectNoHorizontalOverflow(page: Page) {
  const hasOverflow = await page.evaluate(() => {
    const root = document.documentElement;
    return root.scrollWidth > root.clientWidth + 1;
  });
  expect(hasOverflow).toBeFalsy();
}

for (const viewport of viewports) {
  test(`municipality reports responsive smoke (${viewport.name})`, async ({
    browser,
  }) => {
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();
    await seedSession(page, municipalitySession());
    await attachPhase3Routes(page);

    await page.goto("/municipality/reports");

    await expect(
      page.getByRole("heading", { name: "All Reports" }),
    ).toBeVisible();
    await expect(page.getByLabel("Status")).toBeVisible();
    await expect(page.getByText("River Road Fire")).toBeVisible();
    await expectNoHorizontalOverflow(page);

    await context.close();
  });

  test(`municipality analytics responsive smoke (${viewport.name})`, async ({
    browser,
  }) => {
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();
    await seedSession(page, municipalitySession());
    await attachPhase3Routes(page);

    await page.goto("/municipality/analytics");

    await expect(
      page.getByRole("heading", { name: "Analytics" }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Refresh Data" })).toBeVisible();
    await expect(page.getByText("Reports by Status")).toBeVisible();
    await expectNoHorizontalOverflow(page);

    await context.close();
  });

  test(`department assessments responsive smoke (${viewport.name})`, async ({
    browser,
  }) => {
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();
    await seedSession(page, departmentSession());
    await attachPhase3Routes(page);

    await page.goto("/department/assessments");

    await expect(
      page.getByRole("heading", { name: "Assessments", exact: true }),
    ).toBeVisible();
    await expect(page.getByLabel("Affected Area")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Submit Assessment" }),
    ).toBeVisible();
    await expect(page.getByText("Previous Assessments")).toBeVisible();
    await expectNoHorizontalOverflow(page);

    await context.close();
  });

  test(`citizen report detail responsive smoke (${viewport.name})`, async ({
    browser,
  }) => {
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();
    await seedSession(page, citizenSession());
    await attachPhase3Routes(page);

    await page.goto("/citizen/report/rep-phase3-1");

    await expect(
      page.getByRole("heading", { name: /Report #rep-phas/i }),
    ).toBeVisible();
    await expect(page.getByText("Report Timeline")).toBeVisible();
    await expect(page.getByText("Responders are now en route.")).toBeVisible();
    await expect(page.getByText("Department Responses")).toBeVisible();
    await expectNoHorizontalOverflow(page);

    await context.close();
  });
}

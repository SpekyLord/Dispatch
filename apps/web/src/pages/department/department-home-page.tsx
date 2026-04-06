import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { divIcon, latLngBounds } from "leaflet";
import { MapContainer, Marker, Popup, TileLayer, useMap } from "react-leaflet";

import { AppShell } from "@/components/layout/app-shell";
import { DepartmentPageHero } from "@/components/layout/department-page-hero";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { LoadingDots } from "@/components/ui/loading-dots";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore, type DepartmentInfo } from "@/lib/auth/session-store";

/**
 * Department home page.
 * Shows different views based on verification status:
 *  - pending: awaiting approval message
 *  - rejected: edit and resubmit form
 *  - approved: placeholder dashboard layout
 */

export function DepartmentHomePage() {
  const department = useSessionStore((s) => s.department);
  const setDepartment = useSessionStore((s) => s.setDepartment);
  const [loading, setLoading] = useState(!department);
  const [editMode, setEditMode] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  useEffect(() => {
    apiRequest<{ department: DepartmentInfo }>("/api/departments/profile")
      .then((res) => setDepartment(res.department))
      .catch((err) =>
        setFetchError(
          err instanceof Error
            ? err.message
            : "Failed to load department profile.",
        ),
      )
      .finally(() => setLoading(false));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading) {
    return (
      <AppShell subtitle="Department" title="Loading...">
        <Card className="py-16 text-center text-on-surface-variant">
          <LoadingDots sizeClassName="h-5 w-5" />
        </Card>
      </AppShell>
    );
  }

  if (!department) {
    return (
      <AppShell
        subtitle="Department"
        title={fetchError ? "Error" : "No Department Profile"}
      >
        <Card className="py-16 text-center">
          {fetchError ? (
            <>
              <span className="material-symbols-outlined mb-4 block text-5xl text-error">
                cloud_off
              </span>
              <p className="text-error">{fetchError}</p>
            </>
          ) : (
            <p className="text-on-surface-variant">
              No department profile found. Contact the administrator.
            </p>
          )}
        </Card>
      </AppShell>
    );
  }

  const status = department.verification_status;

  if (status === "pending") {
    return (
      <AppShell
        subtitle="Awaiting verification"
        title="Department Registration"
      >
        <Card className="mx-auto max-w-xl py-12 text-center">
          <div className="mb-6 inline-flex h-16 w-16 items-center justify-center rounded-full bg-[#ffdbd0]">
            <span className="material-symbols-outlined text-3xl text-secondary">
              hourglass_empty
            </span>
          </div>
          <h2 className="font-headline text-2xl text-on-surface">
            Awaiting Verification
          </h2>
          <p className="mx-auto mt-3 max-w-md text-on-surface-variant">
            Your department registration for <strong>{department.name}</strong>{" "}
            is pending municipality approval. Operational features unlock once
            approved.
          </p>
          <DeptDetails department={department} />
        </Card>
      </AppShell>
    );
  }

  if (status === "rejected") {
    return (
      <AppShell
        subtitle="Verification rejected"
        title="Department Registration"
      >
        <DepartmentRejectedView
          department={department}
          editMode={editMode}
          onUpdated={(d) => setDepartment(d)}
          setEditMode={setEditMode}
        />
      </AppShell>
    );
  }

  return (
    <AppShell
      hidePageHeading
      subtitle="Responder operations"
      title={department.name}
    >
      <DepartmentDashboard department={department} />
    </AppShell>
  );
}

type ReportSummary = {
  id: string;
  title?: string | null;
  description?: string | null;
  status: string;
  category?: string | null;
  severity?: string | null;
  created_at?: string | null;
  address?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  is_escalated?: boolean;
  visible_via?: string;
  response_summary?: {
    accepted: number;
    declined: number;
    pending: number;
  };
  current_response?: {
    action?: string | null;
    responded_at?: string | null;
  } | null;
};

const DEFAULT_MAP_CENTER: [number, number] = [14.5995, 120.9842];

function DepartmentDashboard({ department }: { department: DepartmentInfo }) {
  const [reports, setReports] = useState<ReportSummary[]>([]);
  const [reportsLoading, setReportsLoading] = useState(true);

  useEffect(() => {
    apiRequest<{ reports: ReportSummary[] }>("/api/departments/reports")
      .then((res) => setReports(Array.isArray(res.reports) ? res.reports : []))
      .catch(() => setReports([]))
      .finally(() => setReportsLoading(false));
  }, []);

  const pendingCount = reports.filter(
    (report) => report.status === "pending",
  ).length;
  const activeCount = reports.filter(
    (report) => report.status === "accepted" || report.status === "responding",
  ).length;
  const resolvedCount = reports.filter(
    (report) => report.status === "resolved",
  ).length;
  const totalCount = reports.length;
  const recentReports = reports.slice(0, 6);
  const alertReports = reports
    .filter((report) => report.status !== "resolved")
    .slice(0, 8);
  const geoReports = reports
    .filter(
      (
        report,
      ): report is ReportSummary & { latitude: number; longitude: number } =>
        typeof report.latitude === "number" &&
        Number.isFinite(report.latitude) &&
        typeof report.longitude === "number" &&
        Number.isFinite(report.longitude),
    )
    .slice(0, 12);
  const mapStatCards = [
    {
      label: "Pending Dispatch",
      value: pendingCount,
      icon: "crisis_alert",
      accent: "from-[#be3f32] to-[#df7a61]",
      tone: "text-[#a3382c]",
      detail: "Awaiting acceptance",
    },
    {
      label: "Active Response",
      value: activeCount,
      icon: "radio_button_checked",
      accent: "from-[#c77c15] to-[#efb24b]",
      tone: "text-[#9a5f0c]",
      detail: activeCount === 1 ? "Team in motion" : "Teams in motion",
    },
    {
      label: "Resolved Cases",
      value: resolvedCount,
      icon: "task_alt",
      accent: "from-[#356f57] to-[#68ab8a]",
      tone: "text-[#245541]",
      detail: resolvedCount === 1 ? "Closed incident" : "Closed incidents",
    },
    {
      label: "Total Routed",
      value: totalCount,
      icon: "stacked_bar_chart",
      accent: "from-[#54443c] to-[#8d7769]",
      tone: "text-[#4d4038]",
      detail: totalCount === 1 ? "Visible report" : "Visible reports",
    },
  ] as const;

  const dashboardActions = [
    {
      title: "Incident Board",
      description: "Review routed incidents and dispatch activity.",
      icon: "assignment",
      to: "/department/reports",
      iconClassName: "bg-[#ffe4db] text-[#a94c2d]",
    },
    {
      title: "Create Post",
      description: "Publish advisories, updates, and field notices.",
      icon: "edit_square",
      to: "/department/news-feed?compose=1",
      iconClassName: "bg-[#f4eadf] text-[#6a564a]",
    },
    {
      title: "Notifications",
      description: "Check fresh alerts and operational changes.",
      icon: "notifications",
      to: "/notifications",
      iconClassName: "bg-[#fff2df] text-[#9b681f]",
    },
    {
      title: "Department Profile",
      description: "Review the agency card and registration details.",
      icon: "badge",
      to: "/department/profile",
      iconClassName: "bg-[#e9efe8] text-[#46664e]",
    },
  ] as const;

  return (
    <div className="space-y-6">
      <DepartmentPageHero
        chips={[
          formatDepartmentType(department.type),
          department.area_of_responsibility?.trim() || "Municipal coverage",
        ]}
        dataTestId="department-page-hero"
        eyebrow="Department Command Center"
        headingTone="soft-light"
        icon="dashboard"
        title={department.name}
      />

      <section className="grid gap-6 xl:grid-cols-[minmax(0,1.58fr)_360px]">
        <section
          className="overflow-visible rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]"
          data-testid="department-operations-shell"
        >
          <div className="space-y-3">
            <LiveMapPlaceholderCard
              mapStatCards={mapStatCards}
              geoReports={geoReports}
              reportsLoading={reportsLoading}
            />
            <IncidentActivityBoard
              reports={recentReports}
              reportsLoading={reportsLoading}
            />
          </div>
        </section>

        <div className="space-y-6">
          <div className="overflow-visible rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]">
            <DepartmentProfileRail department={department} />
          </div>
          <div className="overflow-visible rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]">
            <QuickAccessPanel actions={dashboardActions} />
          </div>
          <div className="overflow-visible rounded-[34px] bg-[#f7efe7] p-3 shadow-[rgba(50,50,93,0.18)_0px_30px_50px_-12px_inset,rgba(0,0,0,0.16)_0px_18px_26px_-18px_inset]">
            <RecentAlertsPanel
              reports={alertReports}
              reportsLoading={reportsLoading}
            />
          </div>
        </div>
      </section>
    </div>
  );
}

function LiveMapPlaceholderCard({
  mapStatCards,
  geoReports,
  reportsLoading,
}: {
  mapStatCards: ReadonlyArray<{
    label: string;
    value: number;
    icon: string;
    accent: string;
    tone: string;
    detail: string;
  }>;
  geoReports: Array<ReportSummary & { latitude: number; longitude: number }>;
  reportsLoading: boolean;
}) {
  return (
    <div className="space-y-3">
      <Card
        className="rounded-[30px] border-[#eadfd5] bg-[#fffaf6] p-5 shadow-[0_22px_48px_rgba(132,94,59,0.1)] sm:p-6"
        data-testid="department-map-stats-panel"
      >
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {mapStatCards.map((card) => (
            <div
              key={card.label}
              className="relative overflow-hidden rounded-[22px] border border-[#ecdcd0] bg-[#fffdfb] p-4 shadow-[0_14px_35px_rgba(95,66,44,0.06)]"
            >
              <div
                className={`absolute left-0 top-4 h-12 w-1 rounded-full bg-gradient-to-b ${card.accent}`}
              />
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-[0.22em] text-[#7c685d]">
                    {card.label}
                  </p>
                  <p
                    className={`mt-3 text-3xl font-semibold leading-none ${card.tone}`}
                  >
                    {reportsLoading ? "..." : formatMetricValue(card.value)}
                  </p>
                  <p className="mt-2 text-[13px] text-[#8a7669]">
                    {reportsLoading ? "Syncing operational feed" : card.detail}
                  </p>
                </div>
                <div className="rounded-[18px] bg-[#faf1eb] p-2.5 text-[#d3c0b4]">
                  <span className="material-symbols-outlined text-[24px]">
                    {card.icon}
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </Card>

      <Card
        className="rounded-[30px] border-[#eadfd5] bg-[#fffaf6] p-5 shadow-[0_22px_48px_rgba(132,94,59,0.1)] sm:p-6"
        data-testid="department-map-view-panel"
      >
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <span className="material-symbols-outlined text-[22px] text-[#c84436]">
              map
            </span>
            <div>
              <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#3b2a24]">
                Live Map View
              </p>
              <p className="mt-1 text-sm text-[#7d6a5f]">
                Placeholder surface for real-time GIS and field telemetry.
              </p>
            </div>
          </div>
          <span className="rounded-full bg-[#fbe9e6] px-4 py-2 text-[11px] font-bold uppercase tracking-[0.24em] text-[#bf3b31]">
            Placeholder
          </span>
        </div>

        <div
          className="relative mt-5 min-h-[365px] overflow-hidden rounded-[30px] border border-[#d8c9bc] bg-[#f8f1ea] sm:min-h-[425px]"
          data-testid="department-live-map-placeholder"
        >
          <div className="absolute inset-0">
            <DepartmentDashboardMap geoReports={geoReports} />
          </div>
        </div>
      </Card>
    </div>
  );
}

function DepartmentDashboardMap({
  geoReports,
}: {
  geoReports: Array<ReportSummary & { latitude: number; longitude: number }>;
}) {
  const mapPoints = geoReports.map(
    (report) => [report.latitude, report.longitude] as [number, number],
  );

  return (
    <MapContainer
      center={mapPoints[0] ?? DEFAULT_MAP_CENTER}
      className="h-full w-full"
      scrollWheelZoom
      zoom={mapPoints.length > 0 ? 13 : 11}
      zoomControl={false}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <DepartmentDashboardMapViewport points={mapPoints} />

      {geoReports.map((report) => (
        <Marker
          key={report.id}
          icon={departmentDashboardReportIcon(report.category)}
          position={[report.latitude, report.longitude]}
          title={`dashboard-report:${report.id}`}
        >
          <Popup>
            <div className="space-y-2 text-sm text-[#4e4742]">
              <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                Live Incident
              </p>
              <p className="font-semibold text-[#373831]">
                {reportTitle(report)}
              </p>
              <p>{reportPreview(report)}</p>
              <div className="flex flex-wrap gap-2 text-[11px] font-medium text-[#6f625b]">
                <span>Status: {formatLabel(report.status)}</span>
                {report.category ? (
                  <span>Category: {formatLabel(report.category)}</span>
                ) : null}
              </div>
            </div>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
}

function DepartmentDashboardMapViewport({
  points,
}: {
  points: Array<[number, number]>;
}) {
  const map = useMap();

  useEffect(() => {
    if (points.length === 0) {
      map.setView(DEFAULT_MAP_CENTER, 11);
      return;
    }

    if (points.length === 1) {
      map.setView(points[0], 14);
      return;
    }

    map.fitBounds(latLngBounds(points), {
      animate: true,
      padding: [36, 36],
    });
  }, [map, points]);

  return null;
}

function departmentDashboardReportIcon(category?: string | null) {
  return divIcon({
    className: "mesh-sar-icon-shell",
    iconSize: [22, 22],
    iconAnchor: [11, 11],
    popupAnchor: [0, -14],
    html: `
      <span class="mesh-sar-report-marker mesh-sar-report-marker--${(category || "other").replace(/_/g, "-")}">
        <span class="mesh-sar-report-marker__core"></span>
      </span>
    `,
  });
}

function QuickAccessPanel({
  actions,
}: {
  actions: ReadonlyArray<{
    title: string;
    description: string;
    icon: string;
    to: string;
    iconClassName: string;
  }>;
}) {
  const compactActionCopy: Record<string, string> = {
    "Incident Board": "Reports and dispatch",
    "Create Post": "Advisories and updates",
    Notifications: "Alerts and changes",
    "Department Profile": "Agency details",
  };

  return (
    <Card
      className="rounded-[30px] border-[#eadfd5] bg-[#fffaf6] p-5 shadow-[0_22px_48px_rgba(132,94,59,0.1)] sm:p-6"
      data-testid="department-quick-access"
    >
      <div className="flex items-center gap-3">
        <span className="material-symbols-outlined text-[18px] text-[#c56a46]">
          bolt
        </span>
        <div>
          <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#3b2a24]">
            Quick Access
          </p>
          <p className="mt-1 text-[13px] text-[#7d6a5f]">
            Responder shortcuts.
          </p>
        </div>
      </div>

      <div className="mt-4 grid gap-2.5 sm:grid-cols-2 xl:grid-cols-2">
        {actions.map((action) => (
          <Link
            key={action.title}
            className="group rounded-[20px] border border-[#efe1d7] bg-white px-3.5 py-3.5 shadow-[0_22px_44px_rgba(112,78,50,0.16)] transition-all duration-200 hover:-translate-y-0.5 hover:border-[#e5c8b8] hover:shadow-[0_22px_44px_rgba(112,78,50,0.16)]"
            to={action.to}
          >
            <div className="flex items-start justify-between gap-3">
              <div
                className={`inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-[14px] ${action.iconClassName}`}
              >
                <span className="material-symbols-outlined text-[18px]">
                  {action.icon}
                </span>
              </div>
              <span className="material-symbols-outlined text-[18px] text-[#cfb2a1] transition-colors group-hover:text-[#a14b2f]">
                north_east
              </span>
            </div>
            <h3 className="mt-3 text-[15px] font-semibold leading-5 text-[#2f211c] transition-colors group-hover:text-[#a14b2f]">
              {action.title}
            </h3>
            <p className="mt-1.5 text-[12px] leading-5 text-[#7d6a5f]">
              {compactActionCopy[action.title] || action.description}
            </p>
          </Link>
        ))}
      </div>
    </Card>
  );
}

function RecentAlertsPanel({
  reports,
  reportsLoading,
}: {
  reports: ReportSummary[];
  reportsLoading: boolean;
}) {
  const hasScrollableAlerts = reports.length > 2;

  return (
    <Card className="rounded-[30px] border-[#eadfd5] bg-[#fffaf6] p-6 shadow-[0_20px_55px_rgba(82,58,43,0.08)]">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#3b2a24]">
            Recent Alerts
          </p>
          <p className="mt-1 text-sm text-[#7d6a5f]">
            Latest routed items visible to your agency.
          </p>
        </div>
        <span className="text-[10px] font-bold uppercase tracking-[0.24em] text-[#b58b77]">
          Live updates
        </span>
      </div>

      <div
        className={`mt-5 space-y-4 ${hasScrollableAlerts ? "max-h-[18.25rem] overflow-y-auto pr-2" : ""}`}
      >
        {reportsLoading ? (
          <div className="py-8 text-center">
            <LoadingDots sizeClassName="h-4 w-4" />
          </div>
        ) : reports.length === 0 ? (
          <div className="rounded-[20px] border border-dashed border-[#eadfd5] bg-[#fff] px-4 py-5 text-sm text-[#7d6a5f]">
            No active alerts yet. New routed incidents will appear here.
          </div>
        ) : (
          reports.map((report) => {
            const severity = severityTone(report.severity);
            return (
              <Link
                key={report.id}
                className="block rounded-[22px] border border-[#efe2d8] bg-white px-4 py-4 shadow-[0_22px_46px_rgba(112,78,50,0.16)] transition-all duration-200 hover:border-[#e5c8b8] hover:shadow-[0_22px_46px_rgba(112,78,50,0.16)]"
                to={`/department/reports/${report.id}`}
              >
                <div className="flex items-start gap-3">
                  <span
                    className={`mt-1 h-2.5 w-2.5 shrink-0 rounded-full ${severity.dotClassName}`}
                  />
                  <div className="min-w-0 flex-1">
                    <h3 className="text-sm font-semibold leading-6 text-[#2f211c]">
                      {reportTitle(report)}
                    </h3>
                    <p className="mt-1 text-sm leading-6 text-[#7d6a5f]">
                      {reportPreview(report)}
                    </p>
                    <div className="mt-3 flex flex-wrap items-center gap-2">
                      <span
                        className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] ${statusStyle(report.status)}`}
                      >
                        {formatLabel(report.status)}
                      </span>
                      <span className="text-[11px] font-semibold uppercase tracking-[0.18em] text-[#b58b77]">
                        {formatTimeAgo(report.created_at)}
                      </span>
                    </div>
                  </div>
                </div>
              </Link>
            );
          })
        )}
      </div>
    </Card>
  );
}

function IncidentActivityBoard({
  reports,
  reportsLoading,
}: {
  reports: ReportSummary[];
  reportsLoading: boolean;
}) {
  return (
    <Card
      className="flex h-full flex-col rounded-[30px] border-[#eadfd5] bg-[#fffaf6] p-5 shadow-[0_18px_40px_rgba(132,94,59,0.08)] sm:p-6"
      data-testid="department-activity-board"
    >
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p className="text-[11px] font-bold uppercase tracking-[0.28em] text-[#3b2a24]">
            Recent Incident Activity
          </p>
          <p className="mt-1 text-sm text-[#7d6a5f]">
            Latest assigned reports and routing status.
          </p>
        </div>
        <Link
          className="rounded-full border border-[#ead9cc] bg-white px-4 py-2 text-[11px] font-bold uppercase tracking-[0.22em] text-[#a14b2f] transition-colors hover:bg-[#fff2eb]"
          to="/department/reports"
        >
          Open board
        </Link>
      </div>

      {reportsLoading ? (
        <div className="py-12 text-center">
          <LoadingDots sizeClassName="h-4 w-4" />
        </div>
      ) : reports.length === 0 ? (
        <div className="mt-6 rounded-[24px] border border-dashed border-[#eadfd5] bg-white px-5 py-10 text-center text-sm text-[#7d6a5f]">
          No routed incidents yet. The activity board will populate once a
          report becomes visible to this department.
        </div>
      ) : (
        <>
          <div className="mt-6 space-y-3 lg:hidden">
            {reports.map((report) => (
              <Link
                key={report.id}
                className="block rounded-[22px] border border-[#efe2d8] bg-white px-4 py-4 shadow-[0_22px_46px_rgba(112,78,50,0.16)] transition-all duration-200 hover:border-[#e5c8b8] hover:shadow-[0_22px_46px_rgba(112,78,50,0.16)]"
                to={`/department/reports/${report.id}`}
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <h3 className="text-base font-semibold text-[#2f211c]">
                      {reportTitle(report)}
                    </h3>
                    <p className="mt-2 text-sm leading-6 text-[#7d6a5f]">
                      {reportPreview(report)}
                    </p>
                  </div>
                  <span className="text-[11px] font-bold uppercase tracking-[0.18em] text-[#b58b77]">
                    {formatTimeAgo(report.created_at)}
                  </span>
                </div>
                <div className="mt-4 flex flex-wrap items-center gap-2">
                  <span
                    className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] ${statusStyle(report.status)}`}
                  >
                    {formatLabel(report.status)}
                  </span>
                  <span className="rounded-full border border-[#ecd8cf] bg-[#fff8f3] px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] text-[#8a6d5d]">
                    {formatLabel(report.category || "general")}
                  </span>
                  <span className="rounded-full border border-[#ecd8cf] bg-[#fff] px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] text-[#8a6d5d]">
                    {formatVisibleRoute(report)}
                  </span>
                </div>
              </Link>
            ))}
          </div>

          <div className="mt-6 hidden min-h-[420px] flex-1 overflow-hidden rounded-[24px] border border-[#eee1d8] bg-white lg:flex lg:flex-col">
            <div className="grid grid-cols-[minmax(0,2.8fr)_minmax(110px,0.9fr)_minmax(110px,0.95fr)_minmax(138px,1fr)_88px] items-center gap-5 border-b border-[#eee1d8] bg-[#fbf5ef] px-5 py-4 text-[10px] font-bold uppercase tracking-[0.24em] text-[#8a6d5d]">
              <span>Incident</span>
              <span>Category</span>
              <span>Received</span>
              <span>Status</span>
              <span>Route</span>
            </div>

            <div className="divide-y divide-[#f1e7de]">
              {reports.map((report) => (
                <Link
                  key={report.id}
                  className="grid grid-cols-[minmax(0,2.8fr)_minmax(110px,0.9fr)_minmax(110px,0.95fr)_minmax(138px,1fr)_88px] items-center gap-5 px-5 py-4 transition-colors hover:bg-[#fdf8f3]"
                  to={`/department/reports/${report.id}`}
                >
                  <div className="min-w-0 self-start">
                    <p className="truncate text-[15px] font-semibold text-[#2f211c]">
                      {reportTitle(report)}
                    </p>
                    <p className="mt-1 truncate text-sm text-[#7d6a5f]">
                      {reportPreview(report)}
                    </p>
                  </div>
                  <div className="flex items-center min-w-0">
                    <span className="rounded-full border border-[#ecd8cf] bg-[#fff8f3] px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] text-[#8a6d5d]">
                      {formatLabel(report.category || "general")}
                    </span>
                  </div>
                  <div className="flex min-w-0 flex-col justify-center">
                    <span className="text-sm font-semibold text-[#3d2f29]">
                      {formatTimeAgo(report.created_at)}
                    </span>
                    <span className="mt-1 text-xs text-[#9b8578]">
                      {formatClockTime(report.created_at)}
                    </span>
                  </div>
                  <div className="flex items-center min-w-0">
                    <span
                      className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-[0.18em] ${statusStyle(report.status)}`}
                    >
                      {formatLabel(report.status)}
                    </span>
                  </div>
                  <div className="flex items-center min-w-0">
                    <span className="text-sm font-semibold text-[#6d564b]">
                      {formatVisibleRoute(report)}
                    </span>
                  </div>
                </Link>
              ))}
            </div>

            <div className="flex-1 bg-[#fffdfb]" />

            <div className="flex items-center justify-between border-t border-[#f1e7de] bg-[#fffaf6] px-5 py-3.5 text-[11px] text-[#9b8578]">
              <span>These are the latest routed incident updates visible to your agency.</span>
              <span className="font-semibold text-[#b58b77]">Live board snapshot</span>
            </div>
          </div>
        </>
      )}
    </Card>
  );
}

function statusStyle(status: string): string {
  switch (status) {
    case "pending":
      return "bg-[#ffdbd0] text-[#89391e]";
    case "accepted":
      return "bg-[#d0e4f7] text-[#2c4a6a]";
    case "responding":
      return "bg-[#ece7df] text-[#62554c]";
    case "resolved":
      return "bg-[#d4edda] text-[#155724]";
    default:
      return "bg-[#eee] text-[#666]";
  }
}

function severityTone(severity?: string | null) {
  switch (severity) {
    case "critical":
      return { dotClassName: "bg-[#be3f32]" };
    case "high":
      return { dotClassName: "bg-[#d97757]" };
    case "medium":
      return { dotClassName: "bg-[#d89a34]" };
    case "low":
      return { dotClassName: "bg-[#4f7c66]" };
    default:
      return { dotClassName: "bg-[#8d7b71]" };
  }
}

function reportTitle(report: ReportSummary) {
  return (
    report.title?.trim() || report.description?.trim() || "Untitled report"
  );
}

function reportPreview(report: ReportSummary) {
  const title = report.title?.trim();
  const description = report.description?.trim();

  if (description && description !== title) {
    return description;
  }

  if (report.address?.trim()) {
    return report.address.trim();
  }

  return "Field update pending additional incident details.";
}

function formatVisibleRoute(report: ReportSummary) {
  if (report.visible_via) {
    return formatLabel(report.visible_via);
  }
  return report.is_escalated ? "Escalation" : "Primary";
}

function formatMetricValue(value: number) {
  if (value >= 10) {
    return new Intl.NumberFormat().format(value);
  }
  return value.toString().padStart(2, "0");
}

function formatTimeAgo(iso?: string | null): string {
  if (!iso) {
    return "";
  }

  try {
    const diff = Date.now() - new Date(iso).getTime();
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) {
      return "just now";
    }
    if (minutes < 60) {
      return `${minutes}m ago`;
    }
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}h ago`;
    }
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  } catch {
    return "";
  }
}

function formatClockTime(iso?: string | null) {
  if (!iso) {
    return "";
  }

  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      minute: "2-digit",
    }).format(new Date(iso));
  } catch {
    return "";
  }
}

function formatLabel(value?: string | null) {
  if (!value) {
    return "";
  }

  return value
    .replace(/_/g, " ")
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function DeptDetails({ department }: { department: DepartmentInfo }) {
  return (
    <div className="mt-6 space-y-4 rounded-[20px] border border-[#eadfd5] bg-[#fffaf5] p-5 text-left">
      <DetailRow label="Type" value={formatDepartmentType(department.type)} />
      {department.contact_number ? (
        <DetailRow label="Contact" value={department.contact_number} />
      ) : null}
      {department.address ? (
        <DetailRow label="Address" value={department.address} />
      ) : null}
      {department.area_of_responsibility ? (
        <DetailRow label="Area" value={department.area_of_responsibility} />
      ) : null}
    </div>
  );
}

function DepartmentProfileRail({ department }: { department: DepartmentInfo }) {
  const profileImage = department.profile_picture || department.profile_photo;
  const coverageChips = (
    department.area_of_responsibility || "Municipal coverage"
  )
    .split(/[,\n/]+/)
    .map((value) => value.trim())
    .filter(Boolean)
    .slice(0, 3);
  const compactProfileDetails = [
    {
      label: "Agency Type",
      value: formatDepartmentType(department.type),
      icon: "business",
    },
    {
      label: "Official Address",
      value: department.address || "Address not provided yet",
      icon: "location_on",
    },
    {
      label: "Contact Terminal",
      value: department.contact_number || "Contact number pending",
      icon: "call",
    },
    {
      label: "Area Coverage",
      value: coverageChips.join(" • ") || "Municipal coverage",
      icon: "globe",
    },
  ] as const;

  return (
    <Card className="rounded-[30px] border-[#eadfd5] bg-[#fffaf6] p-5 shadow-[0_22px_48px_rgba(132,94,59,0.1)] sm:p-6">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex items-center gap-3">
          {profileImage ? (
            <img
              alt={department.name}
              className="h-11 w-11 rounded-[16px] object-cover shadow-[0_10px_20px_rgba(0,0,0,0.12)]"
              src={profileImage}
            />
          ) : (
            <div className="flex h-11 w-11 items-center justify-center rounded-[16px] bg-[linear-gradient(180deg,#55291b_0%,#241714_100%)] text-white shadow-[0_10px_20px_rgba(0,0,0,0.12)]">
              <span className="material-symbols-outlined text-[18px]">
                local_fire_department
              </span>
            </div>
          )}

          <div className="min-w-0">
            <p className="text-[10px] font-black uppercase tracking-[0.12em] text-[#5d3d2c]">
              Department Profile
            </p>
            <h2 className="mt-1 truncate font-headline text-[1.45rem] leading-[0.96] text-[#221814]">
              {department.name}
            </h2>
            <p className="mt-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-[#9c4f28]">
              Active Agency
            </p>
          </div>
        </div>

        <span className="mt-1 inline-flex h-8 w-8 items-center justify-center rounded-full border border-[#eccdbb] text-[#bf7347]">
          <span className="material-symbols-outlined text-[14px]">target</span>
        </span>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3">
        <div className="rounded-[18px] border border-[#efe1d5] bg-[#fff7f1] px-4 py-3 shadow-[0_14px_32px_rgba(95,66,44,0.07)]">
          <p className="text-[9px] font-extrabold uppercase tracking-[0.14em] text-[#875740]">
            Registry ID
          </p>
          <p className="mt-1 text-[12px] font-semibold uppercase tracking-[0.12em] text-[#4f392d]">
            {formatRegistryDisplayId(department.id)}
          </p>
        </div>
        <div className="rounded-[18px] border border-[#efe1d5] bg-[#fff7f1] px-4 py-3 shadow-[0_14px_32px_rgba(95,66,44,0.07)]">
          <p className="text-[9px] font-extrabold uppercase tracking-[0.14em] text-[#875740]">
            Coverage
          </p>
          <p className="mt-1 text-[12px] font-semibold uppercase tracking-[0.12em] text-[#4f392d]">
            {coverageChips.length} zone{coverageChips.length === 1 ? "" : "s"}
          </p>
        </div>
      </div>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {compactProfileDetails.map((detail) => (
          <div
            key={detail.label}
            className="rounded-[18px] border border-[#efe4db] bg-white px-3.5 py-3 shadow-[0_14px_32px_rgba(95,66,44,0.07)]"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-[12px] bg-[#f7ede5] text-[#b98f76]">
                <span className="material-symbols-outlined text-[16px]">
                  {detail.icon}
                </span>
              </div>
              <p className="text-[9px] font-extrabold uppercase tracking-[0.14em] text-[#875740]">
                {detail.label}
              </p>
            </div>
            <div className="mt-3 border-t border-[#f1e5dc] pt-3">
              <p className="text-[13px] leading-5 text-[#3f3028]">
                {detail.value}
              </p>
            </div>
          </div>
        ))}
      </div>

    </Card>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <span className="text-sm text-[#8b7b71]">{label}</span>
      <span className="max-w-[60%] text-right text-sm font-medium text-on-surface">
        {value}
      </span>
    </div>
  );
}

function formatDepartmentType(value?: string | null) {
  if (!value) {
    return "Department";
  }

  return value
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function formatRegistryDisplayId(id: string) {
  const compact = id.replace(/-/g, "").toUpperCase();
  if (compact.length <= 9) {
    return compact || "8842-DRR-BFP";
  }

  return `${compact.slice(0, 4)}-${compact.slice(4, 7)}-${compact.slice(7, 10)}`;
}

function DepartmentRejectedView({
  department,
  onUpdated,
  editMode,
  setEditMode,
}: {
  department: DepartmentInfo;
  onUpdated: (d: DepartmentInfo) => void;
  editMode: boolean;
  setEditMode: (v: boolean) => void;
}) {
  const [name, setName] = useState(department.name);
  const [contactNumber, setContactNumber] = useState(
    department.contact_number ?? "",
  );
  const [address, setAddress] = useState(department.address ?? "");
  const [area, setArea] = useState(department.area_of_responsibility ?? "");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleResubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await apiRequest<{ department: DepartmentInfo }>(
        "/api/departments/profile",
        {
          method: "PUT",
          body: JSON.stringify({
            name,
            contact_number: contactNumber,
            address,
            area_of_responsibility: area,
          }),
        },
      );
      onUpdated(res.department);
      setEditMode(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Card className="mx-auto max-w-xl">
      <div className="mb-6 text-center">
        <div className="mb-4 inline-flex h-16 w-16 items-center justify-center rounded-full bg-error-container/20">
          <span className="material-symbols-outlined text-3xl text-error">
            close
          </span>
        </div>
        <h2 className="font-headline text-2xl text-on-surface">
          Registration Rejected
        </h2>
      </div>

      {department.rejection_reason && (
        <div className="mb-6 rounded-md border border-error/15 bg-error-container/15 px-4 py-3 text-sm text-error">
          <span className="font-semibold">Reason:</span>{" "}
          {department.rejection_reason}
        </div>
      )}

      {editMode ? (
        <form className="space-y-4" onSubmit={handleResubmit}>
          {error && (
            <div className="rounded-md border border-error/20 bg-error-container/20 px-4 py-3 text-sm text-error">
              {error}
            </div>
          )}
          <div>
            <label className="aegis-label">Organization Name</label>
            <input
              className="aegis-input"
              onChange={(e) => setName(e.target.value)}
              placeholder="Organization name"
              type="text"
              value={name}
            />
          </div>
          <div>
            <label className="aegis-label">Contact Number</label>
            <input
              className="aegis-input"
              onChange={(e) => setContactNumber(e.target.value)}
              placeholder="Contact number"
              type="text"
              value={contactNumber}
            />
          </div>
          <div>
            <label className="aegis-label">Address</label>
            <input
              className="aegis-input"
              onChange={(e) => setAddress(e.target.value)}
              placeholder="Address"
              type="text"
              value={address}
            />
          </div>
          <div>
            <label className="aegis-label">Area of Responsibility</label>
            <input
              className="aegis-input"
              onChange={(e) => setArea(e.target.value)}
              placeholder="Area of responsibility"
              type="text"
              value={area}
            />
          </div>
          <div className="flex gap-3 pt-2">
            <Button disabled={loading} type="submit">
              {loading ? "Submitting..." : "Resubmit for Verification"}
            </Button>
            <Button
              onClick={() => setEditMode(false)}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
          </div>
        </form>
      ) : (
        <div className="text-center">
          <p className="mb-6 text-sm text-on-surface-variant">
            Update your department details and resubmit for verification.
          </p>
          <Button onClick={() => setEditMode(true)} variant="secondary">
            <span className="material-symbols-outlined mr-2 text-[16px]">
              edit
            </span>
            Edit & Resubmit
          </Button>
        </div>
      )}
    </Card>
  );
}

import { useEffect, useMemo, useState } from "react";

import {
  MeshSarMap,
  type DisasterReportMarker,
  type MeshDeviceTrail,
  type MeshDeviceTrailPoint,
  type MeshSurvivorSignal,
  type MeshTopologyNode,
} from "@/components/maps/mesh-sar-map";
import { AppShell } from "@/components/layout/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type TopologyResponse = {
  nodes: Array<
    Omit<MeshTopologyNode, "lat" | "lng"> & {
      coordinates?: [number, number] | null;
      lat?: number;
      lng?: number;
    }
  >;
  responders: Array<
    Omit<MeshTopologyNode, "lat" | "lng"> & {
      coordinates?: [number, number] | null;
      lat?: number;
      lng?: number;
    }
  >;
  count: number;
  responder_count: number;
  synced_at: string;
};

type SurvivorSignalResponse = {
  survivor_signals: Array<
    Omit<MeshSurvivorSignal, "lat" | "lng"> & {
      coordinates?: [number, number] | null;
    }
  >;
  count: number;
};

type TrailPointResponse =
  Omit<MeshDeviceTrailPoint, "lat" | "lng"> & {
    coordinates?: [number, number] | null;
    lat?: number;
    lng?: number;
  };

type LastSeenResponse = {
  devices: TrailPointResponse[];
  count: number;
};

type TrailResponse = {
  device_fingerprint: string;
  points: TrailPointResponse[];
  count: number;
  last_seen?: TrailPointResponse | null;
};

type MeshCommsMessage = {
  id: string;
  thread_id?: string | null;
  recipient_scope: string;
  recipient_identifier?: string | null;
  body: string;
  author_display_name: string;
  author_role: string;
  created_at: string;
};

type MeshCommsResponse = {
  messages: MeshCommsMessage[];
  mesh_posts?: Array<{
    id: string;
    title: string;
    content?: string;
    category?: string;
    created_at: string;
  }>;
};

type MunicipalityReportResponse = {
  reports: Array<
    | DisasterReportMarker
    | (Omit<DisasterReportMarker, "latitude" | "longitude"> & {
        latitude?: number | null;
        longitude?: number | null;
      })
  >;
};

const warmPanelClassName = "border-[#efd8d0] bg-[#fff8f3]";
const warmTabClassName = "border border-[#ecd8cf] bg-[#f7efe7] text-[#6f625b]";
const warmActionTabClassName =
  "border border-[#ecd8cf] bg-[#f7efe7] text-[#8a5a40] transition-colors hover:bg-[#f2e7de]";
const RECENT_RESOLVED_WINDOW_MS = 30 * 60 * 1000;

const meshLegend = [
  { label: "Gateway", swatchClassName: "mesh-sar-node-marker mesh-sar-node-marker--gateway" },
  { label: "Relay", swatchClassName: "mesh-sar-node-marker mesh-sar-node-marker--relay" },
  { label: "Origin / Offline", swatchClassName: "mesh-sar-node-marker mesh-sar-node-marker--origin" },
  { label: "Responder", swatchClassName: "mesh-sar-responder-marker" },
  { label: "Survivor Signal", swatchClassName: "mesh-sar-survivor-marker" },
  { label: "Location Trail", swatchClassName: "mesh-sar-trail-pin mesh-sar-trail-pin--foreground" },
] as const;

function toMapNode(
  node: TopologyResponse["nodes"][number] | TopologyResponse["responders"][number],
): MeshTopologyNode | null {
  const coords = node.coordinates;
  const lat = typeof node.lat === "number" ? node.lat : coords?.[1];
  const lng = typeof node.lng === "number" ? node.lng : coords?.[0];
  if (typeof lat !== "number" || typeof lng !== "number") {
    return null;
  }
  return { ...node, lat, lng };
}

function toMapSignal(signal: SurvivorSignalResponse["survivor_signals"][number]): MeshSurvivorSignal | null {
  const coords = signal.coordinates;
  const lat = coords?.[1];
  const lng = coords?.[0];
  if (typeof lat !== "number" || typeof lng !== "number") {
    return null;
  }
  return { ...signal, lat, lng };
}

function toMapReport(report: MunicipalityReportResponse["reports"][number]): DisasterReportMarker | null {
  if (typeof report.latitude !== "number" || typeof report.longitude !== "number") {
    return null;
  }
  return report as DisasterReportMarker;
}

function toTrailPoint(point: TrailPointResponse): MeshDeviceTrailPoint | null {
  const coords = point.coordinates;
  const lat = typeof point.lat === "number" ? point.lat : coords?.[1];
  const lng = typeof point.lng === "number" ? point.lng : coords?.[0];
  if (typeof lat !== "number" || typeof lng !== "number") {
    return null;
  }
  return {
    ...point,
    lat,
    lng,
    app_state: point.app_state ?? "foreground",
  };
}

function toTrailDevice(response: TrailResponse): MeshDeviceTrail | null {
  const points = response.points.map(toTrailPoint).filter((point): point is MeshDeviceTrailPoint => point !== null);
  const lastSeen = response.last_seen ? toTrailPoint(response.last_seen) : points.at(-1) ?? null;
  if (!lastSeen) {
    return null;
  }
  return {
    device_fingerprint: response.device_fingerprint,
    display_name: lastSeen.display_name,
    battery_pct: lastSeen.battery_pct,
    app_state: lastSeen.app_state,
    recorded_at: lastSeen.recorded_at,
    lat: lastSeen.lat,
    lng: lastSeen.lng,
    points,
  };
}

function formatDateTime(value?: string | null) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString();
}

function isRecentResolved(signal: MeshSurvivorSignal) {
  if (!signal.resolved || !signal.resolved_at) {
    return false;
  }
  return Date.now() - new Date(signal.resolved_at).getTime() <= RECENT_RESOLVED_WINDOW_MS;
}

function titleCase(value: string) {
  return value.replace(/_/g, " ");
}

function formatCoordinates(lat: number, lng: number) {
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
}

export function MunicipalityMeshPage() {
  const accessToken = useSessionStore((state) => state.accessToken);
  const [meshLayerEnabled, setMeshLayerEnabled] = useState(true);
  const [showResolved, setShowResolved] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [topologyNodes, setTopologyNodes] = useState<MeshTopologyNode[]>([]);
  const [responderNodes, setResponderNodes] = useState<MeshTopologyNode[]>([]);
  const [survivorSignals, setSurvivorSignals] = useState<MeshSurvivorSignal[]>([]);
  const [deviceTrails, setDeviceTrails] = useState<MeshDeviceTrail[]>([]);
  const [selectedTrailDeviceFingerprint, setSelectedTrailDeviceFingerprint] = useState<string | null>(null);
  const [reports, setReports] = useState<DisasterReportMarker[]>([]);
  const [recentMessages, setRecentMessages] = useState<MeshCommsMessage[]>([]);
  const [recentMeshPosts, setRecentMeshPosts] = useState<
    Array<{ id: string; title: string; content?: string; category?: string; created_at: string }>
  >([]);
  const [resolvingSignalId, setResolvingSignalId] = useState<string | null>(null);

  async function fetchTopology() {
    const response = await apiRequest<TopologyResponse>("/api/mesh/topology");
    setTopologyNodes(response.nodes.map(toMapNode).filter((node): node is MeshTopologyNode => node !== null));
    setResponderNodes(
      response.responders.map(toMapNode).filter((node): node is MeshTopologyNode => node !== null),
    );
  }

  async function fetchSignals() {
    const response = await apiRequest<SurvivorSignalResponse>("/api/mesh/survivor-signals");
    setSurvivorSignals(
      response.survivor_signals
        .map(toMapSignal)
        .filter((signal): signal is MeshSurvivorSignal => signal !== null),
    );
  }

  async function fetchLocationTrails() {
    const lastSeenResponse = await apiRequest<LastSeenResponse>("/api/mesh/last-seen");
    const lastSeenDevices = lastSeenResponse.devices
      .map(toTrailPoint)
      .filter((device): device is MeshDeviceTrailPoint => device !== null);

    if (lastSeenDevices.length === 0) {
      setDeviceTrails([]);
      setSelectedTrailDeviceFingerprint(null);
      return;
    }

    const trailResponses = await Promise.all(
      lastSeenDevices.map((device) =>
        apiRequest<TrailResponse>(`/api/mesh/trail/${encodeURIComponent(device.device_fingerprint)}?limit=60`).catch(
          () => ({
            device_fingerprint: device.device_fingerprint,
            points: [device],
            count: 1,
            last_seen: device,
          }),
        ),
      ),
    );

    const trails = trailResponses
      .map(toTrailDevice)
      .filter((trail): trail is MeshDeviceTrail => trail !== null)
      .sort((a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime());

    setDeviceTrails(trails);
    setSelectedTrailDeviceFingerprint((current) => {
      if (current && trails.some((trail) => trail.device_fingerprint === current)) {
        return current;
      }
      return trails[0]?.device_fingerprint ?? null;
    });
  }

  async function fetchMessages() {
    const response = await apiRequest<MeshCommsResponse>("/api/mesh/messages?include_posts=1");
    setRecentMessages(response.messages.slice(-6).reverse());
    setRecentMeshPosts((response.mesh_posts ?? []).slice(0, 4));
  }

  async function fetchReports() {
    const response = await apiRequest<MunicipalityReportResponse>("/api/municipality/reports");
    setReports(response.reports.map(toMapReport).filter((report): report is DisasterReportMarker => report !== null));
  }

  async function refreshDashboard(showLoader = true) {
    setError(null);
    if (showLoader) {
      setLoading(true);
    } else {
      setRefreshing(true);
    }

    try {
      await Promise.all([
        fetchTopology(),
        fetchSignals(),
        fetchLocationTrails(),
        fetchReports(),
        fetchMessages(),
      ]);
    } catch (refreshError) {
      setError(refreshError instanceof Error ? refreshError.message : "Unable to load mesh dashboard.");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  async function handleResolveSignal(signalId: string) {
    setResolvingSignalId(signalId);
    try {
      await apiRequest(`/api/mesh/survivor-signals/${signalId}/resolve`, {
        method: "PUT",
        body: JSON.stringify({ note: "Resolved from the municipality mesh dashboard." }),
      });
      await fetchSignals();
    } catch (resolveError) {
      setError(resolveError instanceof Error ? resolveError.message : "Unable to resolve survivor signal.");
    } finally {
      setResolvingSignalId(null);
    }
  }

  useEffect(() => {
    queueMicrotask(() => {
      void refreshDashboard();
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const intervalId = window.setInterval(() => {
      void Promise.all([fetchTopology(), fetchLocationTrails()]);
    }, 30_000);

    return () => window.clearInterval(intervalId);
  }, []);

  useEffect(() => {
    const subscription = subscribeToTable(
      "survivor_signals",
      () => {
        void fetchSignals();
      },
      { accessToken },
    );
    return () => subscription.unsubscribe();
  }, [accessToken]);

  const activeSignalCount = survivorSignals.filter((signal) => !signal.resolved).length;
  const visibleSignals = survivorSignals.filter(
    (signal) => !signal.resolved || isRecentResolved(signal) || showResolved,
  );
  const staleNodeCount = topologyNodes.filter((node) => node.is_stale).length;
  const selectedTrail = useMemo(
    () => deviceTrails.find((trail) => trail.device_fingerprint === selectedTrailDeviceFingerprint) ?? deviceTrails[0] ?? null,
    [deviceTrails, selectedTrailDeviceFingerprint],
  );
  const recentTrailPoints = selectedTrail ? [...selectedTrail.points].slice(-10).reverse() : [];

  return (
    <AppShell subtitle="Interactive mesh and survivor oversight" title="Mesh & SAR">
      <div className="space-y-8">
        <section className="overflow-hidden rounded-[28px] border border-[#d8b7aa] bg-gradient-to-br from-[#a14b2f] via-[#8f4427] to-[#5f5e5c] p-6 text-white shadow-xl">
          <div className="flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between">
            <div className="max-w-3xl">
              <span className="inline-flex rounded-full border border-white/20 bg-white/10 px-3 py-1 text-[11px] font-bold uppercase tracking-[0.24em] text-white/90">
                Municipality View
              </span>
              <h2 className="mt-4 font-headline text-3xl lg:text-4xl">Regional Mesh & SAR Watchfloor</h2>
              <p className="mt-3 max-w-2xl text-sm leading-relaxed text-white/80">
                Monitor gateway-uploaded mesh topology, active survivor detections, responder presence, and geotagged disaster reports in one map-oriented command surface.
              </p>
              <div className="mt-5 flex flex-wrap gap-2">
                {meshLegend.map((item) => (
                  <span key={item.label} className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/10 px-3 py-2 text-xs font-medium backdrop-blur-sm">
                    <span className={item.swatchClassName} />
                    {item.label}
                  </span>
                ))}
              </div>
            </div>

            <div className="grid gap-3 sm:grid-cols-3 xl:min-w-[520px]">
              <div className="rounded-2xl border border-white/10 bg-white/10 p-4 backdrop-blur-sm">
                <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Live nodes</p>
                <p className="mt-2 font-headline text-4xl">{String(topologyNodes.length).padStart(2, "0")}</p>
                <p className="mt-1 text-xs text-white/70">{staleNodeCount} flagged as stale</p>
              </div>
              <div className="rounded-2xl border border-white/10 bg-white/10 p-4 backdrop-blur-sm">
                <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Active survivor signals</p>
                <p className="mt-2 font-headline text-4xl">{String(activeSignalCount).padStart(2, "0")}</p>
                <p className="mt-1 text-xs text-white/70">{visibleSignals.length} markers currently visible</p>
              </div>
              <div className="rounded-2xl border border-white/10 bg-white/10 p-4 backdrop-blur-sm">
                <p className="text-[11px] font-bold uppercase tracking-widest text-white/70">Tracked location trails</p>
                <p className="mt-2 font-headline text-4xl">{String(deviceTrails.length).padStart(2, "0")}</p>
                <p className="mt-1 text-xs text-white/70">Last-seen breadcrumbs from mesh beacons</p>
              </div>
            </div>
          </div>
        </section>

        <Card className={warmPanelClassName}>
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">Map controls</p>
              <h3 className="mt-2 text-2xl text-on-surface">Layer command bar</h3>
              <p className="mt-2 max-w-2xl text-sm leading-relaxed text-on-surface-variant">
                Mesh topology reflects the latest gateway-uploaded peer snapshot rather than live BLE discovery. Device trails stay visible for the current 72-hour retention window and emphasize the most recent endpoint.
              </p>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                className={`rounded-full px-4 py-2 text-xs font-bold uppercase tracking-widest ${meshLayerEnabled ? "border border-[#a14b2f] bg-[#a14b2f] text-white" : warmActionTabClassName}`}
                onClick={() => setMeshLayerEnabled((value) => !value)}
              >
                Mesh & SAR {meshLayerEnabled ? "On" : "Off"}
              </button>
              <button
                type="button"
                className={`rounded-full px-4 py-2 text-xs font-bold uppercase tracking-widest ${showResolved ? "border border-[#6a7077] bg-[#6a7077] text-white" : warmActionTabClassName}`}
                onClick={() => setShowResolved((value) => !value)}
              >
                {showResolved ? "Hide old resolved" : "Show old resolved"}
              </button>
              <span className={`rounded-full px-3 py-2 text-xs font-medium ${warmTabClassName}`}>
                {topologyNodes.length} nodes
              </span>
              <span className={`rounded-full px-3 py-2 text-xs font-medium ${warmTabClassName}`}>
                {activeSignalCount} active signals
              </span>
              <span className={`rounded-full px-3 py-2 text-xs font-medium ${warmTabClassName}`}>
                {deviceTrails.length} trails
              </span>
              <Button type="button" variant="ghost" onClick={() => void refreshDashboard(false)}>
                <span className="material-symbols-outlined mr-1 text-[16px]">refresh</span>
                {refreshing ? "Refreshing" : "Refresh"}
              </Button>
            </div>
          </div>
        </Card>

        {error ? (
          <Card className="border border-[#e7b7aa] bg-[#fff3ef] text-[#89391e]">
            <p className="text-sm font-semibold">Mesh dashboard issue</p>
            <p className="mt-2 text-sm">{error}</p>
          </Card>
        ) : null}

        {loading ? (
          <Card className={`${warmPanelClassName} py-16 text-center text-on-surface-variant`}>
            <span className="material-symbols-outlined mb-4 block animate-pulse text-4xl">hourglass_empty</span>
            Loading mesh dashboard...
          </Card>
        ) : (
          <div className="grid gap-6 xl:grid-cols-12">
            <div className="space-y-6 xl:col-span-8">
              <MeshSarMap
                meshLayerEnabled={meshLayerEnabled}
                reports={reports}
                topologyNodes={topologyNodes}
                responderNodes={responderNodes}
                survivorSignals={meshLayerEnabled ? visibleSignals : []}
                deviceTrails={meshLayerEnabled ? deviceTrails : []}
                selectedTrailDeviceFingerprint={selectedTrail?.device_fingerprint ?? null}
                resolvingSignalId={resolvingSignalId}
                onResolveSignal={handleResolveSignal}
                onSelectTrailDevice={setSelectedTrailDeviceFingerprint}
              />
            </div>

            <div className="space-y-6 xl:col-span-4">
              <Card className={warmPanelClassName}>
                <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Trail focus</p>
                <div className="mt-5 space-y-4">
                  {selectedTrail == null ? (
                    <p className="text-sm text-on-surface-variant">No location beacons have been synced yet.</p>
                  ) : (
                    <>
                      <div className="rounded-[24px] border border-[#d8b7aa] bg-[#fff0ea] p-5 shadow-[0_12px_28px_rgba(161,75,47,0.08)]">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">Selected device</p>
                            <h3 className="mt-2 text-xl font-semibold text-on-surface">
                              {selectedTrail.display_name || selectedTrail.device_fingerprint}
                            </h3>
                          </div>
                          <span className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${warmTabClassName}`}>
                            {titleCase(selectedTrail.app_state)}
                          </span>
                        </div>
                        <div className="mt-4 grid gap-2 text-[12px] text-[#6f625b]">
                          <span>Last seen: {formatDateTime(selectedTrail.recorded_at)}</span>
                          <span>Location: {formatCoordinates(selectedTrail.lat, selectedTrail.lng)}</span>
                          <span>Battery: {selectedTrail.battery_pct == null ? "-" : `${selectedTrail.battery_pct}%`}</span>
                          <span>Trail points: {selectedTrail.points.length}</span>
                        </div>
                      </div>

                      <div className="rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                        <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">Quick select</p>
                        <div className="mt-3 flex flex-wrap gap-2">
                          {deviceTrails.slice(0, 8).map((trail) => (
                            <button
                              key={trail.device_fingerprint}
                              type="button"
                              className={`rounded-full px-3 py-2 text-xs font-semibold ${trail.device_fingerprint === selectedTrail.device_fingerprint ? "border border-[#a14b2f] bg-[#a14b2f] text-white" : "border border-[#d8b7aa] bg-white text-[#6f625b]"}`}
                              onClick={() => setSelectedTrailDeviceFingerprint(trail.device_fingerprint)}
                            >
                              {trail.display_name || trail.device_fingerprint.slice(0, 10)}
                            </button>
                          ))}
                        </div>
                      </div>

                      <div className="space-y-3">
                        <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">Last 10 points</p>
                        {recentTrailPoints.map((point, index) => (
                          <div key={`${point.message_id ?? point.recorded_at}-${index}`} className="rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                            <div className="flex items-start justify-between gap-3">
                              <div>
                                <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                                  Trail point {String(recentTrailPoints.length - index).padStart(2, "0")}
                                </p>
                                <p className="mt-2 text-sm font-semibold text-on-surface">
                                  {formatCoordinates(point.lat, point.lng)}
                                </p>
                              </div>
                              <span className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${warmTabClassName}`}>
                                {titleCase(point.app_state)}
                              </span>
                            </div>
                            <div className="mt-3 grid gap-1 text-[12px] text-[#6f625b]">
                              <span>{formatDateTime(point.recorded_at)}</span>
                              <span>Accuracy: {point.accuracy_meters == null ? "-" : `${point.accuracy_meters.toFixed(0)} m`}</span>
                              <span>Battery: {point.battery_pct == null ? "-" : `${point.battery_pct}%`}</span>
                            </div>
                          </div>
                        ))}
                      </div>
                    </>
                  )}
                </div>
              </Card>

              <Card className={warmPanelClassName}>
                <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Survivor queue</p>
                <div className="mt-5 space-y-4">
                  {visibleSignals.length === 0 ? (
                    <p className="text-sm text-on-surface-variant">No survivor signals are visible under the current filters.</p>
                  ) : (
                    visibleSignals.slice(0, 5).map((signal) => (
                      <div key={signal.id} className="rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                              {titleCase(signal.detection_method)}
                            </p>
                            <p className="mt-2 text-base font-semibold text-on-surface">
                              {Math.round(signal.confidence * 100)}% confidence
                            </p>
                          </div>
                          <span className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${signal.resolved ? "border border-[#d3d4d7] bg-[#eef0f3] text-[#666b73]" : "border border-[#f1b3a4] bg-[#fff0ec] text-[#a14b2f]"}`}>
                            {signal.resolved ? "Resolved" : "Active"}
                          </span>
                        </div>
                        <div className="mt-3 grid gap-1 text-[12px] text-[#6f625b]">
                          <span>Distance: {signal.estimated_distance_meters.toFixed(1)} m</span>
                          <span>Last seen: {formatDateTime(signal.last_seen_timestamp)}</span>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </Card>

              <Card className={warmPanelClassName}>
                <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Node roster</p>
                <div className="mt-5 space-y-4">
                  {topologyNodes.length === 0 ? (
                    <p className="text-sm text-on-surface-variant">No topology snapshot has been uploaded yet.</p>
                  ) : (
                    topologyNodes.slice(0, 6).map((node) => (
                      <div key={node.node_device_id} className="rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                              {titleCase(node.node_role)} node
                            </p>
                            <p className="mt-2 text-base font-semibold text-on-surface">
                              {node.display_name || node.department_name || node.node_device_id}
                            </p>
                          </div>
                          <span className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${node.is_stale ? "border border-[#d5c6bf] bg-[#f2ebe6] text-[#7d6e67]" : "border border-[#d8b7aa] bg-[#fff0ea] text-[#a14b2f]"}`}>
                            {node.is_stale ? "Stale" : "Fresh"}
                          </span>
                        </div>
                        <div className="mt-3 grid gap-1 text-[12px] text-[#6f625b]">
                          <span>Peers: {node.peer_count}</span>
                          <span>Queue depth: {node.queue_depth}</span>
                          <span>Last seen: {formatDateTime(node.last_seen_at)}</span>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </Card>

              <Card className={warmPanelClassName}>
                <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Mesh comms</p>
                <div className="mt-5 space-y-4">
                  {recentMessages.length === 0 && recentMeshPosts.length === 0 ? (
                    <p className="text-sm text-on-surface-variant">
                      Mesh-routed conversations and posts will appear here after a gateway sync.
                    </p>
                  ) : (
                    <>
                      {recentMessages.map((message) => (
                        <div key={message.id} className="rounded-2xl border border-[#ecd8cf] bg-[#f7efe7] p-4">
                          <div className="flex items-start justify-between gap-3">
                            <div>
                              <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                                {message.recipient_scope} mesh message
                              </p>
                              <p className="mt-2 text-base font-semibold text-on-surface">
                                {message.author_display_name}
                              </p>
                            </div>
                            <span className={`rounded-full px-3 py-1 text-[10px] font-bold uppercase tracking-widest ${warmTabClassName}`}>
                              {message.author_role}
                            </span>
                          </div>
                          <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">{message.body}</p>
                          <p className="mt-3 text-[12px] text-[#6f625b]">{formatDateTime(message.created_at)}</p>
                        </div>
                      ))}
                      {recentMeshPosts.map((post) => (
                        <div key={post.id} className="rounded-2xl border border-[#d8b7aa] bg-[#fff0ea] p-4">
                          <div className="flex items-start justify-between gap-3">
                            <div>
                              <p className="text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                                Mesh post
                              </p>
                              <p className="mt-2 text-base font-semibold text-on-surface">{post.title}</p>
                            </div>
                            <span className="rounded-full border border-[#f1b3a4] bg-white px-3 py-1 text-[10px] font-bold uppercase tracking-widest text-[#a14b2f]">
                              {titleCase(post.category ?? "update")}
                            </span>
                          </div>
                          <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">{post.content ?? "No post copy available."}</p>
                          <p className="mt-3 text-[12px] text-[#6f625b]">{formatDateTime(post.created_at)}</p>
                        </div>
                      ))}
                    </>
                  )}
                </div>
              </Card>

              <Card className={warmPanelClassName}>
                <p className="text-[11px] font-bold uppercase tracking-widest text-on-surface-variant">Report overlay</p>
                <h3 className="mt-3 text-2xl text-on-surface">{reports.length} mapped reports</h3>
                <p className="mt-3 text-sm leading-relaxed text-on-surface-variant">
                  Disaster reports remain visible even when the Mesh & SAR layer is off, so operators can compare survivor activity against the broader incident footprint.
                </p>
              </Card>
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

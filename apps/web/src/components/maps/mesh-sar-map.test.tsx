import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import {
  MeshSarMap,
  type DisasterReportMarker,
  type MeshDeviceTrail,
  type MeshSurvivorSignal,
  type MeshTopologyNode,
} from "./mesh-sar-map";

const mapApi = vi.hoisted(() => ({
  fitBounds: vi.fn(),
  setView: vi.fn(),
}));

vi.mock("leaflet", () => ({
  divIcon: (options: unknown) => options,
  latLngBounds: (points: unknown) => points,
}));

vi.mock("react-leaflet", () => ({
  MapContainer: ({ children }: { children: React.ReactNode }) => <div data-testid="map">{children}</div>,
  TileLayer: () => <div data-testid="tile-layer" />,
  Marker: ({ children, title }: { children?: React.ReactNode; title?: string }) => (
    <div data-testid="marker" data-title={title ?? ""}>
      {children}
    </div>
  ),
  Popup: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Circle: () => <div data-testid="circle" />,
  Polyline: () => <div data-testid="polyline" />,
  useMap: () => mapApi,
}));

describe("MeshSarMap", () => {
  const reports: DisasterReportMarker[] = [
    {
      id: "report-1",
      category: "fire",
      status: "pending",
      severity: "high",
      description: "Warehouse blaze",
      address: "Pier 4",
      latitude: 14.61,
      longitude: 120.99,
      created_at: "2026-03-31T02:10:00Z",
    },
  ];

  const topologyNodes: MeshTopologyNode[] = [
    {
      node_device_id: "node-1",
      node_role: "gateway",
      peer_count: 4,
      queue_depth: 1,
      display_name: "Gateway Alpha",
      last_seen_at: "2026-03-31T02:20:00Z",
      last_sync_at: "2026-03-31T02:21:00Z",
      lat: 14.62,
      lng: 121.0,
      is_stale: false,
    },
  ];

  const responderNodes: MeshTopologyNode[] = [
    {
      node_device_id: "resp-1",
      node_role: "relay",
      peer_count: 2,
      queue_depth: 0,
      department_name: "Fire Station 2",
      last_seen_at: "2026-03-31T02:20:00Z",
      last_sync_at: "2026-03-31T02:21:00Z",
      lat: 14.625,
      lng: 121.005,
      is_stale: false,
      is_responder: true,
    },
  ];

  const survivorSignals: MeshSurvivorSignal[] = [
    {
      id: "signal-1",
      detection_method: "BLE_PASSIVE",
      confidence: 0.88,
      estimated_distance_meters: 4.2,
      signal_strength_dbm: -68,
      acoustic_pattern_matched: "none",
      resolved: false,
      last_seen_timestamp: "2026-03-31T02:18:00Z",
      lat: 14.63,
      lng: 121.01,
    },
  ];

  const deviceTrails: MeshDeviceTrail[] = [
    {
      device_fingerprint: "device-1",
      display_name: "Responder One",
      battery_pct: 54,
      app_state: "foreground",
      recorded_at: "2026-03-31T02:19:00Z",
      lat: 14.628,
      lng: 121.006,
      points: [
        {
          device_fingerprint: "device-1",
          display_name: "Responder One",
          battery_pct: 56,
          app_state: "background",
          recorded_at: "2026-03-31T02:14:00Z",
          lat: 14.626,
          lng: 121.004,
        },
        {
          device_fingerprint: "device-1",
          display_name: "Responder One",
          battery_pct: 54,
          app_state: "foreground",
          recorded_at: "2026-03-31T02:19:00Z",
          lat: 14.628,
          lng: 121.006,
        },
      ],
    },
  ];

  it("respects the mesh layer toggle and renders overlay markers when enabled", () => {
    const { rerender } = render(
      <MeshSarMap
        meshLayerEnabled={false}
        reports={reports}
        topologyNodes={topologyNodes}
        responderNodes={responderNodes}
        survivorSignals={survivorSignals}
        deviceTrails={deviceTrails}
      />,
    );

    const initialMarkers = screen.getAllByTestId("marker");
    expect(initialMarkers).toHaveLength(1);
    expect(initialMarkers[0]).toHaveAttribute("data-title", "report:report-1");

    rerender(
      <MeshSarMap
        meshLayerEnabled
        reports={reports}
        topologyNodes={topologyNodes}
        responderNodes={responderNodes}
        survivorSignals={survivorSignals}
        deviceTrails={deviceTrails}
      />,
    );

    const enabledMarkers = screen.getAllByTestId("marker").map((marker) => marker.getAttribute("data-title"));
    expect(enabledMarkers).toEqual(
      expect.arrayContaining([
        "report:report-1",
        "mesh-node:node-1",
        "responder:resp-1",
        "survivor:signal-1",
        "trail:device-1",
      ]),
    );
    expect(screen.getAllByTestId("polyline").length).toBeGreaterThan(0);
  });

  it("renders survivor popup details and resolves active signals", () => {
    const handleResolve = vi.fn();

    render(
      <MeshSarMap
        meshLayerEnabled
        reports={reports}
        topologyNodes={topologyNodes}
        responderNodes={responderNodes}
        survivorSignals={survivorSignals}
        deviceTrails={deviceTrails}
        onResolveSignal={handleResolve}
      />,
    );

    expect(screen.getByText("Survivor Signal")).toBeInTheDocument();
    expect(screen.getByText("BLE PASSIVE")).toBeInTheDocument();
    expect(screen.getByText("Estimated distance: 4.2 m")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Resolve Signal" }));
    expect(handleResolve).toHaveBeenCalledWith("signal-1");
  });

  it("opens the trail detail action from the last-seen popup", () => {
    const handleSelectTrail = vi.fn();

    render(
      <MeshSarMap
        meshLayerEnabled
        reports={reports}
        topologyNodes={topologyNodes}
        responderNodes={responderNodes}
        survivorSignals={survivorSignals}
        deviceTrails={deviceTrails}
        onSelectTrailDevice={handleSelectTrail}
      />,
    );

    expect(screen.getByText("Last Seen Device")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Open Trail" }));
    expect(handleSelectTrail).toHaveBeenCalledWith("device-1");
  });
});

import { useEffect } from "react";
import { Circle, MapContainer, Marker, Popup, TileLayer, useMap } from "react-leaflet";
import { divIcon, latLngBounds } from "leaflet";

import { Button } from "@/components/ui/button";

export type MeshTopologyNode = {
  id?: string;
  node_device_id: string;
  node_role: "gateway" | "relay" | "origin";
  peer_count: number;
  queue_depth: number;
  display_name?: string;
  department_name?: string;
  department_id?: string | null;
  operator_role?: string | null;
  is_responder?: boolean;
  last_seen_at: string;
  last_sync_at?: string;
  is_stale?: boolean;
  lat: number;
  lng: number;
};

export type MeshSurvivorSignal = {
  id: string;
  detection_method: string;
  confidence: number;
  estimated_distance_meters: number;
  signal_strength_dbm?: number;
  acoustic_pattern_matched?: string;
  resolved: boolean;
  resolved_at?: string | null;
  resolution_note?: string;
  last_seen_timestamp?: string;
  marker_state?: string;
  lat: number;
  lng: number;
};

export type DisasterReportMarker = {
  id: string;
  category: string;
  status: string;
  severity: string;
  description: string;
  address?: string | null;
  latitude: number;
  longitude: number;
  created_at: string;
};

type MeshSarMapProps = {
  meshLayerEnabled: boolean;
  reports: DisasterReportMarker[];
  topologyNodes: MeshTopologyNode[];
  responderNodes: MeshTopologyNode[];
  survivorSignals: MeshSurvivorSignal[];
  resolvingSignalId?: string | null;
  onResolveSignal?: (signalId: string) => void;
};

const DEFAULT_CENTER: [number, number] = [14.5995, 120.9842];

// Re-fit the map whenever the visible overlays change so operators land on the incident area.
function MapViewportController({ points }: { points: Array<[number, number]> }) {
  const map = useMap();

  useEffect(() => {
    if (points.length === 0) {
      map.setView(DEFAULT_CENTER, 11);
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

function nodeIcon(role: MeshTopologyNode["node_role"], isStale = false) {
  return divIcon({
    className: "mesh-sar-icon-shell",
    iconSize: [28, 28],
    iconAnchor: [14, 14],
    popupAnchor: [0, -16],
    html: `
      <span class="mesh-sar-node-marker mesh-sar-node-marker--${role}${isStale ? " mesh-sar-node-marker--stale" : ""}">
        <span class="mesh-sar-node-marker__triangle"></span>
      </span>
    `,
  });
}

function responderIcon() {
  return divIcon({
    className: "mesh-sar-icon-shell",
    iconSize: [24, 24],
    iconAnchor: [12, 12],
    popupAnchor: [0, -16],
    html: `
      <span class="mesh-sar-responder-marker">
        <span class="mesh-sar-responder-marker__dot"></span>
      </span>
    `,
  });
}

function survivorIcon(resolved: boolean) {
  return divIcon({
    className: "mesh-sar-icon-shell",
    iconSize: [24, 24],
    iconAnchor: [12, 12],
    popupAnchor: [0, -16],
    html: `
      <span class="mesh-sar-survivor-marker${resolved ? " mesh-sar-survivor-marker--resolved" : ""}">
        <span class="mesh-sar-survivor-marker__core"></span>
      </span>
    `,
  });
}

function reportIcon(category: string) {
  return divIcon({
    className: "mesh-sar-icon-shell",
    iconSize: [22, 22],
    iconAnchor: [11, 11],
    popupAnchor: [0, -16],
    html: `
      <span class="mesh-sar-report-marker mesh-sar-report-marker--${category.replace(/_/g, "-")}">
        <span class="mesh-sar-report-marker__core"></span>
      </span>
    `,
  });
}

function formatDateTime(value?: string | null) {
  if (!value) {
    return "-";
  }
  return new Date(value).toLocaleString();
}

function titleCase(value: string) {
  return value.replace(/_/g, " ");
}

export function MeshSarMap({
  meshLayerEnabled,
  reports,
  topologyNodes,
  responderNodes,
  survivorSignals,
  resolvingSignalId,
  onResolveSignal,
}: MeshSarMapProps) {
  const visiblePoints: Array<[number, number]> = reports.map((report) => [report.latitude, report.longitude]);

  if (meshLayerEnabled) {
    visiblePoints.push(...topologyNodes.map((node) => [node.lat, node.lng] as [number, number]));
    visiblePoints.push(...survivorSignals.map((signal) => [signal.lat, signal.lng] as [number, number]));
  }

  return (
    <div className="overflow-hidden rounded-[28px] border border-[#d8b7aa] bg-[#fff8f3] shadow-[0_18px_40px_rgba(56,56,49,0.08)]">
      <MapContainer center={DEFAULT_CENTER} className="mesh-sar-map h-[520px] w-full" scrollWheelZoom zoom={12}>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <MapViewportController points={visiblePoints} />

        {reports.map((report) => (
          <Marker
            key={`report-${report.id}`}
            icon={reportIcon(report.category)}
            position={[report.latitude, report.longitude]}
            title={`report:${report.id}`}
          >
            <Popup>
              <div className="space-y-2 text-sm text-[#4e4742]">
                <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                  Disaster Report
                </p>
                <p className="font-semibold text-[#373831]">{titleCase(report.category)}</p>
                <p>{report.description}</p>
                <div className="flex flex-wrap gap-2 text-[11px] font-medium text-[#6f625b]">
                  <span>Status: {titleCase(report.status)}</span>
                  <span>Severity: {titleCase(report.severity)}</span>
                </div>
                {report.address ? <p className="text-xs text-[#6f625b]">{report.address}</p> : null}
                <p className="text-[11px] text-[#8a5a40]">Reported {formatDateTime(report.created_at)}</p>
              </div>
            </Popup>
          </Marker>
        ))}

        {meshLayerEnabled &&
          topologyNodes.map((node) => (
            <Marker
              key={`node-${node.node_device_id}`}
              icon={nodeIcon(node.node_role, node.is_stale)}
              position={[node.lat, node.lng]}
              title={`mesh-node:${node.node_device_id}`}
            >
              <Popup>
                <div className="space-y-2 text-sm text-[#4e4742]">
                  <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                    Mesh Node
                  </p>
                  <p className="font-semibold text-[#373831]">
                    {node.display_name || node.department_name || node.node_device_id}
                  </p>
                  <div className="grid gap-1 text-[12px] text-[#6f625b]">
                    <span>Role: {titleCase(node.node_role)}</span>
                    <span>Peers: {node.peer_count}</span>
                    <span>Queue depth: {node.queue_depth}</span>
                    <span>Last seen: {formatDateTime(node.last_seen_at)}</span>
                    <span>Last sync: {formatDateTime(node.last_sync_at)}</span>
                  </div>
                </div>
              </Popup>
            </Marker>
          ))}

        {meshLayerEnabled &&
          responderNodes.map((node) => (
            <Marker
              key={`responder-${node.node_device_id}`}
              icon={responderIcon()}
              position={[node.lat, node.lng]}
              title={`responder:${node.node_device_id}`}
            >
              <Popup>
                <div className="space-y-2 text-sm text-[#4e4742]">
                  <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                    Responder
                  </p>
                  <p className="font-semibold text-[#373831]">
                    {node.department_name || node.display_name || node.node_device_id}
                  </p>
                  <div className="grid gap-1 text-[12px] text-[#6f625b]">
                    <span>Department device active on mesh</span>
                    <span>Role: {titleCase(node.node_role)}</span>
                    <span>Last seen: {formatDateTime(node.last_seen_at)}</span>
                  </div>
                </div>
              </Popup>
            </Marker>
          ))}

        {meshLayerEnabled &&
          survivorSignals.map((signal) => (
            <Marker
              key={`signal-${signal.id}`}
              icon={survivorIcon(signal.resolved)}
              position={[signal.lat, signal.lng]}
              title={`survivor:${signal.id}`}
            >
              <Popup>
                <div className="space-y-3 text-sm text-[#4e4742]">
                  <div>
                    <p className="text-[11px] font-bold uppercase tracking-widest text-[#a14b2f]">
                      Survivor Signal
                    </p>
                    <p className="mt-1 font-semibold text-[#373831]">
                      {titleCase(signal.detection_method)}
                    </p>
                  </div>
                  <div className="grid gap-1 text-[12px] text-[#6f625b]">
                    <span>Confidence: {Math.round(signal.confidence * 100)}%</span>
                    <span>Estimated distance: {signal.estimated_distance_meters.toFixed(1)} m</span>
                    <span>Signal strength: {signal.signal_strength_dbm ?? "-"} dBm</span>
                    <span>Last seen: {formatDateTime(signal.last_seen_timestamp)}</span>
                  </div>
                  {signal.acoustic_pattern_matched && signal.acoustic_pattern_matched !== "none" ? (
                    <p className="text-[12px] text-[#8a5a40]">
                      Acoustic match: {titleCase(signal.acoustic_pattern_matched)}
                    </p>
                  ) : null}
                  {signal.resolved ? (
                    <p className="rounded-2xl border border-[#d3d4d7] bg-[#f1f2f4] px-3 py-2 text-[12px] text-[#666b73]">
                      Resolved {signal.resolved_at ? formatDateTime(signal.resolved_at) : "recently"}
                    </p>
                  ) : (
                    <Button
                      type="button"
                      variant="secondary"
                      className="w-full justify-center"
                      disabled={resolvingSignalId === signal.id}
                      onClick={() => onResolveSignal?.(signal.id)}
                    >
                      {resolvingSignalId === signal.id ? "Resolving..." : "Resolve Signal"}
                    </Button>
                  )}
                </div>
              </Popup>
            </Marker>
          ))}

        {meshLayerEnabled &&
          survivorSignals.map((signal) => (
            <Circle
              key={`ring-${signal.id}`}
              center={[signal.lat, signal.lng]}
              radius={Math.max(signal.estimated_distance_meters, 1)}
              className={signal.resolved ? "mesh-sar-radius-ring mesh-sar-radius-ring--resolved" : "mesh-sar-radius-ring"}
              pathOptions={{
                color: signal.resolved ? "#8b9098" : "#c65439",
                fillColor: signal.resolved ? "#cdd1d8" : "#f6b0a1",
                fillOpacity: signal.resolved ? 0.08 : 0.12,
                weight: 2,
              }}
            />
          ))}
      </MapContainer>
    </div>
  );
}

import { MapContainer, Marker, TileLayer } from "react-leaflet";

import { cn } from "@/lib/utils";

/**
 * Phase 1 — Location map component.
 * Aegis-styled Leaflet wrapper with muted tile layer.
 */

type LocationMapProps = {
  latitude?: number;
  longitude?: number;
  centerLatitude?: number;
  centerLongitude?: number;
  wrapperClassName?: string;
  mapClassName?: string;
};

export function LocationMap({
  latitude = 14.5995,
  longitude = 120.9842,
  centerLatitude,
  centerLongitude,
  wrapperClassName,
  mapClassName,
}: LocationMapProps) {
  return (
    <div
      className={cn(
        "overflow-hidden rounded-xl border border-outline-variant/10",
        wrapperClassName,
      )}
    >
      <MapContainer
        center={[centerLatitude ?? latitude, centerLongitude ?? longitude]}
        className={cn("h-64 w-full", mapClassName)}
        scrollWheelZoom={false}
        zoom={13}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <Marker position={[latitude, longitude]} />
      </MapContainer>
    </div>
  );
}

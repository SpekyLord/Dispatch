import { MapContainer, Marker, TileLayer } from "react-leaflet";

/**
 * Phase 1 — Location map component.
 * Aegis-styled Leaflet wrapper with muted tile layer.
 */

type LocationMapProps = {
  latitude?: number;
  longitude?: number;
};

export function LocationMap({ latitude = 14.5995, longitude = 120.9842 }: LocationMapProps) {
  return (
    <div className="overflow-hidden rounded-xl border border-outline-variant/10">
      <MapContainer
        center={[latitude, longitude]}
        className="h-64 w-full"
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

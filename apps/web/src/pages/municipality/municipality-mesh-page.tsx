// Municipality mesh overview â€” distress signals, mesh sync status, recent mesh-origin packets.

import { useEffect, useState } from "react";

import { AppShell } from "@/components/layout/app-shell";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { apiRequest } from "@/lib/api/client";
import { useSessionStore } from "@/lib/auth/session-store";
import { subscribeToTable } from "@/lib/realtime/supabase";

type DistressSignal = {
  id: string;
  message_id: string;
  origin_device_id: string;
  latitude?: number;
  longitude?: number;
  description: string;
  reporter_name: string;
  contact_info: string;
  hop_count: number;
  is_resolved: boolean;
  created_at: string;
};

type SyncUpdate = {
  report_updates: { id: string; status: string; updated_at: string }[];
  distress_signals: DistressSignal[];
  status_history: unknown[];
  synced_at: string;
};

export function MunicipalityMeshPage() {
  const accessToken = useSessionStore((s) => s.accessToken);
  const [distress, setDistress] = useState<DistressSignal[]>([]);
  const [lastSync, setLastSync] = useState<string | null>(null);
  const [recentCount, setRecentCount] = useState(0);
  const [loading, setLoading] = useState(true);

  function fetchData() {
    setLoading(true);
    apiRequest<SyncUpdate>("/api/mesh/sync-updates")
      .then((res) => {
        setDistress(res.distress_signals);
        setLastSync(res.synced_at);
        setRecentCount(res.report_updates.length);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }

  useEffect(() => {
    queueMicrotask(() => {
      fetchData();
    });
  }, []);

  // live updates on distress signals
  useEffect(() => {
    const sub = subscribeToTable("distress_signals", () => fetchData(), { accessToken });
    return () => sub.unsubscribe();
  }, [accessToken]);

  const unresolvedCount = distress.filter((d) => !d.is_resolved).length;

  return (
    <AppShell subtitle="Offline mesh network status" title="Mesh Status">
      {/* Summary cards */}
      <div className="grid gap-4 sm:grid-cols-3 mb-8">
        <Card className="text-center">
          <span className="material-symbols-outlined text-3xl text-cyan-600 mb-2 block">cell_tower</span>
          <p className="text-3xl font-headline font-bold text-on-surface">{recentCount}</p>
          <p className="text-xs text-on-surface-variant uppercase tracking-widest mt-1">Recent Updates</p>
        </Card>
        <Card className="text-center">
          <span className="material-symbols-outlined text-3xl text-red-600 mb-2 block">sos</span>
          <p className="text-3xl font-headline font-bold text-on-surface">{unresolvedCount}</p>
          <p className="text-xs text-on-surface-variant uppercase tracking-widest mt-1">Active Distress</p>
        </Card>
        <Card className="text-center">
          <span className="material-symbols-outlined text-3xl text-green-600 mb-2 block">sync</span>
          <p className="text-sm font-medium text-on-surface mt-2">
            {lastSync ? new Date(lastSync).toLocaleString() : "-"}
          </p>
          <p className="text-xs text-on-surface-variant uppercase tracking-widest mt-1">Last Sync</p>
        </Card>
      </div>

      {/* Distress signals */}
      <div className="flex items-center justify-between mb-4">
        <h2 className="font-headline text-2xl text-on-surface">Distress Signals</h2>
        <Button variant="ghost" onClick={fetchData}>
          <span className="material-symbols-outlined text-[16px] mr-1">refresh</span>
          Refresh
        </Button>
      </div>

      {loading ? (
        <Card className="py-16 text-center text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl animate-pulse">hourglass_empty</span>
        </Card>
      ) : distress.length === 0 ? (
        <Card className="py-16 text-center">
          <span className="material-symbols-outlined text-5xl text-outline-variant mb-4 block">check_circle</span>
          <p className="text-on-surface-variant">No distress signals received.</p>
        </Card>
      ) : (
        <div className="space-y-4">
          {distress.map((d) => (
            <Card
              key={d.id}
              className={`transition-all ${!d.is_resolved ? "border-l-4 border-l-red-500" : ""}`}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${
                    d.is_resolved ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"
                  }`}>
                    <span className="material-symbols-outlined">
                      {d.is_resolved ? "check_circle" : "sos"}
                    </span>
                  </div>
                  <div>
                    <h3 className="text-sm font-semibold text-on-surface">
                      {d.reporter_name || `Device ${d.origin_device_id.slice(0, 8)}...`}
                    </h3>
                    <p className="text-xs text-on-surface-variant">
                      {d.contact_info || "No contact info"}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <span className="rounded-md bg-cyan-100 px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest text-cyan-800">
                    {d.hop_count} hop{d.hop_count !== 1 ? "s" : ""}
                  </span>
                  <span className={`rounded-md px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest ${
                    d.is_resolved
                      ? "bg-green-100 text-green-800"
                      : "bg-red-100 text-red-800"
                  }`}>
                    {d.is_resolved ? "Resolved" : "Active"}
                  </span>
                </div>
              </div>

              {d.description && (
                <p className="mt-3 text-sm text-on-surface">{d.description}</p>
              )}

              <div className="mt-3 flex flex-wrap items-center gap-3 text-xs text-on-surface-variant">
                {d.latitude && d.longitude && (
                  <span className="flex items-center gap-1">
                    <span className="material-symbols-outlined text-[14px]">location_on</span>
                    {d.latitude.toFixed(4)}, {d.longitude.toFixed(4)}
                  </span>
                )}
                <span className="ml-auto text-[10px]">
                  {new Date(d.created_at).toLocaleString()}
                </span>
              </div>
            </Card>
          ))}
        </div>
      )}
    </AppShell>
  );
}

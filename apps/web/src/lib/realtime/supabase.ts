import { createClient, type RealtimeChannel, type SupabaseClient } from "@supabase/supabase-js";

let realtimeClient: SupabaseClient | null = null;

export function getRealtimeClient() {
  const url = import.meta.env.VITE_SUPABASE_URL;
  const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    return null;
  }

  if (!realtimeClient) {
    realtimeClient = createClient(url, anonKey, {
      auth: {
        persistSession: false,
      },
    });
  }

  return realtimeClient;
}

export function subscribeToTable(
  table: "incident_reports" | "department_responses" | "report_status_history" | "notifications" | "posts",
  onChange: (payload: unknown) => void,
) {
  const client = getRealtimeClient();
  if (!client) {
    return {
      unsubscribe: () => undefined,
    };
  }

  const channel = client
    .channel(`phase0:${table}`)
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table },
      (payload) => {
        onChange(payload);
      },
    )
    .subscribe();

  return {
    unsubscribe: () => {
      void client.removeChannel(channel as RealtimeChannel);
    },
  };
}

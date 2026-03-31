import { createClient, type RealtimeChannel, type SupabaseClient } from "@supabase/supabase-js";

let realtimeClient: SupabaseClient | null = null;

export type RealtimeTable =
  | "incident_reports"
  | "department_responses"
  | "report_status_history"
  | "notifications"
  | "department_feed_posts"
  | "department_feed_comment"
  | "distress_signals";

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

function setRealtimeAuth(client: SupabaseClient, accessToken?: string | null) {
  const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
  const token = accessToken ?? anonKey;
  if (token) {
    client.realtime.setAuth(token);
  }
}

export function subscribeToTable(
  table: RealtimeTable,
  onChange: (payload: unknown) => void,
  options?: {
    accessToken?: string | null;
    filter?: string;
  },
) {
  const client = getRealtimeClient();
  if (!client) {
    return {
      unsubscribe: () => undefined,
    };
  }

  setRealtimeAuth(client, options?.accessToken);

  const postgresConfig: {
    event: "*";
    schema: "public";
    table: RealtimeTable;
    filter?: string;
  } = {
    event: "*",
    schema: "public",
    table,
  };
  if (options?.filter) {
    postgresConfig.filter = options.filter;
  }

  const channel = client
    .channel(`phase2:${table}:${options?.filter ?? "all"}:${Math.random().toString(36).slice(2)}`)
    .on("postgres_changes", postgresConfig, (payload) => {
      onChange(payload);
    })
    .subscribe();

  return {
    unsubscribe: () => {
      void client.removeChannel(channel as RealtimeChannel);
    },
  };
}
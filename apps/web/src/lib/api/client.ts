// API client — auto-injects auth token, throws ApiError on non-2xx responses.
// apiRequest() for JSON, apiUpload() for multipart (no Content-Type so browser sets boundary).

import { useSessionStore } from "@/lib/auth/session-store";

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? "http://127.0.0.1:5000";

export class ApiError extends Error {
  readonly status: number;
  readonly details: unknown;

  constructor(message: string, status: number, details: unknown) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

type RefreshResponse = {
  access_token: string;
  refresh_token?: string | null;
  user: {
    id: string;
    email: string;
    role: "citizen" | "department" | "municipality";
    full_name?: string | null;
    phone?: string | null;
    avatar_url?: string | null;
  };
  department?: {
    id: string;
    user_id: string;
    name: string;
    type: string;
    verification_status: "pending" | "approved" | "rejected";
    description?: string | null;
    rejection_reason?: string | null;
    contact_number?: string | null;
    address?: string | null;
    area_of_responsibility?: string | null;
    profile_picture?: string | null;
    profile_photo?: string | null;
    header_photo?: string | null;
    post_count?: number | null;
    updated_at?: string | null;
  } | null;
};

let refreshPromise: Promise<string | null> | null = null;

async function refreshAccessToken(): Promise<string | null> {
  const session = useSessionStore.getState();
  if (!session.refreshToken) {
    session.signOut();
    return null;
  }

  if (!refreshPromise) {
    refreshPromise = fetch(`${API_BASE_URL}/api/auth/refresh`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ refresh_token: session.refreshToken }),
    })
      .then(async (response) => {
        if (!response.ok) {
          useSessionStore.getState().signOut();
          return null;
        }

        const payload = (await response.json()) as RefreshResponse;
        useSessionStore.getState().setSession({
          user: payload.user,
          accessToken: payload.access_token,
          refreshToken: payload.refresh_token ?? session.refreshToken,
          department: payload.department ?? null,
        });
        return payload.access_token;
      })
      .catch(() => {
        useSessionStore.getState().signOut();
        return null;
      })
      .finally(() => {
        refreshPromise = null;
      });
  }

  return refreshPromise;
}

async function requestWithAuthRetry(path: string, init?: RequestInit): Promise<Response> {
  const token = useSessionStore.getState().accessToken;
  const headers: Record<string, string> = {
    ...(init?.headers as Record<string, string> ?? {}),
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  let response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers,
  });

  if (response.status !== 401) {
    return response;
  }

  const nextToken = await refreshAccessToken();
  if (!nextToken) {
    return response;
  }

  const retryHeaders: Record<string, string> = {
    ...(init?.headers as Record<string, string> ?? {}),
    Authorization: `Bearer ${nextToken}`,
  };

  response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: retryHeaders,
  });

  return response;
}

// JSON request with auth token
export async function apiRequest<T>(path: string, init?: RequestInit): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(init?.headers as Record<string, string> ?? {}),
  };
  const response = await requestWithAuthRetry(path, {
    ...init,
    headers,
  });

  if (!response.ok) {
    const payload = await response.json().catch(() => null);
    throw new ApiError(
      payload?.error?.message ?? "Request failed.",
      response.status,
      payload?.error?.details ?? null,
    );
  }

  return response.json() as Promise<T>;
}

// File upload — omits Content-Type so browser can set multipart boundary
export async function apiUpload<T>(
  path: string,
  formData: FormData,
  init?: Omit<RequestInit, "body" | "headers">,
): Promise<T> {
  const response = await requestWithAuthRetry(path, {
    method: init?.method ?? "POST",
    ...init,
    body: formData,
  });

  if (!response.ok) {
    const payload = await response.json().catch(() => null);
    throw new ApiError(
      payload?.error?.message ?? "Upload failed.",
      response.status,
      payload?.error?.details ?? null,
    );
  }

  return response.json() as Promise<T>;
}

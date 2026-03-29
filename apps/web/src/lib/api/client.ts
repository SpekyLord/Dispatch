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

// JSON request with auth token
export async function apiRequest<T>(path: string, init?: RequestInit): Promise<T> {
  const token = useSessionStore.getState().accessToken;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(init?.headers as Record<string, string> ?? {}),
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const response = await fetch(`${API_BASE_URL}${path}`, {
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
  const token = useSessionStore.getState().accessToken;
  const headers: Record<string, string> = {};
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: init?.method ?? "POST",
    ...init,
    headers,
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

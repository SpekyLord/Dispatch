// Session store — Zustand global auth state persisted to localStorage.
// Zustand (not React Context) so we can read state outside components (e.g. API client).

import { create } from "zustand";

export type AppRole = "citizen" | "department" | "municipality";

export type SessionUser = {
  id: string;
  email: string;
  role: AppRole;
  full_name?: string | null;
  phone?: string | null;
  avatar_url?: string | null;
};

// Department info — verification_status drives UI (pending/rejected/approved views)
export type DepartmentInfo = {
  id: string;
  user_id: string;
  name: string;
  type: string;
  description?: string | null;
  verification_status: "pending" | "approved" | "rejected";
  rejection_reason?: string | null;
  contact_number?: string | null;
  address?: string | null;
  area_of_responsibility?: string | null;
  profile_picture?: string | null;
  profile_photo?: string | null;
  header_photo?: string | null;
  post_count?: number | null;
  updated_at?: string | null;
};

type SessionState = {
  user: SessionUser | null;
  accessToken: string | null;
  refreshToken: string | null;
  department: DepartmentInfo | null;
  setSession: (params: {
    user: SessionUser;
    accessToken: string;
    refreshToken?: string;
    department?: DepartmentInfo | null;
  }) => void;
  setDepartment: (dept: DepartmentInfo | null) => void;
  updateUser: (partial: Partial<SessionUser>) => void;
  signOut: () => void;
};

const STORAGE_KEY = "dispatch_session";

// Restore session from localStorage on app load
function loadPersistedSession(): Pick<
  SessionState,
  "user" | "accessToken" | "refreshToken" | "department"
> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const data = JSON.parse(raw);
      return {
        user: data.user ?? null,
        accessToken: data.accessToken ?? null,
        refreshToken: data.refreshToken ?? null,
        department: data.department ?? null,
      };
    }
  } catch {
    // ignore — corrupted or unavailable
  }
  return { user: null, accessToken: null, refreshToken: null, department: null };
}

// Save to localStorage if valid session, otherwise clear it
function persistSession(state: {
  user: SessionUser | null;
  accessToken: string | null;
  refreshToken: string | null;
  department: DepartmentInfo | null;
}) {
  if (state.user && state.accessToken) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } else {
    localStorage.removeItem(STORAGE_KEY);
  }
}

const initial = loadPersistedSession();

export const useSessionStore = create<SessionState>((set) => ({
  user: initial.user,
  accessToken: initial.accessToken,
  refreshToken: initial.refreshToken,
  department: initial.department,

  setSession: ({ user, accessToken, refreshToken, department }) => {
    const state = {
      user,
      accessToken,
      refreshToken: refreshToken ?? null,
      department: department ?? null,
    };
    persistSession(state);
    set(state);
  },

  setDepartment: (dept) =>
    set((prev) => {
      const next = { ...prev, department: dept };
      persistSession(next);
      return { department: dept };
    }),

  updateUser: (partial) =>
    set((prev) => {
      if (!prev.user) return {};
      const user = { ...prev.user, ...partial };
      const next = { ...prev, user };
      persistSession(next);
      return { user };
    }),

  signOut: () => {
    persistSession({ user: null, accessToken: null, refreshToken: null, department: null });
    set({ user: null, accessToken: null, refreshToken: null, department: null });
  },
}));

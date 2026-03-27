import { create } from "zustand";

export type AppRole = "citizen" | "department" | "municipality";

export type SessionUser = {
  id: string;
  email: string;
  role: AppRole;
};

type SessionState = {
  user: SessionUser | null;
  accessToken: string | null;
  signInAs: (role: AppRole) => void;
  signOut: () => void;
};

export const useSessionStore = create<SessionState>((set) => ({
  user: null,
  accessToken: null,
  signInAs: (role) =>
    set({
      accessToken: `phase0-${role}-token`,
      user: {
        id: `${role}-demo-user`,
        email: `${role}@dispatch.local`,
        role,
      },
    }),
  signOut: () =>
    set({
      user: null,
      accessToken: null,
    }),
}));

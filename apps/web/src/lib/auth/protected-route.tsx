// Route guard — redirects to login if no session, or role home if wrong role.
// Wraps route groups as a layout route (renders <Outlet />).

import { Navigate, Outlet, useLocation } from "react-router-dom";

import { useSessionStore } from "@/lib/auth/session-store";

type ProtectedRouteProps = {
  allowedRoles?: Array<"citizen" | "department" | "municipality">;
};

const roleHomePaths: Record<string, string> = {
  citizen: "/citizen",
  department: "/department",
  municipality: "/municipality",
};

export function ProtectedRoute({ allowedRoles }: ProtectedRouteProps) {
  const location = useLocation();
  const user = useSessionStore((state) => state.user);
  const accessToken = useSessionStore((state) => state.accessToken);

  // Not logged in → send to login, save intended path for redirect back
  if (!user || !accessToken) {
    return <Navigate replace state={{ from: location.pathname }} to="/auth/login" />;
  }

  // Wrong role → send to the user's actual role home, not the landing page
  if (allowedRoles && !allowedRoles.includes(user.role)) {
    return <Navigate replace to={roleHomePaths[user.role] ?? "/auth/login"} />;
  }

  return <Outlet />;
}

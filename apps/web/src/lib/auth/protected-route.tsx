// Route guard — redirects to login if no session, or home if wrong role.
// Wraps route groups as a layout route (renders <Outlet />).

import { Navigate, Outlet, useLocation } from "react-router-dom";

import { useSessionStore } from "@/lib/auth/session-store";

type ProtectedRouteProps = {
  allowedRoles?: Array<"citizen" | "department" | "municipality">;
};

export function ProtectedRoute({ allowedRoles }: ProtectedRouteProps) {
  const location = useLocation();
  const user = useSessionStore((state) => state.user);

  // Not logged in → send to login, save intended path for redirect back
  if (!user) {
    return <Navigate replace state={{ from: location.pathname }} to="/auth/login" />;
  }

  // Wrong role → send to home
  if (allowedRoles && !allowedRoles.includes(user.role)) {
    return <Navigate replace to="/" />;
  }

  return <Outlet />;
}

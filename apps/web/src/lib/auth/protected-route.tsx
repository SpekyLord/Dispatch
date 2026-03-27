import { Navigate, Outlet, useLocation } from "react-router-dom";

import { useSessionStore } from "@/lib/auth/session-store";

type ProtectedRouteProps = {
  allowedRoles?: Array<"citizen" | "department" | "municipality">;
};

export function ProtectedRoute({ allowedRoles }: ProtectedRouteProps) {
  const location = useLocation();
  const user = useSessionStore((state) => state.user);

  if (!user) {
    return <Navigate replace state={{ from: location.pathname }} to="/auth/login" />;
  }

  if (allowedRoles && !allowedRoles.includes(user.role)) {
    return <Navigate replace to="/" />;
  }

  return <Outlet />;
}

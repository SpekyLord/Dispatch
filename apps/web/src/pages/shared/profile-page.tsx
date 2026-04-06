// Redirect /profile to the role-specific profile page.
import { Navigate } from "react-router-dom";
import { useSessionStore } from "@/lib/auth/session-store";

const roleProfilePaths: Record<string, string> = {
  citizen: "/citizen/profile",
  department: "/department/profile",
  municipality: "/municipality/profile",
};

export function ProfilePage() {
  const user = useSessionStore((s) => s.user);
  return <Navigate replace to={roleProfilePaths[user?.role ?? ""] ?? "/"} />;
}

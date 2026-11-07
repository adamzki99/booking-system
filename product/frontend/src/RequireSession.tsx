import type { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { useSession } from "./auth/SessionContext";

/**
 * Renders its children only for signed-in users and redirects others to the
 * login page. While a stored token is being validated nothing is rendered, so
 * a reload does not flash the login page.
 */
export function RequireSession({ children }: { children: ReactNode }) {
  const { user, loading } = useSession();
  const location = useLocation();

  if (loading) {
    return null;
  }
  if (!user) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }
  return <>{children}</>;
}

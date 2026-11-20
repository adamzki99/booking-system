import { createRouter, useNavigate } from "@solidjs/router";
import type { RouteSectionProps } from "@solidjs/router";
import type { JSX } from "@solidjs/web";
import { RequireSession } from "./RequireSession";
import AppShell from "./components/AppShell";
import Account from "./pages/Account";
import Calendar from "./pages/Calendar";
import Login from "./pages/Login";
import Users from "./pages/Users";

function Protected(props: { children?: JSX.Element }) {
  return (
    <RequireSession>
      <AppShell>{props.children}</AppShell>
    </RequireSession>
  );
}

function ProtectedCalendar() {
  return (
    <Protected>
      <Calendar />
    </Protected>
  );
}

function ProtectedAccount() {
  return (
    <Protected>
      <Account />
    </Protected>
  );
}

function ProtectedUsers() {
  return (
    <Protected>
      <Users />
    </Protected>
  );
}

function RedirectHome() {
  const navigate = useNavigate();
  navigate("/", { replace: true });
  return null;
}

export const appRoutes = [
  { path: "/login", component: Login as (props: RouteSectionProps) => JSX.Element },
  { path: "/", component: ProtectedCalendar },
  { path: "/account", component: ProtectedAccount },
  { path: "/users", component: ProtectedUsers },
  { path: "*", component: RedirectHome },
];

export const Router = createRouter({ routes: appRoutes });

export default function App() {
  return <Router>{(props) => <>{props.children}</>}</Router>;
}

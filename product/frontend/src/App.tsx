import { Navigate, Route, Routes } from "react-router-dom";
import { RequireSession } from "./RequireSession";
import AppShell from "./components/AppShell";
import Account from "./pages/Account";
import Calendar from "./pages/Calendar";
import Login from "./pages/Login";
import Users from "./pages/Users";

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <RequireSession>
            <AppShell>
              <Calendar />
            </AppShell>
          </RequireSession>
        }
      />
      <Route
        path="/account"
        element={
          <RequireSession>
            <AppShell>
              <Account />
            </AppShell>
          </RequireSession>
        }
      />
      <Route
        path="/users"
        element={
          <RequireSession>
            <AppShell>
              <Users />
            </AppShell>
          </RequireSession>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

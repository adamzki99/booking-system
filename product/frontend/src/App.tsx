import { Navigate, Route, Routes } from "react-router-dom";
import { RequireSession } from "./RequireSession";
import Calendar from "./pages/Calendar";
import Login from "./pages/Login";

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <RequireSession>
            <Calendar />
          </RequireSession>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

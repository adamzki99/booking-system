import { render } from "@solidjs/web";
import App from "./App";
import { SessionProvider } from "./auth/SessionContext";
import "./index.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("Root element not found");
}

render(
  () => (
    <SessionProvider>
      <App />
    </SessionProvider>
  ),
  root,
);

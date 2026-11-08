import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { useSession } from "../auth/SessionContext";
import { getChrome, type ChromeInfo } from "../api/chrome";

export interface AppShellProps {
  children: ReactNode;
}

export function AppShell({ children }: AppShellProps) {
  const { logout } = useSession();
  const navigate = useNavigate();
  const [drawerOpen, setDrawerOpen] = useState<boolean>(true);
  const [chrome, setChrome] = useState<ChromeInfo>({ header: "", footer: "" });

  useEffect(() => {
    let cancelled = false;
    getChrome()
      .then((info) => {
        if (!cancelled) setChrome(info);
      })
      .catch(() => {
        // Graceful fallback: keep empty content.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  function handleLogout() {
    logout();
    navigate("/login", { replace: true });
  }

  return (
    <div>
      <header>{chrome.header}</header>
      <button
        type="button"
        onClick={() => setDrawerOpen((open) => !open)}
        aria-label="Toggle drawer"
      >
        Toggle drawer
      </button>
      {drawerOpen && <aside data-testid="drawer">Navigation</aside>}
      <main>{children}</main>
      <footer>{chrome.footer}</footer>
      <button type="button" onClick={handleLogout}>
        Log out
      </button>
    </div>
  );
}

export default AppShell;

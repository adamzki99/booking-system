import { For, createSignal, onCleanup } from "solid-js";
import type { JSX } from "@solidjs/web";
import { useLocation, useNavigate } from "@solidjs/router";
import { useSession } from "../auth/SessionContext";
import type { User } from "../api/auth";
import { getChrome, type ChromeInfo } from "../api/chrome";
import Button from "../ui/Button";
import "./AppShell.css";

export interface AppShellProps {
  children?: JSX.Element;
}

const REDEPLOY_TICK_MS = 30_000;
const CREATE_BOOKING_HREF = "/?create=1";

const ROLE_LABELS: Record<User["role"], string> = {
  basic: "Member",
  super: "Super user",
  admin: "Admin",
};

const NAV_ITEMS = [
  { to: "/", label: "Bookings" },
  { to: "/users", label: "Members" },
  { to: "/account", label: "Account" },
] as const;

/** Formats the time until the next redeploy, or "" when there is no valid time. */
export function formatRedeployCountdown(nextRedeploy: string, now: number): string {
  const target = Date.parse(nextRedeploy);
  if (Number.isNaN(target)) return "";
  const diff = target - now;
  if (diff <= 0) return "Next redeploy due now";
  const totalMinutes = Math.floor(diff / 60_000);
  if (totalMinutes < 1) return "Next redeploy in <1m";
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  const parts: string[] = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  if (days === 0 && minutes > 0) parts.push(`${minutes}m`);
  return `Next redeploy in ${parts.join(" ")}`;
}

function initials(user: User | null): string {
  if (!user) return "?";
  const base = user.email.split("@")[0] || user.id;
  const parts = base.split(/[._-]+/).filter(Boolean);
  const value = parts.length >= 2 ? `${parts[0][0]}${parts[1][0]}` : base.slice(0, 2);
  return value.toUpperCase() || "?";
}

function usersLink(query: string) {
  const trimmed = query.trim();
  return trimmed ? `/users?q=${encodeURIComponent(trimmed)}` : "/users";
}

function BrandLockup(props: { header: string; footer: string }) {
  return (
    <div class="app-shell-brand">
      <div class="app-shell-brand-mark" aria-hidden="true">
        {(props.header || "B").charAt(0).toUpperCase()}
      </div>
      <div class="app-shell-brand-text">
        <div class="app-shell-brand-title">{props.header || "Bookings"}</div>
        <div class="app-shell-brand-subtitle">{props.footer || "Booking system"}</div>
      </div>
    </div>
  );
}

function CreateBookingButton(props: { onClick: () => void }) {
  return (
    <Button variant="accent" size="lg" class="app-shell-create" onClick={props.onClick}>
      Create booking
    </Button>
  );
}

function PagesNav(props: { onNavigate?: () => void }) {
  const location = useLocation();
  const active = (to: string) =>
    to === "/"
      ? location.pathname === "/"
      : location.pathname === to || location.pathname.startsWith(`${to}/`);

  return (
    <nav aria-label="Pages" class="app-shell-nav">
      <For each={NAV_ITEMS}>
        {(item) => (
          <a
            href={item.to}
            class={["app-shell-nav-link", { active: active(item.to) }]}
            aria-current={active(item.to) ? "page" : undefined}
            onClick={() => props.onNavigate?.()}
          >
            {item.label}
          </a>
        )}
      </For>
    </nav>
  );
}

function MemberFooter(props: { user: User | null; onLogout: () => void }) {
  return (
    <div class="app-shell-member">
      <div class="app-shell-member-info">
        <div class="app-shell-avatar" aria-hidden="true">
          {initials(props.user)}
        </div>
        <div>
          <div class="app-shell-member-email">{props.user?.email ?? "Not signed in"}</div>
          <div class="app-shell-member-role">
            {props.user ? ROLE_LABELS[props.user.role] : "Signed out"}
          </div>
        </div>
      </div>
      <Button variant="accentOutline" size="sm" class="app-shell-logout" onClick={props.onLogout}>
        Log out
      </Button>
    </div>
  );
}

export function AppShell(props: AppShellProps) {
  const session = useSession();
  const navigate = useNavigate();
  const location = useLocation();

  const [chrome, setChrome] = createSignal<ChromeInfo>({
    header: "",
    footer: "",
    nextRedeploy: "",
  });
  const [search, setSearch] = createSignal("");
  const [menuOpen, setMenuOpen] = createSignal(false);
  const [notificationsOpen, setNotificationsOpen] = createSignal(false);
  const [now, setNow] = createSignal(Date.now());

  let cancelled = false;
  void getChrome()
    .then((info) => {
      if (!cancelled) setChrome(info);
    })
    .catch(() => {
      // Graceful fallback: keep empty content.
    });

  const tick = window.setInterval(() => setNow(Date.now()), REDEPLOY_TICK_MS);
  onCleanup(() => {
    cancelled = true;
    window.clearInterval(tick);
  });

  const onBookingsPage = () => location.pathname === "/";
  const onMembersPage = () =>
    location.pathname === "/users" || location.pathname.startsWith("/users/");
  const showShellCreate = () => !onBookingsPage();
  const showGlobalSearch = () => !onMembersPage();

  function handleLogout() {
    session.logout();
    navigate("/login", { replace: true });
  }

  function handleCreateBooking() {
    setMenuOpen(false);
    navigate(CREATE_BOOKING_HREF);
  }

  function handleSearchSubmit(event: Event) {
    event.preventDefault();
    const form = event.currentTarget as HTMLFormElement | null;
    const input = form?.querySelector(
      'input[aria-label="Search members"]',
    ) as HTMLInputElement | null;
    navigate(usersLink(input?.value ?? search()));
  }

  const redeployLabel = () => formatRedeployCountdown(chrome().nextRedeploy, now());

  return (
    <div class="app-shell">
      <aside class="app-shell-sidebar">
        <BrandLockup header={chrome().header} footer={chrome().footer} />
        {showShellCreate() && (
          <div class="app-shell-sidebar-create">
            <CreateBookingButton onClick={handleCreateBooking} />
          </div>
        )}
        <div class="app-shell-sidebar-nav">
          <PagesNav />
        </div>
        <MemberFooter user={session.user()} onLogout={handleLogout} />
      </aside>

      <div class="app-shell-main-column">
        <header class="app-shell-topbar">
          <div class="app-shell-topbar-left">
            <button
              type="button"
              aria-label="Open menu"
              class="app-shell-icon-button"
              onClick={() => setMenuOpen(true)}
            >
              Menu
            </button>
            <div class="app-shell-topbar-brand">
              <BrandLockup header={chrome().header} footer={chrome().footer} />
            </div>
            {showGlobalSearch() && (
              <form class="app-shell-search-form" onSubmit={handleSearchSubmit}>
                <input
                  aria-label="Search members"
                  placeholder="Search members"
                  value={search()}
                  onInput={(e) => setSearch(e.currentTarget.value)}
                  class="ui-input app-shell-search-input"
                />
              </form>
            )}
          </div>
          <div class="app-shell-topbar-right">
            {redeployLabel() ? (
              <span
                class="app-shell-redeploy"
                data-testid="redeploy-indicator"
                title={
                  chrome().nextRedeploy
                    ? new Date(Date.parse(chrome().nextRedeploy)).toLocaleString()
                    : undefined
                }
              >
                {redeployLabel()}
              </span>
            ) : null}
            {showGlobalSearch() && (
              <button
                type="button"
                aria-label="Search members"
                class="app-shell-icon-button app-shell-mobile-search"
                onClick={() => navigate(usersLink(search()))}
              >
                Search
              </button>
            )}
            <div class="app-shell-notifications">
              <button
                type="button"
                aria-label="Notifications"
                class="app-shell-icon-button"
                onClick={() => setNotificationsOpen((open) => !open)}
              >
                Bell
              </button>
              {notificationsOpen() && (
                <dialog class="app-shell-popover" open aria-label="Notifications">
                  <div class="app-shell-popover-header">Notifications</div>
                  <div class="app-shell-popover-body">No notifications yet.</div>
                </dialog>
              )}
            </div>
            <div class="app-shell-avatar app-shell-topbar-avatar" aria-hidden="true">
              {initials(session.user())}
            </div>
          </div>
        </header>

        <main class="app-shell-content">{props.children}</main>
      </div>

      {showShellCreate() && (
        <div class="app-shell-bottom-dock">
          <CreateBookingButton onClick={handleCreateBooking} />
        </div>
      )}

      {menuOpen() && (
        <div class="app-shell-drawer-overlay">
          <div class="app-shell-drawer" data-testid="drawer">
            <button
              type="button"
              aria-label="Close menu"
              class="app-shell-icon-button app-shell-drawer-close"
              onClick={() => setMenuOpen(false)}
            >
              Close
            </button>
            <BrandLockup header={chrome().header} footer={chrome().footer} />
            {showShellCreate() && (
              <div class="app-shell-sidebar-create">
                <CreateBookingButton onClick={handleCreateBooking} />
              </div>
            )}
            <div class="app-shell-sidebar-nav">
              <PagesNav onNavigate={() => setMenuOpen(false)} />
            </div>
            <MemberFooter user={session.user()} onLogout={handleLogout} />
          </div>
        </div>
      )}
    </div>
  );
}

export default AppShell;

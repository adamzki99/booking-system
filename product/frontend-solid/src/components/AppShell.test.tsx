import { fireEvent, screen, within } from "@solidjs/testing-library";
import { createRouter, memoryHistory, useLocation } from "@solidjs/router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "../test-utils";
import { getChrome } from "../api/chrome";
import { useSession } from "../auth/SessionContext";
import type { User } from "../api/auth";
import { AppShell, formatRedeployCountdown } from "./AppShell";

vi.mock("../api/chrome", () => ({ getChrome: vi.fn() }));
vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));

const getChromeMock = vi.mocked(getChrome);
const useSessionMock = vi.mocked(useSession);

function member(role: User["role"] = "basic"): User {
  return { id: "u1", email: "member@example.com", role, address: null, active: true };
}

function LocationProbe() {
  const location = useLocation();
  return <div data-testid="location">{location.pathname + location.search}</div>;
}

function renderShell(initialEntry = "/") {
  const Router = createRouter({
    history: memoryHistory(initialEntry),
    routes: [
      {
        path: "*",
        component: () => (
          <>
            <LocationProbe />
            <AppShell>
              <p>content</p>
            </AppShell>
          </>
        ),
      },
    ],
  });

  render(() => <Router>{(props) => <>{props.children}</>}</Router>);
}

describe("AppShell", () => {
  beforeEach(() => {
    getChromeMock.mockReset();
    useSessionMock.mockReset();
    getChromeMock.mockResolvedValue({ header: "Sauna", footer: "Footer", nextRedeploy: "" });
    useSessionMock.mockReturnValue({
      user: () => member(),
      loading: () => false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout: vi.fn(),
    } as any);
  });

  it("renders the responsive shell structure with navigation, search, and member footer", async () => {
    renderShell();

    expect((await screen.findAllByText("Sauna")).length).toBeGreaterThan(0);
    expect((await screen.findAllByText("Footer")).length).toBeGreaterThan(0);

    const nav = screen.getByRole("navigation", { name: "Pages" });
    expect(within(nav).getByRole("link", { name: "Bookings" })).toHaveAttribute("href", "/");
    expect(within(nav).getByRole("link", { name: "Members" })).toHaveAttribute("href", "/users");
    expect(within(nav).getByRole("link", { name: "Account" })).toHaveAttribute("href", "/account");

    expect(screen.getByPlaceholderText("Search members")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Notifications" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open menu" })).toBeInTheDocument();

    expect(screen.getAllByText("member@example.com").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Member").length).toBeGreaterThan(0);
    expect(screen.getAllByRole("button", { name: "Log out" }).length).toBeGreaterThan(0);
  });

  it("hides the global member search on the Members page to avoid duplicate search controls", async () => {
    renderShell("/users");

    expect(await screen.findAllByText("Sauna")).not.toHaveLength(0);
    expect(screen.queryByPlaceholderText("Search members")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Search members" })).not.toBeInTheDocument();
  });

  it("marks the active route with aria-current=page", async () => {
    renderShell("/users");

    const nav = screen.getByRole("navigation", { name: "Pages" });
    expect(within(nav).getByRole("link", { name: "Members" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(within(nav).getByRole("link", { name: "Bookings" })).not.toHaveAttribute("aria-current");
  });

  it("opens and closes the mobile menu", async () => {
    renderShell();

    fireEvent.click(screen.getByRole("button", { name: "Open menu" }));
    const closeButtons = await screen.findAllByRole("button", { name: "Close menu" });
    expect(closeButtons.length).toBeGreaterThan(0);
    expect(screen.getAllByRole("navigation", { name: "Pages" }).length).toBeGreaterThan(1);

    fireEvent.click(closeButtons[0]);
    await vi.waitFor(() => {
      expect(screen.queryByRole("button", { name: "Close menu" })).not.toBeInTheDocument();
    });
  });

  it("navigates to the booking creation flow from the shell Create booking CTA on non-booking pages", async () => {
    renderShell("/account");

    fireEvent.click((await screen.findAllByRole("button", { name: "Create booking" }))[0]);
    expect(await screen.findByTestId("location")).toHaveTextContent("/?create=1");
  });

  it("shows a notifications message when the notifications control is opened", async () => {
    renderShell();

    fireEvent.click(screen.getByRole("button", { name: "Notifications" }));
    expect(await screen.findByText(/no notifications yet/i)).toBeInTheDocument();
  });

  it("submits member search to the users route with a query", async () => {
    renderShell();

    const input = screen.getByPlaceholderText("Search members") as HTMLInputElement;
    fireEvent.input(input, { target: { value: "anna" } });
    const form = input.closest("form");
    expect(form).not.toBeNull();
    fireEvent.submit(form!);
    await vi.waitFor(() => {
      expect(screen.getByTestId("location")).toHaveTextContent("/users?q=anna");
    });
  });

  it.each([
    ["basic", "Member"],
    ["super", "Super user"],
    ["admin", "Admin"],
  ] as const)("shows the %s role as %s", async (role, label) => {
    useSessionMock.mockReturnValue({
      user: () => member(role),
      loading: () => false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout: vi.fn(),
    } as any);
    renderShell();
    expect((await screen.findAllByText(label)).length).toBeGreaterThan(0);
  });

  it("logs out and returns to the login route", async () => {
    const logout = vi.fn();
    useSessionMock.mockReturnValue({
      user: () => member(),
      loading: () => false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout,
    } as any);
    renderShell();

    fireEvent.click(screen.getAllByRole("button", { name: "Log out" })[0]);
    expect(logout).toHaveBeenCalledOnce();
    expect(await screen.findByTestId("location")).toHaveTextContent("/login");
  });

  it("shows the next redeploy countdown when a schedule is exposed", async () => {
    getChromeMock.mockResolvedValue({
      header: "Sauna",
      footer: "Footer",
      nextRedeploy: new Date(Date.now() + 2 * 60 * 60 * 1000 + 30_000).toISOString(),
    });

    renderShell();

    expect(await screen.findByText("Next redeploy in 2h")).toBeInTheDocument();
  });

  it("hides the redeploy indicator when no schedule is exposed", async () => {
    renderShell();

    expect(await screen.findAllByText("Sauna")).not.toHaveLength(0);
    expect(screen.queryByTestId("redeploy-indicator")).not.toBeInTheDocument();
  });
});

describe("formatRedeployCountdown", () => {
  const now = Date.parse("2026-11-09T10:00:00Z");

  it("formats days, hours, and minutes", () => {
    expect(formatRedeployCountdown("2026-11-10T12:05:00Z", now)).toBe("Next redeploy in 1d 2h");
    expect(formatRedeployCountdown("2026-11-09T13:42:00Z", now)).toBe("Next redeploy in 3h 42m");
    expect(formatRedeployCountdown("2026-11-09T10:05:00Z", now)).toBe("Next redeploy in 5m");
  });

  it("handles sub-minute, due, invalid, and empty values", () => {
    expect(formatRedeployCountdown("2026-11-09T10:00:30Z", now)).toBe("Next redeploy in <1m");
    expect(formatRedeployCountdown("2026-11-09T10:00:00Z", now)).toBe("Next redeploy due now");
    expect(formatRedeployCountdown("not-a-date", now)).toBe("");
    expect(formatRedeployCountdown("", now)).toBe("");
  });
});

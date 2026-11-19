import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes, useLocation } from "react-router-dom";
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
  render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <LocationProbe />
      <Routes>
        <Route path="*" element={<AppShell><p>content</p></AppShell>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("AppShell", () => {
  beforeEach(() => {
    getChromeMock.mockReset();
    useSessionMock.mockReset();
    getChromeMock.mockResolvedValue({ header: "Sauna", footer: "Footer", nextRedeploy: "" });
    useSessionMock.mockReturnValue({
      user: member(),
      loading: false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout: vi.fn(),
    });
  });

  it("renders the responsive shell structure with navigation, search, and member footer", async () => {
    renderShell();

    // Brand lockup sourced from /api/chrome.
    expect((await screen.findAllByText("Sauna")).length).toBeGreaterThan(0);
    expect((await screen.findAllByText("Footer")).length).toBeGreaterThan(0);

    // Pages navigation with routes from the plan.
    const nav = screen.getByRole("navigation", { name: "Pages" });
    expect(within(nav).getByRole("link", { name: "Bookings" })).toHaveAttribute("href", "/");
    expect(within(nav).getByRole("link", { name: "Members" })).toHaveAttribute("href", "/users");
    expect(within(nav).getByRole("link", { name: "Account" })).toHaveAttribute("href", "/account");

    // Search and notifications utilities.
    expect(screen.getByPlaceholderText("Search members")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Notifications" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open menu" })).toBeInTheDocument();

    // Signed-in member footer.
    expect(screen.getAllByText("member@example.com").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Member").length).toBeGreaterThan(0);
    expect(screen.getAllByRole("button", { name: "Log out" }).length).toBeGreaterThan(0);
  });

  it("marks the active route with aria-current=page", async () => {
    renderShell("/users");

    const nav = screen.getByRole("navigation", { name: "Pages" });
    expect(within(nav).getByRole("link", { name: "Members" })).toHaveAttribute("aria-current", "page");
    expect(within(nav).getByRole("link", { name: "Bookings" })).not.toHaveAttribute("aria-current");
  });

  it("opens and closes the mobile menu", async () => {
    renderShell();
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Open menu" }));
    const closeButtons = await screen.findAllByRole("button", { name: "Close menu" });
    expect(closeButtons.length).toBeGreaterThan(0);
    expect(screen.getAllByRole("navigation", { name: "Pages" }).length).toBeGreaterThan(1);

    await user.click(closeButtons[0]);
    await vi.waitFor(() => {
      expect(screen.queryByRole("button", { name: "Close menu" })).not.toBeInTheDocument();
    });
  });

  it("navigates to the booking creation flow from the Create booking CTA", async () => {
    renderShell();
    const user = userEvent.setup();

    await user.click(screen.getAllByRole("button", { name: "Create booking" })[0]);
    expect(screen.getByTestId("location")).toHaveTextContent("/?create=1");
  });

  it("submits member search to the users route with a query", async () => {
    renderShell();
    const user = userEvent.setup();

    const input = screen.getByPlaceholderText("Search members");
    await user.type(input, "anna");
    await user.type(input, "{Enter}");
    expect(screen.getByTestId("location")).toHaveTextContent("/users?q=anna");
  });

  it.each([
    ["basic", "Member"],
    ["super", "Super user"],
    ["admin", "Admin"],
  ] as const)("shows the %s role as %s", (role, label) => {
    useSessionMock.mockReturnValue({
      user: member(role),
      loading: false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout: vi.fn(),
    });
    renderShell();
    expect(screen.getAllByText(label).length).toBeGreaterThan(0);
  });

  it("logs out and returns to the login route", async () => {
    const logout = vi.fn();
    useSessionMock.mockReturnValue({
      user: member(),
      loading: false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout,
    });
    renderShell();
    const user = userEvent.setup();

    await user.click(screen.getAllByRole("button", { name: "Log out" })[0]);
    expect(logout).toHaveBeenCalledOnce();
    expect(screen.getByTestId("location")).toHaveTextContent("/login");
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

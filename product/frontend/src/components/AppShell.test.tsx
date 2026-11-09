import { screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter } from "react-router-dom";
import { render } from "../test-utils";
import { getChrome } from "../api/chrome";
import { useSession } from "../auth/SessionContext";
import { AppShell, formatRedeployCountdown } from "./AppShell";

vi.mock("../api/chrome", () => ({ getChrome: vi.fn() }));
vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));

const getChromeMock = vi.mocked(getChrome);
const useSessionMock = vi.mocked(useSession);

function renderShell() {
  render(
    <MemoryRouter>
      <AppShell>
        <p>content</p>
      </AppShell>
    </MemoryRouter>,
  );
}

describe("AppShell", () => {
  beforeEach(() => {
    getChromeMock.mockReset();
    useSessionMock.mockReset();
    useSessionMock.mockReturnValue({
      user: null,
      loading: false,
      login: vi.fn(),
      logout: vi.fn(),
    });
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
    getChromeMock.mockResolvedValue({
      header: "Sauna",
      footer: "Footer",
      nextRedeploy: "",
    });

    renderShell();

    expect(await screen.findByText("Sauna")).toBeInTheDocument();
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

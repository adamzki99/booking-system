import { screen } from "@solidjs/testing-library";
import { createRouter, memoryHistory } from "@solidjs/router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "./test-utils";
import { useSession } from "./auth/SessionContext";
import { RequireSession } from "./RequireSession";

vi.mock("./auth/SessionContext", () => ({ useSession: vi.fn() }));

const useSessionMock = vi.mocked(useSession);

function renderRoutes(initialPath = "/") {
  const Router = createRouter({
    history: memoryHistory(initialPath),
    routes: [
      {
        path: "/",
        component: () => (
          <RequireSession>
            <p>calendar</p>
          </RequireSession>
        ),
      },
      {
        path: "/login",
        component: () => <p>login</p>,
      },
    ],
  });

  render(() => <Router>{(props) => <>{props.children}</>}</Router>);
}

describe("RequireSession", () => {
  beforeEach(() => {
    useSessionMock.mockReset();
  });

  it("redirects to the login page when signed out", async () => {
    useSessionMock.mockReturnValue({
      user: () => null,
      loading: () => false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout: vi.fn(),
    } as any);
    renderRoutes();

    expect(await screen.findByText("login")).toBeInTheDocument();
  });

  it("stays on the page while a session is present", async () => {
    useSessionMock.mockReturnValue({
      user: () => ({
        id: "u1",
        email: "user@example.com",
        role: "basic",
        address: null,
        active: true,
      }),
      loading: () => false,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout: vi.fn(),
    } as any);
    renderRoutes();

    expect(await screen.findByText("calendar")).toBeInTheDocument();
  });

  it("shows nothing while the stored session is loading", async () => {
    useSessionMock.mockReturnValue({
      user: () => null,
      loading: () => true,
      login: vi.fn(),
      loginWithQAMode: vi.fn(),
      refresh: vi.fn(),
      logout: vi.fn(),
    } as any);
    renderRoutes();

    await Promise.resolve();
    expect(screen.queryByText("login")).not.toBeInTheDocument();
    expect(screen.queryByText("calendar")).not.toBeInTheDocument();
  });
});

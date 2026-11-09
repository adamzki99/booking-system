import { screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { render } from "./test-utils";
import { useSession } from "./auth/SessionContext";
import { RequireSession } from "./RequireSession";

vi.mock("./auth/SessionContext", () => ({ useSession: vi.fn() }));

const useSessionMock = vi.mocked(useSession);

function renderRoutes() {
  render(
    <MemoryRouter initialEntries={["/"]}>
      <Routes>
        <Route
          path="/"
          element={
            <RequireSession>
              <p>calendar</p>
            </RequireSession>
          }
        />
        <Route path="/login" element={<p>login</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("RequireSession", () => {
  beforeEach(() => {
    useSessionMock.mockReset();
  });

  it("redirects to the login page when signed out", async () => {
    useSessionMock.mockReturnValue({
      user: null,
      loading: false,
      login: vi.fn(),
      logout: vi.fn(),
    });
    renderRoutes();

    expect(await screen.findByText("login")).toBeInTheDocument();
  });

  it("stays on the page while a session is present", async () => {
    useSessionMock.mockReturnValue({
      user: {
        id: "u1",
        email: "user@example.com",
        role: "basic",
        address: null,
        active: true,
      },
      loading: false,
      login: vi.fn(),
      logout: vi.fn(),
    });
    renderRoutes();

    expect(await screen.findByText("calendar")).toBeInTheDocument();
  });

  it("shows nothing while the stored session is loading", async () => {
    useSessionMock.mockReturnValue({
      user: null,
      loading: true,
      login: vi.fn(),
      logout: vi.fn(),
    });
    renderRoutes();
    await waitFor(() => {
      expect(screen.queryByText("login")).not.toBeInTheDocument();
    });

    // Still loading: no redirect flash to /login.
    expect(screen.queryByText("calendar")).not.toBeInTheDocument();
  });
});

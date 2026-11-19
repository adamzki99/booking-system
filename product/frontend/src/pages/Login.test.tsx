import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { render } from "../test-utils";
import { useSession } from "../auth/SessionContext";
import { getAuthConfig, requestCode } from "../api/auth";
import Login from "./Login";

vi.mock("../api/auth", () => ({
  getAuthConfig: vi.fn(),
  requestCode: vi.fn(),
}));
vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));

const getAuthConfigMock = vi.mocked(getAuthConfig);
const requestCodeMock = vi.mocked(requestCode);
const useSessionMock = vi.mocked(useSession);

function stubSession(
  login: () => Promise<void> = vi.fn().mockResolvedValue(undefined),
  loginWithQAMode: () => Promise<void> = vi.fn().mockResolvedValue(undefined),
) {
  useSessionMock.mockReturnValue({
    user: null,
    loading: false,
    login,
    loginWithQAMode,
    refresh: vi.fn(),
    logout: vi.fn(),
  } as any);
}

function renderLogin() {
  render(
    <MemoryRouter initialEntries={["/login"]}>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<p>calendar</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("Login page", () => {
  beforeEach(() => {
    getAuthConfigMock.mockReset();
    getAuthConfigMock.mockResolvedValue({ qaMode: false });
    requestCodeMock.mockReset();
    useSessionMock.mockReset();
    stubSession();
  });

  it("renders the Booking header and sign-in description", async () => {
    renderLogin();
    expect(screen.getByRole("heading", { name: "Booking" })).toBeInTheDocument();
    expect(await screen.findByText(/sign in with your email/i)).toBeInTheDocument();
  });

  it("requests a code for the entered email", async () => {
    renderLogin();

    await userEvent.type(screen.getByLabelText("Email"), "user@example.com");
    await userEvent.click(screen.getByRole("button", { name: "Request code" }));

    await waitFor(() =>
      expect(requestCodeMock).toHaveBeenCalledWith("user@example.com"),
    );
    expect(await screen.findByLabelText("Code")).toBeInTheDocument();
  });

  it("signs in with the code and redirects to the calendar", async () => {
    const login = vi.fn().mockResolvedValue(undefined);
    stubSession(login);
    renderLogin();

    await userEvent.type(screen.getByLabelText("Email"), "user@example.com");
    await userEvent.click(screen.getByRole("button", { name: "Request code" }));
    await screen.findByLabelText("Code");
    await userEvent.type(screen.getByLabelText("Code"), "ABC123");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    await waitFor(() =>
      expect(login).toHaveBeenCalledWith("user@example.com", "ABC123"),
    );
    expect(await screen.findByText("calendar")).toBeInTheDocument();
  });

  it("signs in without a code in QA mode", async () => {
    getAuthConfigMock.mockResolvedValue({ qaMode: true });
    const loginWithQAMode = vi.fn().mockResolvedValue(undefined);
    stubSession(vi.fn(), loginWithQAMode);
    renderLogin();

    await screen.findByRole("button", { name: "Sign in" });
    await userEvent.type(screen.getByLabelText("Email"), "user1@test.local");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    await waitFor(() =>
      expect(loginWithQAMode).toHaveBeenCalledWith("user1@test.local"),
    );
    expect(requestCodeMock).not.toHaveBeenCalled();
    expect(await screen.findByText("calendar")).toBeInTheDocument();
  });

  it("shows request-code failures", async () => {
    requestCodeMock.mockRejectedValue(new Error("too many requests"));

    renderLogin();

    await userEvent.type(screen.getByLabelText("Email"), "user@example.com");
    await userEvent.click(screen.getByRole("button", { name: "Request code" }));

    expect(await screen.findByText("too many requests")).toBeInTheDocument();
  });
});

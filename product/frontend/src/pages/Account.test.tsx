import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "../test-utils";
import { useSession } from "../auth/SessionContext";
import { currentUser } from "../api/auth";
import type { User } from "../api/auth";
import { confirmEmailChange, requestEmailChange } from "../api/users";
import Account from "./Account";

vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));
vi.mock("../api/auth", () => ({ currentUser: vi.fn() }));
vi.mock("../api/users", () => ({
  requestEmailChange: vi.fn(),
  confirmEmailChange: vi.fn(),
}));
vi.mock("../api/calendar", () => ({ regenerateCalendarUrl: vi.fn() }));

const useSessionMock = vi.mocked(useSession);
const currentUserMock = vi.mocked(currentUser);
const requestEmailChangeMock = vi.mocked(requestEmailChange);
const confirmEmailChangeMock = vi.mocked(confirmEmailChange);

const user: User = {
  id: "u1",
  email: "basic@example.com",
  role: "basic",
  address: "Sauna Street 1",
  active: true,
};

const refreshedUser: User = { ...user, email: "moved@example.com" };

function stubSession() {
  useSessionMock.mockReturnValue({
    user,
    loading: false,
    login: vi.fn(),
    refresh: vi.fn().mockResolvedValue(undefined),
    logout: vi.fn(),
  });
}

describe("Account page email change", () => {
  beforeEach(() => {
    useSessionMock.mockReset();
    currentUserMock.mockReset();
    requestEmailChangeMock.mockReset();
    confirmEmailChangeMock.mockReset();
    stubSession();
    currentUserMock.mockResolvedValue(user);
    requestEmailChangeMock.mockResolvedValue({
      pendingEmail: "moved@example.com",
      expiresAt: "2026-11-17T20:00:00Z",
    });
    confirmEmailChangeMock.mockResolvedValue(refreshedUser);
  });

  it("shows the account email from the session", async () => {
    render(<Account />);
    await screen.findByTestId("account-email");
    await waitFor(() =>
      expect(screen.getByTestId("account-email").textContent).toBe(
        "basic@example.com",
      ),
    );
  });

  it("walks through request, code entry and confirm, then refreshes the session", async () => {
    render(<Account />);
    await screen.findByTestId("account-email");

    const usr = userEvent.setup();
    const emailInput = screen.getByLabelText("New email") as HTMLInputElement;
    await usr.clear(emailInput);
    await usr.type(emailInput, "moved@example.com");
    await usr.click(screen.getByRole("button", { name: "Send verification code" }));

    await waitFor(() =>
      expect(requestEmailChangeMock).toHaveBeenCalledWith("moved@example.com"),
    );

    // The page moves to the code step.
    await screen.findByLabelText("Verification code");
    expect(
      screen.getByText(/verification code was sent to moved@example.com/i),
    ).toBeInTheDocument();

    await usr.type(screen.getByLabelText("Verification code"), "ABC123");
    await usr.click(screen.getByRole("button", { name: "Confirm email change" }));

    await waitFor(() => expect(confirmEmailChangeMock).toHaveBeenCalledWith("ABC123"));

    // The session context is refreshed so it agrees with the account.
    await waitFor(() => expect(useSessionMock().refresh).toHaveBeenCalled());

    // The displayed email and the code step are cleared.
    await waitFor(() =>
      expect(screen.getByTestId("account-email").textContent).toBe(
        "moved@example.com",
      ),
    );
    expect(
      screen.queryByLabelText("Verification code"),
    ).not.toBeInTheDocument();
  });

  it("surfaces backend errors without leaving the account unchanged", async () => {
    requestEmailChangeMock.mockRejectedValue(
      Object.assign(new Error("user: duplicate email"), { name: "ApiError" }),
    );
    render(<Account />);
    await screen.findByTestId("account-email");

    await userEvent
      .setup()
      .click(screen.getByRole("button", { name: "Send verification code" }));

    await screen.findByRole("alert");
    expect(screen.getByRole("alert").textContent).toContain(
      "user: duplicate email",
    );
  });
});

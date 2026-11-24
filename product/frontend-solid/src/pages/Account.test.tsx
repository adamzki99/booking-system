import { fireEvent, screen, waitFor } from "@solidjs/testing-library";
import { flush } from "solid-js";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "../test-utils";
import { useSession } from "../auth/SessionContext";
import { currentUser } from "../api/auth";
import type { User } from "../api/auth";
import {
  cancelEmailChange,
  confirmEmailChange,
  getPendingEmailChange,
  requestEmailChange,
  resendEmailChange,
} from "../api/users";
import { regenerateCalendarUrl } from "../api/calendar";
import Account from "./Account";

vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));
vi.mock("../api/auth", () => ({ currentUser: vi.fn() }));
vi.mock("../api/users", () => ({
  requestEmailChange: vi.fn(),
  confirmEmailChange: vi.fn(),
  getPendingEmailChange: vi.fn(),
  resendEmailChange: vi.fn(),
  cancelEmailChange: vi.fn(),
}));
vi.mock("../api/calendar", () => ({ regenerateCalendarUrl: vi.fn() }));

const useSessionMock = vi.mocked(useSession);
const currentUserMock = vi.mocked(currentUser);
const requestEmailChangeMock = vi.mocked(requestEmailChange);
const confirmEmailChangeMock = vi.mocked(confirmEmailChange);
const getPendingEmailChangeMock = vi.mocked(getPendingEmailChange);
const resendEmailChangeMock = vi.mocked(resendEmailChange);
const cancelEmailChangeMock = vi.mocked(cancelEmailChange);
const regenerateCalendarUrlMock = vi.mocked(regenerateCalendarUrl);

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
    user: () => user,
    loading: () => false,
    login: vi.fn(),
    loginWithQAMode: vi.fn(),
    refresh: vi.fn().mockResolvedValue(undefined),
    logout: vi.fn(),
  } as any);
}

function setInput(element: HTMLElement, value: string) {
  const input = element as HTMLInputElement;
  input.value = value;
  fireEvent.input(input);
  flush();
}

describe("Account page email change", () => {
  beforeEach(() => {
    useSessionMock.mockReset();
    currentUserMock.mockReset();
    requestEmailChangeMock.mockReset();
    confirmEmailChangeMock.mockReset();
    getPendingEmailChangeMock.mockReset();
    resendEmailChangeMock.mockReset();
    cancelEmailChangeMock.mockReset();
    regenerateCalendarUrlMock.mockReset();
    regenerateCalendarUrlMock.mockResolvedValue("https://cal.example/feed.ics");
    getPendingEmailChangeMock.mockResolvedValue(null);
    resendEmailChangeMock.mockResolvedValue({
      pendingEmail: "moved@example.com",
      expiresAt: "2026-11-17T20:00:00Z",
    });
    cancelEmailChangeMock.mockResolvedValue(undefined);
    stubSession();
    currentUserMock.mockResolvedValue(user);
    requestEmailChangeMock.mockResolvedValue({
      pendingEmail: "moved@example.com",
      expiresAt: "2026-11-17T20:00:00Z",
    });
    confirmEmailChangeMock.mockResolvedValue(refreshedUser);
  });

  it("shows the account email from the session", async () => {
    render(() => <Account />);
    await screen.findByTestId("account-email");
    await waitFor(() =>
      expect(screen.getByTestId("account-email").textContent).toBe("basic@example.com"),
    );
  });

  it("renders the Account, Email and Calendar section headings", async () => {
    render(() => <Account />);
    await screen.findByTestId("account-email");
    expect(screen.getByRole("heading", { name: "Account", level: 1 })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Email", level: 2 })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Calendar", level: 2 })).toBeInTheDocument();
  });

  it("regenerates the calendar URL and copies it to the clipboard", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText },
      configurable: true,
    });

    render(() => <Account />);
    await screen.findByTestId("account-email");

    fireEvent.click(screen.getByRole("button", { name: "Regenerate" }));
    flush();
    expect(await screen.findByText("https://cal.example/feed.ics")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Copy" }));
    flush();
    await waitFor(() => expect(writeText).toHaveBeenCalledWith("https://cal.example/feed.ics"));
  });

  it("walks through request, code entry and confirm, then refreshes the session", async () => {
    render(() => <Account />);
    await screen.findByTestId("account-email");

    const emailInput = screen.getByLabelText("New email") as HTMLInputElement;
    setInput(emailInput, "moved@example.com");
    fireEvent.click(screen.getByRole("button", { name: "Send verification code" }));
    flush();

    await waitFor(() => expect(requestEmailChangeMock).toHaveBeenCalledWith("moved@example.com"));

    await screen.findByLabelText("Verification code");
    expect(
      screen.getAllByText(/verification code was sent to moved@example.com/i).length,
    ).toBeGreaterThan(0);

    setInput(screen.getByLabelText("Verification code"), "ABC123");
    fireEvent.click(screen.getByRole("button", { name: "Confirm email change" }));
    flush();

    await waitFor(() => expect(confirmEmailChangeMock).toHaveBeenCalledWith("ABC123"));
    // oxlint-disable-next-line typescript/unbound-method -- vitest mock function reference for assertion
    const refresh = useSessionMock().refresh;
    await waitFor(() => expect(refresh).toHaveBeenCalled());

    await waitFor(() =>
      expect(screen.getByTestId("account-email").textContent).toBe("moved@example.com"),
    );
    expect(screen.queryByLabelText("Verification code")).not.toBeInTheDocument();
  });

  it("shows pending email change persistently and supports resend and cancel", async () => {
    getPendingEmailChangeMock.mockResolvedValue({
      pendingEmail: "pending@example.com",
      expiresAt: "2026-11-17T20:00:00Z",
    });

    render(() => <Account />);

    expect(await screen.findByTestId("pending-email-change")).toBeInTheDocument();
    expect(screen.getByText(/email change pending/i)).toBeInTheDocument();
    expect(screen.getAllByText(/pending@example.com/i).length).toBeGreaterThan(0);
    expect(screen.getByLabelText("Verification code")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Resend code" }));
    flush();
    await waitFor(() => expect(resendEmailChangeMock).toHaveBeenCalled());

    fireEvent.click(screen.getByRole("button", { name: "Cancel email change" }));
    flush();
    await waitFor(() => expect(cancelEmailChangeMock).toHaveBeenCalled());
    await waitFor(() =>
      expect(screen.queryByTestId("pending-email-change")).not.toBeInTheDocument(),
    );
    expect(screen.getByLabelText("New email")).toBeInTheDocument();
  });

  it("surfaces backend errors without leaving the account unchanged", async () => {
    requestEmailChangeMock.mockRejectedValue(
      Object.assign(new Error("user: duplicate email"), { name: "ApiError" }),
    );
    render(() => <Account />);
    await screen.findByTestId("account-email");

    fireEvent.click(screen.getByRole("button", { name: "Send verification code" }));
    flush();

    await screen.findByRole("alert");
    expect(screen.getByRole("alert").textContent).toMatch(/already in use/i);
    expect(screen.getByRole("alert").textContent).not.toContain("user:");
  });
});

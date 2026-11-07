import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { useSession } from "../auth/SessionContext";
import { requestCode } from "../api/auth";
import Login from "./Login";

vi.mock("../api/auth", () => ({ requestCode: vi.fn() }));
vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));

const requestCodeMock = vi.mocked(requestCode);
const useSessionMock = vi.mocked(useSession);

function stubSession(login: () => Promise<void> = vi.fn().mockResolvedValue(undefined)) {
  useSessionMock.mockReturnValue({
    user: null,
    loading: false,
    login,
    logout: vi.fn(),
  });
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
    requestCodeMock.mockReset();
    useSessionMock.mockReset();
    stubSession();
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

  it("shows request-code failures", async () => {
    requestCodeMock.mockRejectedValue(new Error("too many requests"));

    renderLogin();

    await userEvent.type(screen.getByLabelText("Email"), "user@example.com");
    await userEvent.click(screen.getByRole("button", { name: "Request code" }));

    expect(await screen.findByText("too many requests")).toBeInTheDocument();
  });
});

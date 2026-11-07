import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { setToken } from "../api/client";
import { currentUser, verify } from "../api/auth";
import { SessionProvider, useSession } from "./SessionContext";

vi.mock("../api/auth", () => ({
  verify: vi.fn(),
  currentUser: vi.fn(),
}));

const verifyMock = vi.mocked(verify);
const currentUserMock = vi.mocked(currentUser);

function wrapper({ children }: { children: ReactNode }) {
  return <SessionProvider>{children}</SessionProvider>;
}

const user = {
  id: "u1",
  email: "user@example.com",
  role: "basic" as const,
  address: null,
  active: true,
};

describe("useSession", () => {
  beforeEach(() => {
    localStorage.clear();
    verifyMock.mockReset();
    currentUserMock.mockReset();
  });
  afterEach(() => {
    setToken(null);
  });

  it("starts signed out when no token is stored", async () => {
    const { result } = renderHook(() => useSession(), { wrapper });

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.user).toBeNull();
    expect(currentUserMock).not.toHaveBeenCalled();
  });

  it("restores the session from a stored token", async () => {
    setToken("tok");
    currentUserMock.mockResolvedValue(user);

    const { result } = renderHook(() => useSession(), { wrapper });

    await waitFor(() => expect(result.current.user).toEqual(user));
  });

  it("logs in: verifies the code, stores the token and loads the user", async () => {
    verifyMock.mockResolvedValue("tok");
    currentUserMock.mockResolvedValue(user);

    const { result } = renderHook(() => useSession(), { wrapper });
    await waitFor(() => expect(result.current.loading).toBe(false));

    await act(async () => {
      await result.current.login("user@example.com", "ABC123");
    });

    expect(verifyMock).toHaveBeenCalledWith("user@example.com", "ABC123");
    expect(result.current.user).toEqual(user);
    expect(localStorage.getItem("booking.session-token")).toBe("tok");
  });

  it("logs out by clearing the token and the user", async () => {
    setToken("tok");
    currentUserMock.mockResolvedValue(user);

    const { result } = renderHook(() => useSession(), { wrapper });
    await waitFor(() => expect(result.current.user).toEqual(user));

    act(() => {
      result.current.logout();
    });

    expect(result.current.user).toBeNull();
    expect(localStorage.getItem("sauna.session-token")).toBeNull();
  });
});

import { renderHook } from "@solidjs/testing-library";
import { flush } from "solid-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { setToken } from "../api/client";
import { currentUser, qaLogin, verify } from "../api/auth";
import { SessionProvider, useSession } from "./SessionContext";

vi.mock("../api/auth", () => ({
  verify: vi.fn(),
  qaLogin: vi.fn(),
  currentUser: vi.fn(),
}));

const verifyMock = vi.mocked(verify);
const qaLoginMock = vi.mocked(qaLogin);
const currentUserMock = vi.mocked(currentUser);

function wrapper(props: { children: any }) {
  return <SessionProvider>{props.children}</SessionProvider>;
}

const user = {
  id: "u1",
  email: "user@example.com",
  role: "basic" as const,
  address: null,
  active: true,
};

async function settle() {
  await Promise.resolve();
  await Promise.resolve();
  flush();
}

describe("useSession", () => {
  beforeEach(() => {
    localStorage.clear();
    verifyMock.mockReset();
    qaLoginMock.mockReset();
    currentUserMock.mockReset();
  });

  afterEach(() => {
    setToken(null);
  });

  it("starts signed out when no token is stored", async () => {
    const { result } = renderHook(useSession, { wrapper });

    await settle();

    expect(result.loading()).toBe(false);
    expect(result.user()).toBeNull();
    expect(currentUserMock).not.toHaveBeenCalled();
  });

  it("restores the session from a stored token without flashing signed-out state", async () => {
    setToken("tok");
    let resolveUser!: (value: typeof user) => void;
    currentUserMock.mockReturnValue(
      new Promise<typeof user>((resolve) => {
        resolveUser = resolve;
      }),
    );

    const { result } = renderHook(useSession, { wrapper });
    flush();

    expect(result.loading()).toBe(true);
    expect(result.user()).toBeNull();

    resolveUser(user);
    await settle();

    expect(result.loading()).toBe(false);
    expect(result.user()).toEqual(user);
  });

  it("clears an invalid stored token on load", async () => {
    setToken("tok");
    currentUserMock.mockRejectedValue(new Error("unauthorized"));

    const { result } = renderHook(useSession, { wrapper });

    await settle();

    expect(result.loading()).toBe(false);
    expect(result.user()).toBeNull();
    expect(localStorage.getItem("booking.session-token")).toBeNull();
  });

  it("logs in: verifies the code, stores the token and loads the user", async () => {
    verifyMock.mockResolvedValue("tok");
    currentUserMock.mockResolvedValue(user);

    const { result } = renderHook(useSession, { wrapper });
    await settle();

    await result.login("user@example.com", "ABC123");
    await settle();

    expect(verifyMock).toHaveBeenCalledWith("user@example.com", "ABC123");
    expect(result.user()).toEqual(user);
    expect(localStorage.getItem("booking.session-token")).toBe("tok");
  });

  it("logs in with QA mode: stores the token and loads the user", async () => {
    qaLoginMock.mockResolvedValue("tok");
    currentUserMock.mockResolvedValue(user);

    const { result } = renderHook(useSession, { wrapper });
    await settle();

    await result.loginWithQAMode("user@example.com");
    await settle();

    expect(qaLoginMock).toHaveBeenCalledWith("user@example.com");
    expect(result.user()).toEqual(user);
    expect(localStorage.getItem("booking.session-token")).toBe("tok");
  });

  it("logs out by clearing the token and the user", async () => {
    setToken("tok");
    currentUserMock.mockResolvedValue(user);

    const { result } = renderHook(useSession, { wrapper });
    await settle();

    expect(result.user()).toEqual(user);

    result.logout();
    flush();

    expect(result.user()).toBeNull();
    expect(localStorage.getItem("booking.session-token")).toBeNull();
  });

  it("refresh reloads the signed-in user", async () => {
    setToken("tok");
    currentUserMock.mockResolvedValue(user);

    const { result } = renderHook(useSession, { wrapper });
    await settle();

    expect(result.user()).toEqual(user);

    const updated = { ...user, email: "moved@example.com" };
    currentUserMock.mockResolvedValue(updated);

    await result.refresh();
    await settle();

    expect(currentUserMock).toHaveBeenCalled();
    expect(result.user()).toEqual(updated);
  });
});

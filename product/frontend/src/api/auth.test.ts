import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { currentUser, requestCode, verify } from "./auth";

const fetchMock = vi.fn();

function jsonResponse(status: number, body: unknown = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("auth API", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });

  it("requests a code for an email", async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 204 }));

    await requestCode("user@example.com");

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/auth/request-code");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(JSON.stringify({ email: "user@example.com" }));
  });

  it("verifies email + code and returns the session token", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, { token: "tok" }));

    const token = await verify("user@example.com", "ABC123");

    expect(token).toBe("tok");
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/auth/verify");
    expect(init.body).toBe(JSON.stringify({ email: "user@example.com", code: "ABC123" }));
  });

  it("loads the current user", async () => {
    const user = {
      id: "u1",
      email: "user@example.com",
      role: "basic",
      address: "Vägen 1",
      active: true,
    };
    fetchMock.mockResolvedValueOnce(jsonResponse(200, user));

    const me = await currentUser();

    expect(me).toEqual(user);
    expect(fetchMock.mock.calls[0][0]).toBe("/api/users/me");
  });
});

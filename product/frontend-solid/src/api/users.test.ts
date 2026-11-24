import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  addUser,
  changeUserAddress,
  confirmEmailChange,
  listUsers,
  removeUser,
  requestEmailChange,
  type RawUser,
} from "./users";
import type { User } from "./auth";

const fetchMock = vi.fn();

function jsonResponse(status: number, body: unknown = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// The backend emits duplicated snake_case/camelCase keys for timestamps only;
// identity fields share names between both conventions.
const RAW: RawUser = {
  id: "u1",
  email: "basic@example.com",
  role: "basic",
  address: "Sauna Street 1",
  active: true,
};

describe("users API", () => {
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists all registered users", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, [RAW, { ...RAW, id: "u2", role: "super" }]));

    const users = await listUsers();

    expect(fetchMock.mock.calls[0][0]).toBe("/api/users");
    expect(users).toHaveLength(2);
    expect(users[1].role).toBe("super");
    expect(users[0].active).toBe(true);
  });

  it("requests an email change and reports the pending address", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse(202, {
        pendingEmail: "new@example.com",
        pending_email: "new@example.com",
        expiresAt: "2026-11-17T20:00:00Z",
        expires_at: "2026-11-17T20:00:00Z",
      }),
    );

    const pending = await requestEmailChange("new@example.com");

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/users/me/email");
    expect(init.method).toBe("PATCH");
    expect(init.body).toBe(JSON.stringify({ email: "new@example.com" }));
    expect(pending.pendingEmail).toBe("new@example.com");
    expect(pending.expiresAt).toBe("2026-11-17T20:00:00Z");
  });

  it("confirms the email change with the verification code", async () => {
    const updated: User = { ...RAW, email: "new@example.com" };
    fetchMock.mockResolvedValueOnce(jsonResponse(200, updated));

    const user = await confirmEmailChange("123456");

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/users/me/email/confirm");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(JSON.stringify({ code: "123456" }));
    expect(user).toEqual(updated);
  });

  it("adds a basic user (super-user tooling)", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(201, RAW));

    const user = await addUser({ email: "basic@example.com", address: "Sauna Street 1" });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/users");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(
      JSON.stringify({ email: "basic@example.com", address: "Sauna Street 1" }),
    );
    expect(user.id).toBe("u1");
  });

  it("removes a basic user by id", async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 204 }));

    await removeUser("u1");

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/users/u1/remove");
    expect(init.method).toBe("POST");
  });

  it("changes another user's address", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, { ...RAW, address: "Sauna Street 9" }));

    const user = await changeUserAddress("u1", "Sauna Street 9");

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/users/u1/address");
    expect(init.method).toBe("PATCH");
    expect(init.body).toBe(JSON.stringify({ address: "Sauna Street 9" }));
    expect(user.address).toBe("Sauna Street 9");
  });
});

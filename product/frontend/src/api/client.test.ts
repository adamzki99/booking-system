import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiError, getToken, post, request, setToken } from "./client";

const fetchMock = vi.fn();

function jsonResponse(status: number, body: unknown = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("API client", () => {
  beforeEach(() => {
    localStorage.clear();
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });

  it("sends GET requests and parses JSON responses", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, { email: "a@b.se" }));

    const result = await request<{ email: string }>("/api/users/me");

    expect(result).toEqual({ email: "a@b.se" });
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/users/me",
      expect.objectContaining({ body: undefined, headers: expect.any(Headers) }),
    );
  });

  it("attaches the stored bearer token", async () => {
    setToken("token-123");
    fetchMock.mockResolvedValueOnce(jsonResponse(200, {}));

    await request("/api/users/me");

    const headers = new Headers(fetchMock.mock.calls[0][1].headers);
    expect(headers.get("Authorization")).toBe("Bearer token-123");
    expect(getToken()).toBe("token-123");
  });

  it("posts JSON bodies with a content-type header", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(null, { status: 204 }),
    );

    await post("/api/auth/request-code", { email: "a@b.se" });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/auth/request-code");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(JSON.stringify({ email: "a@b.se" }));
    expect(new Headers(init.headers).get("Content-Type")).toBe(
      "application/json",
    );
  });

  it("throws an ApiError carrying the backend error message", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(409, { error: "double booking" }));

    const error = await request("/api/bookings", { method: "POST" }).then(
      () => null,
      (err: unknown) => err,
    );
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).message).toBe("double booking");
    expect((error as ApiError).status).toBe(409);
  });

  it("falls back to the status text when the body is not JSON", async () => {
    fetchMock.mockResolvedValueOnce(
      new Response("unauthorized", { status: 401, statusText: "Unauthorized" }),
    );

    await expect(request("/api/bookings")).rejects.toMatchObject({
      message: "Unauthorized", // statusText from the Response object
      status: 401,
    });
  });
});

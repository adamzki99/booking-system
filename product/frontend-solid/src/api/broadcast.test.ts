import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { broadcastMessage } from "./broadcast";

const fetchMock = vi.fn();

describe("broadcast API", () => {
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("sends subject and body to all basic users", async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 202 }));

    await broadcastMessage({ subject: "Closed", body: "The sauna is closed." });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/broadcast");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(
      JSON.stringify({ subject: "Closed", body: "The sauna is closed." }),
    );
  });
});

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { regenerateCalendarUrl } from "./calendar";

const fetchMock = vi.fn();

function jsonResponse(status: number, body: unknown = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("calendar API", () => {
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("regenerates the calendar feed URL", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse(200, { url: "https://sauna.example/calendar/tok123.ics" }),
    );

    const url = await regenerateCalendarUrl();

    const [endpoint, init] = fetchMock.mock.calls[0];
    expect(endpoint).toBe("/api/account/calendar-token");
    expect(init.method).toBe("POST");
    expect(url).toBe("https://sauna.example/calendar/tok123.ics");
  });
});

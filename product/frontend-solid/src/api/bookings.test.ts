import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cancelBooking, createBooking, listBookings } from "./bookings";

const fetchMock = vi.fn();

function jsonResponse(status: number, body: unknown = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const START = "2026-11-08T08:00:00Z";
const END = "2026-11-08T09:00:00Z";

describe("bookings API", () => {
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists bookings and normalizes the owner id", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse(200, [
        { id: "b1", user_id: "u1", start: START, end: END, status: "active" },
        { id: "b2", userId: "u2", start: END, end: START, status: "active" },
      ]),
    );

    const bookings = await listBookings();

    expect(fetchMock.mock.calls[0][0]).toBe("/api/bookings");
    expect(bookings).toHaveLength(2);
    expect(bookings[0].userId).toBe("u1");
    expect(bookings[1].userId).toBe("u2");
  });

  it("creates a booking from start/end instants", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, { id: "b3", user_id: "u1", start: START, end: END, status: "active" }),
    );

    const booking = await createBooking({ start: START, end: END });

    expect(booking.id).toBe("b3");
    expect(booking.userId).toBe("u1");
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/bookings");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(JSON.stringify({ start: START, end: END }));
  });

  it("cancels a booking by id", async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 204 }));

    await cancelBooking("b1");

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/bookings/b1/cancel");
    expect(init.method).toBe("POST");
  });
});

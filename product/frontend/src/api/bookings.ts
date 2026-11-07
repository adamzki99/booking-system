import { get, post } from "./client";
import type { Booking } from "./auth";

interface RawBooking {
  id: string;
  user_id?: string;
  userId?: string;
  start: string;
  end: string;
  status: Booking["status"];
  created_at?: string;
  createdAt?: string;
  cancelled_at?: string;
  cancelledAt?: string;
}

/** The backend emits duplicated snake_case/camelCase keys; normalize them. */
function normalize(raw: RawBooking): Booking {
  return {
    ...raw,
    userId: raw.userId ?? raw.user_id ?? "",
    createdAt: raw.createdAt ?? raw.created_at,
    cancelledAt: raw.cancelledAt ?? raw.cancelled_at,
  };
}

/** Lists bookings, optionally limited to an RFC3339 interval. */
export function listBookings(range?: { from?: string; to?: string }): Promise<Booking[]> {
  const params = new URLSearchParams();
  if (range?.from) params.set("from", range.from);
  if (range?.to) params.set("to", range.to);
  const query = params.toString();
  const url = query ? `/api/bookings?${query}` : "/api/bookings";
  return get<RawBooking[]>(url).then((list) => list.map(normalize));
}

/** Creates a booking for a start/end interval (RFC3339 instants). */
export function createBooking(interval: { start: string; end: string }): Promise<Booking> {
  return post<RawBooking>("/api/bookings", interval).then(normalize);
}

/** Cancels a booking (own bookings for basic users, any for super users). */
export function cancelBooking(id: string): Promise<void> {
  return post(`/api/bookings/${encodeURIComponent(id)}/cancel`);
}

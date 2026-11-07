import { useCallback, useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import { errorMessage } from "../api/client";
import type { Booking, User } from "../api/auth";
import { cancelBooking, createBooking, listBookings } from "../api/bookings";
import { useSession } from "../auth/SessionContext";

function canCancel(user: User | null, booking: Booking): boolean {
  if (!user) return false;
  if (user.role === "super" || user.role === "admin") return true;
  return booking.userId === user.id;
}

/** Formats a booking interval in local time, "2026-11-08 08:00 – 09:00". */
function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function formatInstant(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function formatInterval(start: string, end: string): string {
  const s = formatInstant(new Date(start));
  const e = formatInstant(new Date(end));
  // Same day: show the end time only.
  return s.slice(0, 10) === e.slice(0, 10) ? `${s} – ${e.slice(-5)}` : `${s} – ${e}`;
}

/** Happy flow steps 4–6: view bookings, create a booking, cancel own bookings. */
export default function Calendar() {
  const { user } = useSession();
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");

  const refresh = useCallback(async () => {
    try {
      const list = await listBookings();
      list.sort((a, b) => a.start.localeCompare(b.start));
      setBookings(list);
      setError(null);
    } catch (err) {
      setError(errorMessage(err, "could not load bookings"));
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    try {
      await createBooking({
        start: new Date(start).toISOString(),
        end: new Date(end).toISOString(),
      });
      setStart("");
      setEnd("");
      setError(null);
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not create booking"));
    }
  }

  async function onCancel(id: string) {
    try {
      await cancelBooking(id);
      setError(null);
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not cancel booking"));
    }
  }

  const canSubmit = useMemo(() => start !== "" && end !== "", [start, end]);

  return (
    <main>
      <h1>Booking calendar</h1>
      <section>
        <h2>Create booking</h2>
        <form onSubmit={onSubmit}>
          <label>
            Start
            <input
              type="datetime-local"
              value={start}
              onChange={(e) => setStart(e.target.value)}
              required
            />
          </label>
          <label>
            End
            <input
              type="datetime-local"
              value={end}
              onChange={(e) => setEnd(e.target.value)}
              required
            />
          </label>
          <button type="submit" disabled={!canSubmit}>
            Create booking
          </button>
        </form>
      </section>
      <section>
        <h2>Bookings</h2>
        {error && <p role="alert">{error}</p>}
        {error === null && bookings.length === 0 && <p>No bookings yet.</p>}
        <ul>
          {bookings.map((booking) => (
            <li key={booking.id}>
              <time dateTime={booking.start}>
                {formatInterval(booking.start, booking.end)}
              </time>{" "}
              {canCancel(user, booking) && (
                <button type="button" onClick={() => void onCancel(booking.id)}>
                  Cancel booking
                </button>
              )}
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}

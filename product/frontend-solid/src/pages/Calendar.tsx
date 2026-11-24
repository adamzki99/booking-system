import { For, Show, createEffect, createSignal } from "solid-js";
import { Errored, Loading, action, createAsyncData, isPending, refresh } from "../data";
import type { Booking, User } from "../api/auth";
import { cancelBooking, createBooking, listBookings } from "../api/bookings";
import { listUsers } from "../api/users";
import { useSession } from "../auth/SessionContext";
import Alert from "../ui/Alert";
import Avatar from "../ui/Avatar";
import Button from "../ui/Button";
import Card from "../ui/Card";
import CardBody from "../ui/CardBody";
import CardHeader from "../ui/CardHeader";
import Input from "../ui/Input";
import PageHeader from "../components/PageHeader";
import Select from "../ui/Select";
import { errorMessage } from "../api/client";
import "./Calendar.css";

function canCancel(user: User | null, booking: Booking): boolean {
  if (!user) return false;
  if (user.role === "super" || user.role === "admin") return true;
  return booking.userId === user.id;
}

/** Formats a booking interval in local time, "2026-11-08 08:00 - 09:00". */
function pad(n: number): string {
  return String(n).padStart(2, "0");
}

const WEEKDAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const WEEKDAYS_LONG = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];
const MONTHS_LONG = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

export function addWeeks(d: Date, weeks: number): Date {
  const clone = new Date(d.getTime());
  clone.setDate(clone.getDate() + 7 * weeks);
  return clone;
}

export function formatPageDate(d: Date): string {
  return `${WEEKDAYS_LONG[d.getDay()]}, ${d.getDate()} ${MONTHS_LONG[d.getMonth()]} ${d.getFullYear()}`;
}

export function formatDayLabel(start: string | Date): string {
  const d = typeof start === "string" ? new Date(start) : start;
  const today = new Date();
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const sameDay = (a: Date, b: Date) =>
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate();
  if (sameDay(d, today)) return "Today";
  if (sameDay(d, tomorrow)) return "Tomorrow";
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(d);
}

function formatTimeRange(start: string, end: string): string {
  const s = new Date(start);
  const e = new Date(end);
  return `${pad(s.getHours())}:${pad(s.getMinutes())} - ${pad(e.getHours())}:${pad(e.getMinutes())}`;
}

function memberLabel(user: User | undefined, _booking: Booking): string {
  return user?.address ?? "Member";
}

function formatTime(d: Date): string {
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function formatSlot(start: Date, end?: Date): string {
  const e = end ?? new Date(start.getTime() + 60 * 60 * 1000);
  return `${WEEKDAYS_SHORT[start.getDay()]}, ${formatTime(start)} - ${formatTime(e)}`;
}

export function formatSummary(start: Date, end?: Date): string {
  const e = end ?? new Date(start.getTime() + 60 * 60 * 1000);
  return `1 new booking · ${formatDayLabel(start)}, ${formatTime(start)} - ${formatTime(e)}`;
}

interface CalendarData {
  bookings: Booking[];
  members: Record<string, User>;
}

/**
 * Calendar page: view bookings, create a booking, quick-repeat, and cancel own
 * bookings. Async data loads under Loading/Errored. Mutations use action with
 * yield + refresh. No optimistic updates were found in current page behavior
 * (documented "not found").
 */
export default function Calendar() {
  const session = useSession();
  const wantsCreate = new URLSearchParams(window.location.search).has("create");

  const [createError, setCreateError] = createSignal<string | null>(null);
  const [createSuccess, setCreateSuccess] = createSignal<string | null>(null);
  const [listError, setListError] = createSignal<string | null>(null);
  const [showAll, setShowAll] = createSignal(false);
  const [start, setStart] = createSignal("");
  const [end, setEnd] = createSignal("");
  const [sourceId, setSourceId] = createSignal("");
  const [selectedWeeks, setSelectedWeeks] = createSignal("");
  const [createBusy, setCreateBusy] = createSignal(false);
  const [quickBusy, setQuickBusy] = createSignal(false);

  const data = createAsyncData<CalendarData>(async () => {
    const bookings = await listBookings();
    bookings.sort((a, b) => a.start.localeCompare(b.start));
    let members: Record<string, User> = {};
    try {
      const users = await listUsers();
      for (const u of users) members[u.id] = u;
    } catch {
      // Best effort: leave the map empty on failure.
    }
    return { bookings, members };
  });

  function currentBookings(): Booking[] {
    return (data() as CalendarData | undefined)?.bookings ?? [];
  }

  function currentMembers(): Record<string, User> {
    return (data() as CalendarData | undefined)?.members ?? {};
  }

  function selectedSource(): Booking | null {
    const bookings = currentBookings();
    const id = sourceId();
    return bookings.find((b) => b.id === id) ?? (bookings.length ? bookings[0] : null);
  }

  function targetStart(): Date | null {
    const src = selectedSource();
    const weeks = selectedWeeks();
    if (!src || !weeks) return null;
    return addWeeks(new Date(src.start), Number(weeks));
  }

  function targetEnd(): Date | null {
    const src = selectedSource();
    const weeks = selectedWeeks();
    if (!src || !weeks) return null;
    return addWeeks(new Date(src.end), Number(weeks));
  }

  function canSubmit(): boolean {
    return start() !== "" && end() !== "" && !createBusy();
  }

  // Default source booking to first available when data loads/changes.
  createEffect(
    () => {
      if (isPending(data)) return undefined;
      const bookings = currentBookings();
      if (!sourceId() && bookings.length > 0) return bookings[0].id;
      return undefined;
    },
    (id) => {
      if (id) setSourceId(id);
    },
  );

  // Focus create form when opened with ?create=1.
  let createFocusDone = false;
  createEffect(
    () => {
      if (!wantsCreate || createFocusDone || isPending(data)) return false;
      return true;
    },
    (ready) => {
      if (!ready || createFocusDone) return;
      createFocusDone = true;
      queueMicrotask(() => {
        const el = document.getElementById("start") as HTMLInputElement | null;
        el?.focus();
      });
    },
  );

  // oxlint-disable-next-line solid/reactivity -- action handler reads signals only on user invocation
  const submitCreate = action(function* (event: Event) {
    event.preventDefault();
    setCreateError(null);
    setCreateSuccess(null);
    const startVal = start();
    const endVal = end();
    if (!startVal || !endVal) {
      setCreateError("Choose both a start and end time for the booking.");
      return;
    }
    const startDate = new Date(startVal);
    const endDate = new Date(endVal);
    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
      setCreateError("Enter valid start and end times.");
      return;
    }
    if (endDate <= startDate) {
      setCreateError("The end time must be after the start time.");
      return;
    }
    setCreateBusy(true);
    try {
      yield createBooking({
        start: startDate.toISOString(),
        end: endDate.toISOString(),
      });
      setStart("");
      setEnd("");
      setCreateSuccess("Booking created.");
      setListError(null);
      yield refresh(data);
    } catch (err) {
      setCreateError(errorMessage(err, "Could not create the booking. Please try again."));
    } finally {
      setCreateBusy(false);
    }
  });

  // oxlint-disable-next-line solid/reactivity -- action handler reads signals only on user invocation
  const submitQuickBook = action(function* () {
    const src = selectedSource();
    const weeks = selectedWeeks();
    if (!src || !weeks) return;
    const newStart = addWeeks(new Date(src.start), Number(weeks));
    const newEnd = addWeeks(new Date(src.end), Number(weeks));
    setCreateError(null);
    setCreateSuccess(null);
    setQuickBusy(true);
    try {
      yield createBooking({
        start: newStart.toISOString(),
        end: newEnd.toISOString(),
      });
      setCreateSuccess("Booking created.");
      setListError(null);
      yield refresh(data);
    } catch (err) {
      setCreateError(errorMessage(err, "Could not create the booking. Please try again."));
    } finally {
      setQuickBusy(false);
    }
  });

  const submitCancel = action(function* (id: string) {
    try {
      yield cancelBooking(id);
      setListError(null);
      yield refresh(data);
    } catch (err) {
      setListError(errorMessage(err, "Could not cancel the booking."));
    }
  });

  return (
    <div class="calendar-page">
      <div class="calendar-stack">
        <PageHeader title="Bookings" subtitle={formatPageDate(new Date())} />

        <Loading fallback={<p class="calendar-loading">Loading bookings...</p>}>
          <Errored
            fallback={(err, reset) => (
              <Alert status="error">
                <div class="calendar-error-fallback">
                  <span>{errorMessage(err, "Could not load bookings.")}</span>
                  <Button variant="accentOutline" size="sm" onClick={() => reset()}>
                    Retry
                  </Button>
                </div>
              </Alert>
            )}
          >
            <section class="ui-card calendar-card" aria-label="Quick book">
              <CardBody>
                <h2 class="calendar-section-title">Quick book</h2>
                <p class="calendar-muted calendar-section-desc">
                  Repeat a booking on the same day and time in another week.
                </p>
                <div class="calendar-form-stack">
                  <div class="calendar-field">
                    {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                    <label class="calendar-label" for="qb-src">
                      Booking to repeat
                    </label>
                    <Select
                      id="qb-src"
                      value={sourceId()}
                      onInput={(e) => setSourceId(e.currentTarget.value)}
                      disabled={currentBookings().length === 0}
                    >
                      <Show
                        when={currentBookings().length > 0}
                        fallback={<option value="">No bookings to repeat</option>}
                      >
                        <For each={currentBookings()} keyed={(b) => b.id}>
                          {(b) => (
                            <option value={b().id}>
                              {formatSlot(new Date(b().start), new Date(b().end))}
                            </option>
                          )}
                        </For>
                      </Show>
                    </Select>
                  </div>

                  <fieldset class="calendar-fieldset">
                    <legend class="calendar-label">Repeat on</legend>
                    <div class="calendar-repeat-grid">
                      <For each={[1, 2, 3, 4]} keyed={(w) => w}>
                        {(w) => {
                          const week = () => w();
                          const src = () => selectedSource();
                          const base = () => {
                            const s = src();
                            return s ? new Date(s.start) : new Date();
                          };
                          const target = () => addWeeks(base(), week());
                          const label = () => formatDayLabel(target());
                          const value = () => String(week());
                          const checked = () => selectedWeeks() === value();
                          const disabled = () => currentBookings().length === 0;
                          return (
                            <label class="calendar-repeat-chip">
                              <input
                                type="radio"
                                name="repeat-weeks"
                                value={value()}
                                checked={checked()}
                                disabled={disabled()}
                                aria-label={label()}
                                onChange={(e) => setSelectedWeeks(e.currentTarget.value)}
                              />
                              <span class="calendar-repeat-chip-label">{label()}</span>
                            </label>
                          );
                        }}
                      </For>
                    </div>
                  </fieldset>

                  <Show when={targetStart() && targetEnd()}>
                    <div class="calendar-summary">
                      <p class="calendar-summary-text">
                        {formatSummary(targetStart()!, targetEnd()!)}
                      </p>
                    </div>
                  </Show>

                  <Button
                    variant="accent"
                    onClick={() => void submitQuickBook()}
                    disabled={
                      currentBookings().length === 0 ||
                      !selectedSource() ||
                      !selectedWeeks() ||
                      quickBusy()
                    }
                  >
                    {quickBusy() ? "Quick booking..." : "Quick book"}
                  </Button>
                </div>
              </CardBody>
            </section>

            <Card class="calendar-card">
              <CardBody>
                <h2 class="calendar-section-title">Create booking</h2>
                <form class="calendar-form-stack" onSubmit={submitCreate} novalidate>
                  <Show when={createError()}>{(msg) => <Alert status="error">{msg()}</Alert>}</Show>
                  <Show when={createSuccess()}>
                    {(msg) => <output class="ui-alert ui-alert--success">{msg()}</output>}
                  </Show>
                  <div class="calendar-field">
                    {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                    <label class="calendar-label" for="start">
                      Start
                    </label>
                    <Input
                      ref={(el) => {
                        if (wantsCreate) el.focus();
                      }}
                      id="start"
                      type="datetime-local"
                      autofocus={wantsCreate}
                      value={start()}
                      onInput={(e) => {
                        setStart(e.currentTarget.value);
                        setCreateError(null);
                        setCreateSuccess(null);
                      }}
                    />
                  </div>
                  <div class="calendar-field">
                    {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                    <label class="calendar-label" for="end">
                      End
                    </label>
                    <Input
                      id="end"
                      type="datetime-local"
                      value={end()}
                      onInput={(e) => {
                        setEnd(e.currentTarget.value);
                        setCreateError(null);
                        setCreateSuccess(null);
                      }}
                    />
                  </div>
                  <Button
                    type="submit"
                    variant="accent"
                    class="calendar-create-submit"
                    disabled={!canSubmit()}
                  >
                    {createBusy() ? "Creating..." : "Create booking"}
                  </Button>
                </form>
              </CardBody>
            </Card>

            <section class="ui-card calendar-card" aria-label="Upcoming bookings">
              <CardHeader>
                <h2 class="calendar-section-title">Upcoming bookings</h2>
              </CardHeader>
              <CardBody>
                <Show when={listError()}>{(msg) => <Alert status="error">{msg()}</Alert>}</Show>
                <Show when={listError() === null && currentBookings().length === 0}>
                  <p class="calendar-muted">No bookings yet.</p>
                </Show>

                <div class="calendar-table-head" aria-hidden="true">
                  <span class="calendar-th">Member</span>
                  <span class="calendar-th">Date and time</span>
                  <span class="calendar-th calendar-th-action" />
                </div>

                <ul class="calendar-booking-list">
                  <For
                    each={showAll() ? currentBookings() : currentBookings().slice(0, 5)}
                    keyed={(b) => b.id}
                  >
                    {(booking) => {
                      const b = () => booking();
                      const member = () => currentMembers()[b().userId];
                      const label = () => memberLabel(member(), b());
                      return (
                        <li class="calendar-booking-item">
                          <div class="calendar-booking-row">
                            <div class="calendar-booking-member">
                              <Avatar size="sm" name={label()} />
                              <span>{label()}</span>
                            </div>
                            <time class="calendar-booking-time" datetime={b().start}>
                              <span class="calendar-booking-day">{formatDayLabel(b().start)}</span>
                              <span class="calendar-booking-range calendar-muted">
                                {formatTimeRange(b().start, b().end)}
                              </span>
                            </time>
                            <div class="calendar-booking-action">
                              <Show when={canCancel(session.user(), b())}>
                                <Button
                                  size="sm"
                                  variant="accentOutline"
                                  class="calendar-cancel-btn"
                                  onClick={() => void submitCancel(b().id)}
                                >
                                  Cancel booking
                                </Button>
                              </Show>
                            </div>
                          </div>
                        </li>
                      );
                    }}
                  </For>
                </ul>

                <Show when={currentBookings().length > 5}>
                  <Button
                    variant="accentOutline"
                    class="calendar-toggle-btn"
                    onClick={() => setShowAll((v) => !v)}
                  >
                    {showAll() ? "Show fewer bookings" : "View all bookings"}
                  </Button>
                </Show>
              </CardBody>
            </section>
          </Errored>
        </Loading>
      </div>
    </div>
  );
}

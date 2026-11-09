import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "../test-utils";
import type { Booking } from "../api/auth";
import { cancelBooking, createBooking, listBookings } from "../api/bookings";
import { useSession } from "../auth/SessionContext";
import Calendar from "./Calendar";

vi.mock("../api/bookings", () => ({
  listBookings: vi.fn(),
  createBooking: vi.fn(),
  cancelBooking: vi.fn(),
}));
vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));

const listMock = vi.mocked(listBookings);
const createMock = vi.mocked(createBooking);
const cancelMock = vi.mocked(cancelBooking);
const useSessionMock = vi.mocked(useSession);

function booking(id: string, userId: string, start: string): Booking {
  return { id, userId, start, end: start, status: "active" };
}

function stubSession(id: string) {
  useSessionMock.mockReturnValue({
    user: { id, email: "user@example.com", role: "basic", address: null, active: true },
    loading: false,
    login: vi.fn(),
    logout: vi.fn(),
  });
}

describe("Calendar page", () => {
  beforeEach(() => {
    listMock.mockReset();
    createMock.mockReset();
    cancelMock.mockReset();
    useSessionMock.mockReset();
    stubSession("u1");
  });

  it("lists bookings sorted by start time", async () => {
    listMock.mockResolvedValue([
      booking("b1", "u1", "2026-11-08T08:00:00Z"),
      booking("b2", "u2", "2026-11-09T10:00:00Z"),
      booking("b3", "u2", "2026-11-07T12:00:00Z"),
    ]);

    render(<Calendar />);

    await screen.findByRole("list");
    const times = screen
      .getAllByRole("listitem")
      .map((item) => item.querySelector("time")?.getAttribute("datetime"));
    expect(times).toEqual([
      "2026-11-07T12:00:00Z",
      "2026-11-08T08:00:00Z",
      "2026-11-09T10:00:00Z",
    ]);
  });

  it("creates a booking from the form values and shows it after refresh", async () => {
    listMock
      .mockResolvedValueOnce([])
      .mockResolvedValue([booking("b1", "u1", "2026-11-08T08:00:00Z")]);
    createMock.mockResolvedValue(booking("b1", "u1", "2026-11-08T08:00:00Z"));

    render(<Calendar />);

    await userEvent.type(screen.getByLabelText("Start"), "2026-11-08T08:00");
    await userEvent.type(screen.getByLabelText("End"), "2026-11-08T09:00");
    await userEvent.click(screen.getByRole("button", { name: "Create booking" }));

    await waitFor(() =>
      expect(createMock).toHaveBeenCalledWith({
        start: expect.stringMatching(/^2026-11-08T08:00/),
        end: expect.stringMatching(/^2026-11-08T09:00/),
      }),
    );
    // The refreshed list shows the new own booking with a cancel control.
    expect(await screen.findByRole("button", { name: "Cancel booking" })).toBeInTheDocument();
    expect(listMock).toHaveBeenCalledTimes(2);
  });

  it("enables creation only with a complete interval", async () => {
    listMock.mockResolvedValue([]);

    render(<Calendar />);

    expect(
      await screen.findByRole("button", { name: "Create booking" }),
    ).toBeDisabled();

    await userEvent.type(screen.getByLabelText("Start"), "2026-11-08T08:00");
    expect(screen.getByRole("button", { name: "Create booking" })).toBeDisabled();
  });

  it("lets the user cancel their own bookings only", async () => {
    listMock.mockResolvedValue([
      booking("b1", "u1", "2026-11-08T08:00:00Z"),
      booking("b2", "u2", "2026-11-09T10:00:00Z"),
    ]);
    cancelMock.mockResolvedValue(undefined);

    render(<Calendar />);

    // Only one cancel control exists: for the signed-in user's own booking.
    expect(
      await screen.findByRole("button", { name: "Cancel booking" }),
    ).toBeInTheDocument();
    expect(screen.getAllByRole("button", { name: "Cancel booking" })).toHaveLength(1);

    await userEvent.click(screen.getByRole("button", { name: "Cancel booking" }));
    await waitFor(() => expect(cancelMock).toHaveBeenCalledWith("b1"));
  });
});

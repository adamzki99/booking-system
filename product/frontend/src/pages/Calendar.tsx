import { useCallback, useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import {
  Alert,
  AlertIcon,
  Box,
  Button,
  Flex,
  FormControl,
  FormLabel,
  Heading,
  Input,
  List,
  ListItem,
  Text,
  VStack,
} from "@chakra-ui/react";
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
    <Box as="main">
      <VStack spacing={6} align="stretch">
        <Heading as="h1" size="lg">
          Booking calendar
        </Heading>
        <Box as="section">
          <Heading as="h2" size="md" mb={3}>
            Create booking
          </Heading>
          <Box as="form" onSubmit={onSubmit}>
            <VStack spacing={4} align="stretch">
              <FormControl>
                <FormLabel htmlFor="start">Start</FormLabel>
                <Input
                  id="start"
                  type="datetime-local"
                  value={start}
                  onChange={(e) => setStart(e.target.value)}
                />
              </FormControl>
              <FormControl>
                <FormLabel htmlFor="end">End</FormLabel>
                <Input
                  id="end"
                  type="datetime-local"
                  value={end}
                  onChange={(e) => setEnd(e.target.value)}
                />
              </FormControl>
              <Button type="submit" alignSelf="flex-start" isDisabled={!canSubmit}>
                Create booking
              </Button>
            </VStack>
          </Box>
        </Box>
        <Box as="section">
          <Heading as="h2" size="md" mb={3}>
            Bookings
          </Heading>
          {error && (
            <Alert status="error" role="alert" mb={3}>
              <AlertIcon />
              {error}
            </Alert>
          )}
          {error === null && bookings.length === 0 && (
            <Text color="gray.600">No bookings yet.</Text>
          )}
          <List spacing={2} role="list">
            {bookings.map((booking) => (
              <ListItem
                key={booking.id}
                role="listitem"
                borderWidth="1px"
                borderRadius="base"
                p={3}
              >
                <Flex justify="space-between" align="center" gap={3}>
                  <Box as="time" dateTime={booking.start}>
                    {formatInterval(booking.start, booking.end)}
                  </Box>
                  {canCancel(user, booking) && (
                    <Button
                      size="sm"
                      colorScheme="red"
                      variant="outline"
                      onClick={() => void onCancel(booking.id)}
                    >
                      Cancel booking
                    </Button>
                  )}
                </Flex>
              </ListItem>
            ))}
          </List>
        </Box>
      </VStack>
    </Box>
  );
}

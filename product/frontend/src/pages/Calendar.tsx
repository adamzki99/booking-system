import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FormEvent } from "react";
import {
  Alert,
  AlertIcon,
  Box,
  Button,
  Card,
  CardBody,
  Flex,
  FormControl,
  FormLabel,
  Heading,
  Input,
  List,
  ListItem,
  Select,
  SimpleGrid,
  Text,
  VStack,
  useRadio,
  useRadioGroup,
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
const MONTHS_SHORT = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

export function addWeeks(d: Date, weeks: number): Date {
  const clone = new Date(d.getTime());
  clone.setDate(clone.getDate() + 7 * weeks);
  return clone;
}

export function formatPageDate(d: Date): string {
  return `${WEEKDAYS_LONG[d.getDay()]}, ${d.getDate()} ${MONTHS_LONG[d.getMonth()]} ${d.getFullYear()}`;
}

export function formatDayLabel(d: Date): string {
  return `${WEEKDAYS_SHORT[d.getDay()]} ${d.getDate()} ${MONTHS_SHORT[d.getMonth()]}`;
}

function formatTime(d: Date): string {
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function formatSlot(start: Date, end?: Date): string {
  const e = end ?? new Date(start.getTime() + 60 * 60 * 1000);
  return `${WEEKDAYS_SHORT[start.getDay()]}, ${formatTime(start)} – ${formatTime(e)}`;
}

export function formatSummary(start: Date, end?: Date): string {
  const e = end ?? new Date(start.getTime() + 60 * 60 * 1000);
  return `1 new booking · ${formatDayLabel(start)}, ${formatTime(start)} – ${formatTime(e)}`;
}

function RepeatChip(props: any) {
  const { getInputProps, getRadioProps } = useRadio(props);
  const input = getInputProps();
  const radio = getRadioProps();
  return (
    <Box as="label" cursor="pointer">
      <input {...input} aria-label={props["aria-label"]} />
      <Box
        {...radio}
        px={3}
        py={2}
        borderWidth="1px"
        borderRadius="md"
        textAlign="center"
        fontSize="sm"
        _checked={{
          bg: "#F6E6E0",
          borderColor: "#9A2F22",
          color: "#7A241A",
          fontWeight: "bold",
        }}
      >
        {props.children}
      </Box>
    </Box>
  );
}

/** Happy flow steps 4–6: view bookings, create a booking, cancel own bookings. */
export default function Calendar() {
  const { user } = useSession();
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const startRef = useRef<HTMLInputElement>(null);

  const [sourceId, setSourceId] = useState("");
  const [selectedWeeks, setSelectedWeeks] = useState("");

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

  // Default the source booking to the first available booking.
  useEffect(() => {
    if (!sourceId && bookings.length > 0) {
      setSourceId(bookings[0].id);
    }
  }, [bookings, sourceId]);

  // The shell's "Create booking" CTA lands here with ?create=1; focus the
  // creation form so the flow is ready to use without another click.
  useEffect(() => {
    if (new URLSearchParams(window.location.search).has("create")) {
      startRef.current?.focus();
    }
  }, []);

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

  const selectedSource = useMemo(
    () => bookings.find((b) => b.id === sourceId) ?? (bookings.length ? bookings[0] : null),
    [bookings, sourceId],
  );

  const { getRadioProps } = useRadioGroup({
    name: "repeat-weeks",
    value: selectedWeeks,
    onChange: setSelectedWeeks,
  });

  async function onQuickBook() {
    if (!selectedSource || !selectedWeeks) return;
    const weeks = Number(selectedWeeks);
    const newStart = addWeeks(new Date(selectedSource.start), weeks);
    const newEnd = addWeeks(new Date(selectedSource.end), weeks);
    try {
      await createBooking({
        start: newStart.toISOString(),
        end: newEnd.toISOString(),
      });
      setError(null);
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not create booking"));
    }
  }

  const targetStart =
    selectedSource && selectedWeeks
      ? addWeeks(new Date(selectedSource.start), Number(selectedWeeks))
      : null;
  const targetEnd =
    selectedSource && selectedWeeks
      ? addWeeks(new Date(selectedSource.end), Number(selectedWeeks))
      : null;

  const disabled = bookings.length === 0;

  return (
    <Box as="main" maxW="1040px" mx="auto">
      <VStack spacing={6} align="stretch">
        <Box>
          <Heading as="h1" size="lg">
            Bookings
          </Heading>
          <Text color="gray.600">{formatPageDate(new Date())}</Text>
        </Box>

        <Card as="section" aria-label="Quick book">
          <CardBody>
            <Heading as="h2" size="md" mb={1}>
              Quick book
            </Heading>
            <Text color="gray.600" mb={3}>
              Repeat a booking on the same day and time in another week.
            </Text>
            <VStack spacing={4} align="stretch">
              <FormControl isDisabled={disabled}>
                <FormLabel htmlFor="qb-src">Booking to repeat</FormLabel>
                <Select
                  id="qb-src"
                  value={sourceId}
                  onChange={(e) => setSourceId(e.target.value)}
                  isDisabled={disabled}
                  placeholder={disabled ? "No bookings to repeat" : "Choose a booking"}
                >
                  {bookings.map((b) => (
                    <option key={b.id} value={b.id}>
                      {formatSlot(new Date(b.start), new Date(b.end))}
                    </option>
                  ))}
                </Select>
              </FormControl>

              <Box as="fieldset" border="none" p={0} m={0}>
                <FormLabel as="legend">Repeat on</FormLabel>
                <SimpleGrid columns={{ base: 2, sm: 4 }} spacing={2}>
                  {[1, 2, 3, 4].map((w) => {
                    const src = selectedSource ? new Date(selectedSource.start) : new Date();
                    const target = addWeeks(src, w);
                    const radioProps = getRadioProps({
                      value: String(w),
                      isDisabled: disabled,
                    });
                    return (
                      <RepeatChip key={w} {...radioProps} aria-label={formatDayLabel(target)}>
                        {formatDayLabel(target)}
                      </RepeatChip>
                    );
                  })}
                </SimpleGrid>
              </Box>

              {targetStart && targetEnd && (
                <Box bg="#FBF8F4" borderRadius="10px" p={3}>
                  <Text fontSize="sm">
                    {formatSummary(targetStart, targetEnd)}
                  </Text>
                </Box>
              )}

              <Button
                colorScheme="teal"
                onClick={() => void onQuickBook()}
                isDisabled={disabled || !selectedSource || !selectedWeeks}
              >
                Quick book
              </Button>
            </VStack>
          </CardBody>
        </Card>

        <Card>
          <CardBody>
            <Heading as="h2" size="md" mb={3}>
              Create booking
            </Heading>
            <Box as="form" onSubmit={onSubmit}>
              <VStack spacing={4} align="stretch">
                <FormControl>
                  <FormLabel htmlFor="start">Start</FormLabel>
                  <Input
                    ref={startRef}
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
          </CardBody>
        </Card>

        <Box as="section">
          <Heading as="h2" size="md" mb={3}>
            All bookings
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
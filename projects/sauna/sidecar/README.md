# Sauna sidecar

The sauna-specific components of the booking system, separated from the generic
product so the product can be reused for other booking applications.

- Runs as its own container in the docker compose cluster.
- Communicates via a REST API (called by the product backend).
- **Stateless:** it only performs functions — no state is kept here.

## Endpoints

- `GET /healthz` — liveness check.
- `POST /functions/echo` — echo `{input}`.
- `POST /functions/validate-booking` — validates a booking interval against the
  sauna booking method (a single time period within one calendar day). Request:
  `{"start":"<RFC3339>","end":"<RFC3339>"}`. Returns 200 with the echoed
  interval on success, 400 with `{"error":"..."}` otherwise.

## Configuration

- `PORT` (default 8081)
- `BOOKING_TIMEZONE` (default `Europe/Stockholm`) — IANA timezone used to
  determine the calendar day boundary for the single-day rule.

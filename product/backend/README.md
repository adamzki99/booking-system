# Backend (Go)

The booking platform backend.

## Responsibilities

- REST API for the frontend, and REST client of the deployment sidecar.
- Passwordless authentication: email → 6-character alphanumeric code → session.
- Command handling: validate commands and record events (append-only).
- Projections: build read models from recorded events.
- Queries: serve read models to the frontend.
- Emails: login codes, booking confirmations, cancellation notices, broadcasts.
- iCal feed of the booking calendar.
- OpenTelemetry export to SigNoz.

## Event store

PostgreSQL. Events are append-only — state is never updated or deleted, only
derived through projections.

### Booking conflict serialization

Create-booking validation and the `booking.created` append are not covered by a
single transaction: the handler checks the bookings read model, then the command
service appends the event and synchronously updates the projection. To keep that
check-then-append sequence atomic across backend replicas, `command.Service`
holds a PostgreSQL session-level advisory lock for the whole execution
(`eventstore.PostgresStore.Lock`). The lock is keyed by
`booking.CreateBookingLockKey`, acquired before validation and released after
the projection update, so a concurrent request observes the prior booking and
is rejected with `ErrDoubleBooking`.

Operational notes:

- All create-booking requests serialize on one advisory lock. Keep the pool's
  `MaxConns` above the expected peak of concurrent create-booking requests: the
  lock holder needs further connections for validation, append, and projection
  writes while its lock connection is held.
- The lock is session-scoped and held on a borrowed pooled connection. If it
  cannot be released, that connection is destroyed so the session close releases
  the lock instead of leaking it.
- Cancellations and blocked-period checks are not locked. Blocked-period
  validation is super-user-only and out of scope for this guard.

## Open decisions

- **Authelia fit:** Authelia is an SSO/2FA portal and does not natively provide
  the email-code passwordless flow. Current assumption: the backend implements
  the code flow itself; Authelia's role (if any) is limited to super/admin SSO.
- **iCal URLs:** calendar apps can't complete the login flow, so iCal feeds need
  token-authenticated URLs.

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

## Notification delivery

Booking confirmations, cancellation notices, and broadcasts are delivered
through the durable `notification_outbox` table. Notifiers enqueue one row per
intended delivery; a background worker sends it, retries transient sender
failures with bounded exponential backoff, and leaves permanently failed rows
in the table (`status = 'failed'`) for operator inspection. A replayed event
does not create duplicate rows.

Unlike domain events, outbox rows are mutable delivery work: their status,
attempt count, and next-attempt time advance as the worker runs. They are
infrastructure, not domain state — delivery outcomes never mutate, delete, or
roll back a recorded booking or broadcast event. Login-code and email-change
mail stay on the synchronous sender path and are not queued.

## Open decisions

- **Authelia fit:** Authelia is an SSO/2FA portal and does not natively provide
  the email-code passwordless flow. Current assumption: the backend implements
  the code flow itself; Authelia's role (if any) is limited to super/admin SSO.
- **iCal URLs:** calendar apps can't complete the login flow, so iCal feeds need
  token-authenticated URLs.

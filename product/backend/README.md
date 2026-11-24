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
- OpenTelemetry traces, metrics, and logs export via OTLP.

## Event store

PostgreSQL. Events are append-only - state is never updated or deleted, only
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

## Telemetry

Telemetry is optional. When `OTEL_EXPORTER_OTLP_ENDPOINT` is set, the backend exports traces, metrics, and logs over OTLP/HTTP. When it is empty, telemetry stays no-op and the backend logs a warning.

### Environment variables

| Variable | Purpose |
| --- | --- |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP HTTP base endpoint, for example `http://otel-collector:4318`. Empty disables export. |
| `OTEL_SERVICE_NAME` | Overrides `service.name`. Defaults to `booking-backend`. |
| `OTEL_RESOURCE_ATTRIBUTES` | Comma-separated `key=value` resource attributes, for example `service.version=... ,deployment.environment=... ,project=...`. |

The resource also includes OpenTelemetry SDK, host, and process runtime attributes. `OTEL_SERVICE_NAME` / configured service name takes precedence over defaults.

### Traces and spans

| Span | Source | Notes |
| --- | --- | --- |
| `GET /...` / route pattern | `otelhttp` server wrapper | Span name is the matched Go route pattern, for example `GET /bookings/{id}/cancel`. `http.route` is set. `/healthz` is excluded from tracing. |
| `command.execute` | command service | Attribute: `command.type`. |
| `projection.apply` | projection runner | Attributes: `projection.name`, `event.count`. |
| `smtp.send` | SMTP sender | Attribute: `smtp.host`. No recipient, subject, or body attributes. |
| pgx spans | `otelpgx` | Database spans for pool queries. Query parameters are not recorded. |
| sidecar client spans | `otelhttp` transport | Outbound HTTP spans to the deployment sidecar. |

Stdout JSON logs include `trace_id` and `span_id` when a span is active.

### Metrics

All metric attributes are low-cardinality enums. User ids, e-mails, booking ids, tokens, and raw URLs are never used as metric attributes.

| Metric | Type | Attributes | Notes |
| --- | --- | --- | --- |
| `events.appended` | counter | `type` | Recorded after successful event append. |
| `commands.handled` | counter | `command`, `outcome` | `outcome` is `ok` or `error`. |
| `commands.duration` | histogram (s) | `command`, `outcome` | Command handling duration. |
| `projection.checkpoint` | observable gauge | `projection` | Last applied event ID. |
| `projection.lag` | observable gauge | `projection` | Event store head minus checkpoint, clamped to zero. |
| `projection.errors` | counter | `projection` | Projection apply/checkpoint errors. |
| `bookings.created` | counter | - | Successful booking creation. |
| `bookings.cancelled` | counter | - | Successful booking cancellation. |
| `bookings.rejected` | counter | `reason` | `reason`: `double_booking`, `blocked_period`, `sidecar_rule`, `validation`. |
| `auth.codes_issued` | counter | - | Login code issued and sent. |
| `auth.logins` | counter | `result` | `result`: `success`, `invalid_code`, `rate_limited`, `error`. |
| `ratelimit.rejected` | counter | `limiter` | Low-cardinality limiter name, for example `auth_verify_ip`, `ical_token`. |
| `sidecar.requests` | counter | `endpoint`, `result` | `result`: `ok`, `rejected`, `unavailable`, `error`. |
| `sidecar.duration` | histogram (s) | `endpoint`, `result` | Sidecar request duration. |
| `email.sent` | counter | `result` | `result`: `ok`, `error`. |
| `notifications.enqueued` | counter | - | Outbox delivery enqueued. |
| `notifications.sent` | counter | - | Outbox delivery sent. |
| `notifications.retried` | counter | - | Outbox delivery scheduled for retry. |
| `notifications.failed` | counter | - | Outbox delivery permanently failed. |
| `notifications.enqueue_failed` | counter | - | Outbox enqueue failure. |
| `notifications.pending` | observable gauge | - | Pending outbox deliveries from the database. |

Runtime Go/process metrics are exported by the OTel runtime instrumentation. pgx pool stats are exported when pool instrumentation is enabled.

### Redaction and safety

- iCal feed tokens never appear in span names or in `url.path`, `url.full`, or `http.target` span attributes. The feed route is recorded as `/calendar/{token}`.
- DB spans do not record query parameters.
- SMTP spans do not record recipient, subject, or body.
- Metric attributes must remain low-cardinality; never add user ids, e-mails, booking ids, or tokens.

## Open decisions

- **Authelia fit:** Authelia is an SSO/2FA portal and does not natively provide
  the email-code passwordless flow. Current assumption: the backend implements
  the code flow itself; Authelia's role (if any) is limited to super/admin SSO.
- **iCal URLs:** calendar apps can't complete the login flow, so iCal feeds need
  token-authenticated URLs.

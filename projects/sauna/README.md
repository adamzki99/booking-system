# Sauna Booking (deployment)

Sauna booking system for a homeowner association, the first deployment of the
booking product.

## UI mockups

Supplied normal-user UI mockups for this deployment live in [`docs/mocks/`](docs/mocks/):

- [`sauna_booking_website_normal_user_mock_desktop.html`](docs/mocks/sauna_booking_website_normal_user_mock_desktop.html): desktop bookings view (app shell, create-booking action, quick book/repeat flow, upcoming bookings list).
- [`sauna_booking_website_normal_user_mock_mobile.html`](docs/mocks/sauna_booking_website_normal_user_mock_mobile.html): mobile bookings view and menu-open state.

When implementing sauna UI, align layout, styling, coloring, spacing, typography, and component states with these mockups. Use the fixed frontend stack (**Solid 2, TypeScript, Vite, @solidjs/router**) and implement visual treatment through shared UI primitives, theme tokens, and component patterns (see [`../../product/frontend-solid/README.md`](../../product/frontend-solid/README.md)). Reusable visual patterns should be captured in generic frontend theme/components when broadly useful; sauna-specific branding and content remain deployment-specific.

## User roles

### Basic user

- Make bookings.
- Cancel their own bookings.
- Change the email connected to their account. The new address must be
  verified first: a code is emailed to it, the change only takes effect once
  that code is confirmed, and the old address stops working as a login
  afterwards. Active sessions stay valid under the new address.
- See all other users registered on the platform.
- Add the booking calendar to their calendar (iCal format).

### Super user

Held by persons assigned by the homeowner association. Capabilities are a
superset of the basic user's, plus:

- Cancel bookings of any basic user.
- Block basic users from making bookings during a specific time period.
- Add basic users.
- Remove basic users.
- Change the address of a basic user.
- Send messages to all basic users.

**Cannot** delete anything from the system.

### Admin user

The system owner only. Capabilities are a superset of the super user's.

## Initial test flows

### Happy flow

1. User enters their email address.
2. User receives an email with a random, system-generated 6-character
   alphanumeric code.
3. The user is logged in to the system.
4. The user clicks "Create a booking".
5. The user enters the booking details.
6. The user completes the booking.
7. The system registers the booking and sends a confirmation email to the user.
8. The user reads the confirmation email.

### Alternative flow (continuation of the happy flow)

9. The super user cancels the created booking.
10. The super user confirms the cancellation.
11. The system registers the cancellation event and sends a confirmation email
    to the user that made the booking.
12. The user reads the email with the notice of the cancelled booking.

## Automated E2E tests

Backend API-level end-to-end tests live in `product/backend/internal/e2e/` and
cover the happy flow (login -> create booking -> confirmation email) and the
alternative flow (super user cancels -> cancellation email), including a few
negative assertions (unauthenticated create returns 401; non-super cancellation
of another user's booking returns 403).

Run locally (requires Docker for testcontainers):

```sh
cd product/backend && go test ./internal/e2e/...
```

If a PostgreSQL instance is already available, set `DATABASE_URL` to skip
testcontainers:

```sh
DATABASE_URL="postgres://user:pass@localhost:5432/db?sslmode=disable" \
  go test ./internal/e2e/...
```

Browser-level steps from the flows above (login screen, calendar rendering,
reading email in a mail client) remain a manual verification checklist until
Playwright and a mail sink are added.

#### Public iCal feed smoke check

The basic-user story includes adding the booking calendar to a personal
calendar. Caddy proxies the public `/calendar/*` path to the backend so the
generated URL works without an auth header. To smoke-check a deployed stack:

1. Log in as a basic user and call `POST /api/account/calendar-token`; keep the
   returned `url` secret (the token is a bearer credential).
2. Validate the ingress configuration and run the smoke check against the
   public origin, with no `Authorization` header:

   ```sh
   caddy validate --config config/Caddyfile --adapter caddyfile
   CALENDAR_URL='https://<site>/calendar/<token>.ics' scripts/smoke-calendar-feed.sh
   ```

3. Confirm the response is a `VCALENDAR` with the active bookings. Create a
   booking, refresh the feed, then cancel that booking and refresh again: the
   event must appear and then disappear. Invalid tokens must return a
   non-calendar error.

## Telemetry / project monitoring

The backend exports traces, metrics, and logs via OTLP/HTTP when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set. Leaving it empty disables export; the
backend logs a warning and runs with no-op providers. No monitoring stack is
required for the booking stack to start.

Sauna uses its own monitoring instance built from the generic base in
[`../../product/monitoring/`](../../product/monitoring/README.md). The instance
config lives in [`monitoring/`](monitoring/) and has its own compose project
(`sauna-monitoring`), network (`sauna-monitoring-net`), volumes, ports, and
`.env`.

Start monitoring:

```sh
cd monitoring
cp .env.example .env
# fill required secrets and ports (defaults: Grafana 3001, OTLP 4328/4327)
docker compose up -d
```

To attach a locally started booking stack to the running monitoring instance:

```sh
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

`docker-compose.monitoring.yml` is an optional override: it joins `backend`,
`sidecar`, and optionally `caddy` (profile `caddy`) to `sauna-monitoring-net`
and sets `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318` so traces,
metrics, and logs flow to the sauna monitoring collector. The booking stack
starts normally without this override.

`dev-ops/scripts/deploy-environment.sh` detects `sauna-monitoring-net`: when the
network exists it adds `docker-compose.monitoring.yml` automatically; when it is
absent it deploys without monitoring and logs one line. Deploys never fail
because monitoring is down.

Grafana is bound to `127.0.0.1:${GRAFANA_PORT:-3001}`. Use an SSH tunnel for
remote access. See [`../../product/monitoring/README.md`](../../product/monitoring/README.md)
for validation, retention, and security details.

## Sidecar

`sidecar/` holds the sauna-specific components, kept out of the generic product.
It is stateless and called by the backend over REST.

## Running

Everything is packaged in `docker-compose.yml` (Caddy, frontend, backend,
sidecar, PostgreSQL; Authelia is opt-in via the `authelia` profile). Project
monitoring is optional and runs as a separate compose stack; see
[Telemetry / project monitoring](#telemetry--project-monitoring).

### Prerequisites

- Docker Engine + Docker Compose plugin (or run the setup script below, which
  installs them).

### Quick start from a clean checkout

```sh
cp .env.example .env
# edit .env: set POSTGRES_PASSWORD, DATABASE_URL, PUBLIC_BASE_URL, etc.
docker compose up -d --build
```

### One-command provisioning (fresh Linux host)

```sh
sudo ./setup.sh
```

The script installs Docker if missing, clones/updates the repo into
`/opt/booking-system`, creates `.env` from `.env.example` when absent, builds
and starts the stack, then prints the Caddy URL and `docker compose ps`.

### Service / health endpoints

- Caddy (entrypoint, HTTP): `http://<host>:${PORT:-8080}`
- Caddy (public, HTTPS): `https://${SITE_ADDRESS:-localhost}` when `SITE_ADDRESS`
  is set; see [Let's Encrypt TLS](#lets-encrypt-tls).
- Backend health: `http://<host>:${PORT:-8080}/api/...` (direct: backend:8080 `/healthz`)
- Sidecar health: sidecar:8081 `/healthz`

### Logs / stop / update

```sh
docker compose logs -f
docker compose down
docker compose up -d --build   # rebuild after changes
```

### Authelia (optional)

Authelia is disabled by default. Start it with:

```sh
docker compose --profile authelia up -d
```

### Cloudflare Tunnel

For exposing a self-hosted instance publicly over HTTPS via Cloudflare Tunnels,
follow [`../../dev-ops/self-hosting-cloudflare-tunnel.md`](../../dev-ops/self-hosting-cloudflare-tunnel.md).
Keep tunnel tokens, public hostnames, and other deployment-specific values in
sauna deployment config/environment (not in `product/`).

### Let's Encrypt TLS

Each environment serves HTTPS with its own Let's Encrypt certificate, issued and
auto-renewed by Caddy over ACME. Set `SITE_ADDRESS` (public FQDN), `ACME_EMAIL`,
and optionally `ACME_CA` (staging) in `.env`; Caddy publishes `80`/`443` for the
HTTP-01 challenge and stores certificate state in the per-environment
`caddy-data` volume. See [`../../dev-ops/tls-letsencrypt.md`](../../dev-ops/tls-letsencrypt.md)
for DNS requirements, staging, rate limits, and verification. With `SITE_ADDRESS`
unset, Caddy serves an internal self-signed certificate for `localhost`.

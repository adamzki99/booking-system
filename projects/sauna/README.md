# Sauna Booking (deployment)

Sauna booking system for a homeowner association — the first deployment of the
booking product.

## User roles

### Basic user

- Make bookings.
- Cancel their own bookings.
- Change the email connected to their account.
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


## SigNoz / telemetry

The backend exports traces and metrics via OTLP/HTTP. SigNoz (APM) is run
separately from this compose stack. Configure the collector endpoint with the
`OTEL_EXPORTER_OTLP_ENDPOINT` environment variable (SigNoz collector listens
on port 4318 for OTLP/HTTP). Set `OTEL_SERVICE_NAME` to override the service
name (defaults to `booking-backend`). Leaving `OTEL_EXPORTER_OTLP_ENDPOINT`
unset disables export; the backend logs a warning and runs with no-op providers.

## Sidecar

`sidecar/` holds the sauna-specific components, kept out of the generic product.
It is stateless and called by the backend over REST.

## Running

Everything is packaged in `docker-compose.yml` (Caddy, frontend, backend,
sidecar, PostgreSQL; Authelia is opt-in via the `authelia` profile; SigNoz
runs separately).

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

- Caddy (entrypoint): `http://<host>:${PORT:-8080}`
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

# Product — Booking Platform

The generic booking product. Contains everything reusable across deployments;
deployment-specific configuration and logic live in `../projects/<name>/`.

## Components

| Component   | Tech  | Purpose |
|-------------|-------|---------|
| `backend/`  | Go    | Commands, queries, event store, projections, REST API, auth. |
| `frontend/` | React | Booking calendar UI, account management, super-user tooling. |

## Core capabilities

- Passwordless login: user enters email, receives a 6-character alphanumeric code.
- Create and cancel bookings; confirmation emails on booking and cancellation.
- iCal export of the booking calendar.
- Role model: basic user < super user < admin (each role's capabilities are a
  superset of the previous). Super users manage users and may cancel/block
  bookings, but may not delete anything.

## Architecture

- **CQRS + event sourcing:** the backend records events only; all state is
  derived from projections. Commands produce events, queries read projections.
- **Sidecar:** deployment-specific functions (e.g. sauna rules) are provided by
  the deployment (`projects/<name>/sidecar/`) and called over REST.

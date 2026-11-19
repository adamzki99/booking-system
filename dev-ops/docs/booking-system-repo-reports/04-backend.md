# Go Backend Review: Event Store, Projections, Booking Domain and Notifications

**Scope:** `product/backend/**` (all packages under `internal/`, `cmd/server`, migrations 0001–0010, tests), the backend–sidecar contract in `projects/sauna/sidecar/internal/{server,rules,config}`, `.github/workflows/backend-ci.yml`, and `projects/sauna/config/Caddyfile` and `docker-compose.yml` as far as they affect the backend. This was a static review only: I read the code and the git history and ran nothing. Security is covered only briefly because a separate pass handles it. · **Reviewed:** 2026-11-19 at commit 45f6ee5

## Summary

The backend is a small Go service of about 15k lines, including tests. Its layout is clear: `command.Service` runs a handler, appends events, then publishes them through an in-process `dispatcher`. A `projection.Runner` keeps eight read models up to date synchronously from that publish. Notifiers write rows to a `notification_outbox` table, and a polling worker delivers those rows. The architecture rules are mostly followed. Every domain state change goes through an event, no query reads the event stream, and `events` is only ever inserted into. However, the hard parts of event sourcing are thin or missing:

- **No transactional consistency between the event and its effects.** Appending the event, updating the projection, advancing the checkpoint and enqueuing the notification are four separate writes.
- **Events can be skipped silently.** The projection checkpoint is "highest event ID seen", so an event that commits out of ID order, or that fails in one projection, is passed over for good.
- **No stream versioning.** Every invariant is checked against read models. Only create-booking is protected, by a global session-level advisory lock that can deadlock the connection pool.

Several user-visible defects follow from deployment details:

- Per-IP rate limits key on Caddy's address, so they act as site-wide limits.
- Confirmation emails show times in UTC.
- The sidecar's capacity setting has no effect.

The code also shows clear drift from the many models that wrote it. There are 35 alias functions and constants, families of aliased error values, and four copies of the JSON writer and the request decoding logic. The domain is small and the traffic is low (one sauna, one homeowner association), so none of this is an emergency. It is cheap to fix now, and it gets more expensive as more domains are added.

**What's working well**

- **CQRS discipline holds.** Commands read only projections. Queries never touch `events` (`LoadAll` is used only by the runner, `internal/projection/runner.go:67,85,106`). `LoadByAggregate` has no callers. "No deletes" is respected: cancellation, removal and blocking are all events.
- **Read-your-writes works for the UI.** Projections are applied synchronously before `Execute` returns, so `CreateBooking` can read its own booking back (`internal/booking/service.go:68`).
- **The outbox worker's claim logic is solid.** It uses `FOR UPDATE SKIP LOCKED`, a lease, `attempts` incremented on claim, and an idempotency key `UNIQUE (event_id, kind, recipient_email)` (`internal/notification/postgres.go:46-63`, `migrations/0010_create_notification_outbox.sql`). Failed rows are kept for operators.
- **Projections have a working rebuild path.** `Reset` + `RebuildAll` exists, and most `Apply` methods are idempotent upserts. `TestRebuildAllReproducesState` covers this (`internal/booking/integration_test.go:366`).
- **Integration tests use real Postgres in CI.** Every Postgres test runs on `ubuntu-latest` through testcontainers when `DATABASE_URL` is unset. That includes a real concurrency test for double booking (`internal/booking/integration_test.go:174`).
- **Secrets are handled carefully.** Login codes and calendar tokens are stored only as hashes (bcrypt or SHA-256), recipients are masked in logs, and the SMTP sender blocks header injection.

## Findings

| ID | Severity | Effort | Title |
|----|----------|--------|-------|
| BE-01 | Critical | M | Projection runner can permanently skip events (commit-order gaps, partial batch failure) or crash-loop on a poison event |
| BE-02 | High | M | Create-booking advisory lock can exhaust the connection pool and stall the whole backend, and protects only create-vs-create |
| BE-03 | High | S | A command reports failure after its event is already committed; there is no idempotency |
| BE-04 | High | M | The "outbox" is a best-effort dual write that is never replayed, so a crash or error loses emails silently |
| BE-05 | High | S | Per-IP rate limits key on Caddy's address, so they are global limits (20 login codes per hour for everyone) |
| BE-06 | Medium | S | Email retry gives up after about 15 s; SMTP has no timeout; transient and permanent errors are treated the same |
| BE-07 | Medium | M | No stream versioning or optimistic concurrency; invariants are checked against read models; no event schema versioning |
| BE-08 | Medium | S | Booking emails show UTC times; the product has no display timezone |
| BE-09 | Medium | M | Backend–sidecar contract: capacity hard-coded in the product, no user context, fails open, midnight-boundary bug |
| BE-10 | Medium | S | Migrations rerun every file on every boot, with no version table |
| BE-11 | Medium | M | Auth design: ephemeral credentials in the event log, identity keyed by email, no logout or revocation |
| BE-12 | Medium | S | Inconsistent HTTP layer: unbounded decoding, raw internal errors returned, mixed error formats and key styles |
| BE-13 | Medium | M | AI-generated drift: 35 aliases, alias error families, duplicated boilerplate, dead fallbacks |
| BE-14 | Medium | M | Tests: no `-race`, duplicated harness, shared-DB mode not isolated, key failure modes untested |
| BE-15 | Low | S | `sample` scaffolding is still registered in production |
| BE-16 | Low | S | Config: silent fallbacks, `PublicBaseURL` unused, no DB still reports healthy |
| BE-17 | Low | M | Observability gaps: no DB or sidecar spans, no log–trace correlation, misleading `pending` gauge |
| BE-18 | Low | M | Performance hotspots: global runner mutex, 2×N checkpoint round-trips per event, unbounded reads |
| BE-19 | Low | S | Domain gaps: removed users keep future bookings, blocks can't be lifted or conflict-checked, role edge cases |
| BE-20 | Low | S | Append-only is enforced only by a source-grep test; rebuild can't be triggered in operation |

---

### BE-01 — Projection runner can permanently skip events or crash-loop on a poison event (Critical, M)

**Evidence**
- Event IDs come from `BIGSERIAL` inside the append transaction (`migrations/0001_create_events.sql:2`, `internal/eventstore/eventstore.go:107-131`). Transactions can commit in a different order from their IDs.
- The runner receives only the batch from the current command (`internal/registry/registry.go:31` `d.Subscribe(runner.Handle)`). It skips anything at or below the checkpoint: `if event.ID <= checkpoint { continue }` (`internal/projection/runner.go:147`). It then advances the checkpoint for *every* projection, including those that ignore the event (`runner.go:155`).
- Example: command A gets id 101 and command B gets id 102. B commits and publishes first, so every checkpoint moves to 102. A then publishes `[101]` and every projection skips it. The advisory lock in BE-02 does not prevent this, because it only orders create-booking against other create-booking calls. Any concurrent login, cancellation or user event can interleave.
- `handleLocked` loops over a Go map and returns on the first error: `for name, projection := range r.projections { if err := ...; err != nil { return err } }` (`runner.go:128-135`). If one projection fails, the projections later in the random iteration order never see the event. The next command's batch then moves their checkpoints past it.
- `Apply` and `checkpoints.Set` are separate auto-commit statements (`runner.go:150-155`, `internal/projection/checkpoint_postgres.go:37-50`), so delivery is at-least-once with no transaction.
- At startup, `CatchUp` fails the whole process on any projection error (`cmd/server/main.go:81-85` → `os.Exit(1)`). If the poison event is the newest one, the backend crash-loops. If newer events exist, it is skipped silently. Projections that can fail on valid events include `users.email UNIQUE` (`migrations/0005_create_users.sql:3`, hit by a concurrent `AddUser` or by two users confirming the same new email, see BE-07) and `bookings.id UUID` with the non-UUID `NewID` fallback (BE-13).

**Why it matters**
A skipped `booking.created` means the booking is in the event log and the confirmation email goes out (notifiers don't use checkpoints). But the slot appears free, so it can be double-booked. `CreateBooking` then returns `ErrBookingNotFound` (404) from the read-back, and only a manual `RebuildAll` recovers. Nothing exposes `RebuildAll` (BE-20). This defeats the main promise of event sourcing, that state can always be derived from the log.

**Recommendation**
1. Make ID order match commit order. At this traffic level, the simplest way is a global append lock that lives for the transaction:
   ```go
   // in PostgresStore.Append, right after Begin
   if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, appendOrderLockKey); err != nil { ... }
   ```
   A scalable alternative is to read only below `pg_snapshot_xmin(pg_current_snapshot())` using an `xid8` column, as Marten and Eventuous do.
2. Make `Handle` *pull* instead of trusting the pushed batch. Use `LoadAfter(ctx, minCheckpoint)` (`WHERE id > $1 ORDER BY id LIMIT n`). This also picks up events written by other replicas.
3. Apply each event and its checkpoint in **one transaction**. Change the interface to `Apply(ctx, pgx.Tx, Event)` and run `UPDATE projection_checkpoints … ` on the same `tx`.
4. Isolate failures per projection. A failing projection stops at its own checkpoint, logs the event ID, increments a `projection.errors` metric and does not block the others. `CatchUp` failures should mark the projection as degraded instead of calling `os.Exit`.
5. Add a test that commits id N+1 before id N and checks that both are projected.

### BE-02 — Create-booking advisory lock can exhaust the pool and covers only create-vs-create (High, M)

**Evidence**
- `PostgresStore.Lock` borrows a pooled connection and blocks on `SELECT pg_advisory_lock($1)` (`internal/eventstore/eventstore.go:148-171`). The lock holder then needs *more* pooled connections for `bookings.List`, `HasOverlap`, `users.GetByID`, `Append`, 8×`Apply` and 8×`checkpoints.Set` (`internal/booking/commands.go:102-122`, `internal/command/service.go:99-115`).
- The pool uses pgx defaults: `pgxpool.New(ctx, databaseURL)` (`eventstore.go:256`), and the deployment URL has no `pool_max_conns` (`projects/sauna/.env.example:11`). The default is `max(4, NumCPU)`. Suppose four create-booking requests arrive at once on a 2-vCPU host. The holder plus three waiters use all four connections, and the holder blocks in `Acquire`. Every other request then blocks in `Acquire` too, including the session middleware on every authenticated route. The stall lasts until clients disconnect, because `http.Server` has no handler timeout and `pg_advisory_lock` has no `lock_timeout`. `product/backend/README.md` documents "keep MaxConns above peak", but nothing in code or config enforces it.
- The lock is released after `Publish` (`service.go:97`) whether or not the projection update succeeded. If `Publish` fails, the next create does not see the booking (BE-01, BE-03).
- Only `CreateBooking` implements `LockKey` (`commands.go:42-45`). `BlockTimePeriod`, cancellations, user deactivation and role changes are not serialized. The README says this ("Blocked-period validation … out of scope").

**Why it matters**
The fix for #117 closes the create/create race that was tested. In exchange, it adds a way for the whole API to stall under a modest burst, for example a dozen neighbours booking when a new week opens. It also makes correctness depend on a non-transactional projection update.

**Recommendation**
Keep one global key, which is fine at this scale. Run the *decision* in a single transaction on a single connection, with a lock that ends with that transaction:
```go
tx, _ := pool.Begin(ctx)
defer tx.Rollback(ctx)
tx.Exec(ctx, `SET LOCAL lock_timeout = '3s'`)
tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, booking.CreateBookingLockKey)
// overlap / blocked / sidecar checks using tx
// INSERT INTO events ... using tx
// apply bookings projection + checkpoint using tx   (see BE-01 #3)
tx.Commit(ctx)
```
This requires `command.Service` to pass a transaction to handlers and to the store, for example `Handler func(ctx, tx pgx.Tx, cmd)`. A cheaper alternative is a command-side consistency table, written in the same transaction as the event, with `EXCLUDE USING gist (slot WITH &&) WHERE (released_at IS NULL)` on `tstzrange(start,"end")`. Then the database rejects overlaps even if a code path forgets the lock. In both cases, set `pool_max_conns` explicitly and fail fast on lock timeout with a 503 and `Retry-After`. Extend the guarded set to `BlockTimePeriod` and the cancel commands.

### BE-03 — Commands report failure after the event is committed; no idempotency (High, S)

**Evidence**
- `Execute` appends and then publishes: `recorded, err := s.store.Append(...)` and then `if err := s.publisher.Publish(ctx, recorded); err != nil { … return err }` (`internal/command/service.go:105-115`). Any error from projection, checkpoint or subscriber is returned to the HTTP handler, which responds with 500 even though the event is permanent.
- `BookingService.CreateBooking` generates a new ID for every call (`internal/booking/service.go:59`) and reads back from the projection (`service.go:68`). There is no client idempotency key.
- The dispatcher stops at the first failing subscriber (`internal/dispatcher/dispatcher.go:28-35`). The runner is subscribed first (`registry.go:31`), so a projection error also prevents the notifiers from running.

**Why it matters**
A user who gets a 500 and retries creates a second booking, or a second cancellation, broadcast or user. Retrying a broadcast emails every resident again.

**Recommendation**
After a successful append, `Execute` should return success with the recorded events. Log projection or notify errors and retry them asynchronously through the catch-up loop in BE-01. Add an optional `Idempotency-Key` header on `POST /bookings` and `POST /broadcast`. Store it in the event metadata with a unique index on `(event_type, idempotency_key)`, and return the original result when the key repeats.

### BE-04 — The outbox is a best-effort dual write, never replayed (High, M)

**Evidence**
- Notifiers run as dispatcher subscribers *after* the event transaction has committed (`internal/booking/notify.go:32`, `internal/broadcast/notifier.go:73`). They call `Enqueue` in its own statement (`internal/notification/postgres.go:15-29`) and only log failures: "an enqueue error is logged and never surfaced" (`notify.go:19-21`, `notify.go:107-121`).
- Notifiers keep no checkpoint and are not projections, so `CatchUp` and `RebuildAll` never call them again. If the process crashes between commit and enqueue, or the enqueue fails, or the projection fails first (BE-03), the email is lost and nothing records that it was lost.
- `enqueueCancelled` looks up the owner from the bookings *projection* (`notify.go:79-86`). If the cancel was skipped by BE-01, the notice is dropped.
- AGENTS.md says these must be "enqueued into a durable `notification_outbox`".

**Why it matters**
This is a "transactional outbox" without the transaction. In particular, the cancellation notice required by the "alternative flow" can disappear without a trace.

**Recommendation**
There are two good options. Both reuse the existing unique key, which already makes enqueue idempotent:
1. Insert the outbox rows **in the same transaction as the event append**. This needs the transaction-aware command path from BE-02.
2. Make each notifier a **checkpointed projection** (`Name() = "notify.booking"`) driven by the runner. Replay is then safe and gaps are filled automatically. Set the starting checkpoint to the current max ID when deploying, so history is not re-sent.

Option 2 is the smaller change. Put the owner's user ID in `BookingCancelledPayload` so the notifier needs no projection lookup.

### BE-05 — Per-IP rate limits are global behind Caddy (High, S)

**Evidence**
- Three copies of `clientIP` use `r.RemoteAddr` (`internal/server/server.go:254-260`, `internal/user/http.go:33-39`, `internal/ical/http.go:109-115`). Caddy proxies everything with `reverse_proxy backend:8080` (`projects/sauna/config/Caddyfile:27-38`), so `RemoteAddr` is always the Caddy container.
- The limits are: login code requests 20 per IP per hour (`internal/auth/service.go:22-23`), verification 30 per hour (`auth/service.go:27-28`), and the iCal feed 30 per IP per hour (`internal/ical/http.go:22-23`).
- The limiter is in memory and per process. Its `windows` map is never pruned (`internal/ratelimit/limiter.go:14,43`), and redeploys reset it (the factory redeploys on a schedule).

**Why it matters**
After 20 login code requests in an hour across the *whole association*, nobody can log in for the rest of the hour. One user's calendar app polling every few minutes, plus a handful of others, uses up the feed budget, and every subscription returns 429. This works as a self-inflicted denial of service. It also lets an attacker lock everyone out cheaply.

**Recommendation**
Configure Caddy to set the client IP (`header_up X-Real-IP {remote_host}`, already covered by `trusted_proxies`). Read it in one shared `httpx.ClientIP(r, trustedProxies)` helper that falls back to `RemoteAddr` only when the peer is not a trusted proxy. Prune expired windows, for example in a sweep run from `Allow`. If more than one replica will ever run, move the limits to Postgres (`INSERT … ON CONFLICT … RETURNING count`).

### BE-06 — Email retry gives up after about 15 s; SMTP has no timeout (Medium, S)

**Evidence**
- Defaults are `MaxAttempts 5`, `BaseDelay 1s`, `MaxDelay 1m` (`internal/notification/worker.go:14-16`, `internal/config/config.go:51-52`). The delays are 1+2+4+8 s, plus up to 5 s per tick, so a row is marked `failed` (`worker.go:128-135`) within about 30–40 s of the first attempt. An SMTP outage of a minute permanently fails every confirmation sent during it. Nothing re-drives failed rows. `Store.List` exists but has no endpoint.
- `SMTPSender.Send` ignores `ctx` and calls `smtp.SendMail`, which has no dial or IO timeout (`internal/email/smtp_sender.go:44-55`). One hung server blocks the single worker loop indefinitely.
- The lease is 30 s (`internal/notification/outbox.go:33`), and a batch is 50 rows sent one after another. If one batch takes longer than 30 s and a second replica or worker exists, it re-claims and sends again.
- Every error is retried the same way, so a permanent `550 mailbox unavailable` is retried just like a timeout.

**Why it matters**
A short provider outage turns into permanently missing confirmations and cancellation notices, with no operator tooling to recover them.

**Recommendation**
Change the defaults to something like `MaxAttempts 10`, `BaseDelay 30s`, `MaxDelay 1h`, with jitter, which spans about a day. Classify SMTP 5xx errors as permanent and fail them immediately. Dial with `net.Dialer{Timeout: 10*time.Second}` and set `conn.SetDeadline` (or use a context-aware mail library). Set the lease from the batch's worst-case send time, or claim one row per send. Add an admin endpoint or CLI to list and requeue `failed` rows.

### BE-07 — No stream versioning or optimistic concurrency; no event schema versioning (Medium, M)

**Evidence**
- The `events` table has no `stream_version` and no uniqueness per aggregate (`migrations/0001_create_events.sql`). `Append` has no expected-version argument (`eventstore.go:92`). Aggregates are never rebuilt from their own stream (`LoadByAggregate` has no callers). Every handler validates against a read model.
- Unprotected check-then-append races that result:
  - Two concurrent cancels both pass `b.Status != StatusActive` (`internal/booking/commands.go:181,224`). That gives two `booking.cancelled` events and two emails, and the last writer wins `cancelled_by`.
  - Concurrent `AddUser` with the same email both pass the duplicate check (`internal/user/commands.go:238-242`). The second `user.created` then violates `users.email UNIQUE`, which is a poison event (BE-01).
  - The same applies to `ConfirmOwnEmailChange` ("first confirmed change wins", `user/commands.go:470-477`) and to concurrent `VerifyLoginCode`, where one code produces two sessions.
- There is no `schema_version` or metadata. Payload changes are handled ad hoc. `UserRoleChangedPayload` has both `Role` and `NewRole` (`internal/user/events.go:81-82`), and the projection falls back between them (`internal/user/projection.go:193-196`).

**Why it matters**
Domain invariants hold only on a quiet day. Without versioning, each future payload change will add another fallback inside a projection.

**Recommendation**
Add `stream_version INT NOT NULL` and `UNIQUE (aggregate_type, aggregate_id, stream_version)`. Give `Append` an `expectedVersion` argument and map the unique violation to `ErrConcurrencyConflict`, which becomes HTTP 409 or a retry. For decisions that cross aggregates (email uniqueness, slot overlap), use a reservation stream such as `aggregate_type='email', aggregate_id=<email>` with expected version 0, or the transaction-scoped lock from BE-02. Add `schema_version SMALLINT DEFAULT 1` and a `metadata JSONB` column (actor, correlation or trace ID, idempotency key). Put upcasters in one `eventstore.Upcast(event)` step before `Apply`.

### BE-08 — Booking emails show UTC times (Medium, S)

**Evidence**
- The frontend sends `new Date(start).toISOString()` (`product/frontend/src/pages/Calendar.tsx:72-73`), which is always in UTC (`Z`). Go keeps that offset, and the notifier formats it without converting: `payload.Start.Format("2006-01-02 15:04")` (`internal/booking/notify.go:61`).
- The only timezone setting is in the sidecar (`BOOKING_TIMEZONE`, `projects/sauna/sidecar/internal/config/config.go`). The product has no display timezone.

**Why it matters**
A Stockholm resident who books 18:00–19:00 is told "17:00 to 18:00" in winter and "16:00 to 17:00" in summer. This is happy-flow step 8 in `projects/sauna/README.md`.

**Recommendation**
Add `DISPLAY_TIMEZONE` to `config.Config`, load it once with `time.LoadLocation` and fail at startup if it is invalid. Format as `start.In(loc).Format("Mon 2 Jan 15:04 MST")`. Include the zone abbreviation so it is unambiguous across DST changes. Alternatively, have the sidecar provide formatting or templates through a `/functions/render-notification` endpoint.

### BE-09 — Backend–sidecar contract problems (Medium, M)

**Evidence**
- **Capacity is hard-coded in the product.** After the sidecar check, the backend always rejects any overlap: `HasOverlap … WHERE status='active' AND start < $2 AND "end" > $1` (`internal/booking/projection.go:82`, used at `internal/booking/commands.go:111-117`). The sidecar's `SAUNA_CAPACITY` and its `capacity` request field (`projects/sauna/sidecar/internal/server/server.go:148-150`) therefore have no effect. A deployment rule ("one at a time") sits in `product/`.
- **No user context.** The request is `{start, end, existing}`, where `existing` holds only bookings overlapping the candidate (`internal/sidecar/client.go:55-67`, `commands.go:102`). The sidecar gets no user ID or role, no user's other bookings and no time of request. Common HOA rules such as "max N bookings per week per apartment" or "no more than 14 days ahead" cannot be expressed.
- **Fails open.** A 200 with an empty body counts as allowed (`client.go:87-89`). An unset `SIDECAR_URL` disables every rule without a warning (`cmd/server/main.go:71-74`). A sidecar outage fails closed (503), which is correct.
- **Midnight bug.** The single-day rule compares `start.In(loc)` with `end.In(loc)` by calendar date (`sidecar/internal/server/server.go:142`). A half-open 22:00–00:00 booking ends "the next day" and is rejected. An invalid `BOOKING_TIMEZONE` silently falls back to UTC (`server.go:189`).
- The rules in `rules.Validate` duplicate the backend overlap check.

**Why it matters**
The product/sidecar split exists to keep deployment rules out of `product/`, but the contract can't express the rules an HOA actually needs, and the one configurable rule has no effect.

**Recommendation**
Turn the contract into a versioned DTO, for example `POST /functions/v1/validate-booking`:
```json
{"candidate":{"start":"…","end":"…"},"user":{"id":"…","role":"basic"},
 "now":"…","existing":[…overlapping…],"userBookings":[…user's future active…]}
```
Remove `HasOverlap` from the product, or make it a configurable default that applies when no sidecar is configured. Treat an empty or invalid 200 response as `ErrSidecarUnavailable`. Log at startup when `SIDECAR_URL` is unset, and in production refuse to start without it. Fix the sidecar date check to use `end.Add(-time.Nanosecond)`, and make an invalid timezone a startup error.

### BE-10 — Migrations rerun every file on every boot (Medium, S)

**Evidence**
`runMigrations` walks the embedded files and `pool.Exec`s each one on every start (`internal/eventstore/eventstore.go:223-252`). There is no `schema_migrations` table, no lock, and no transaction per file. It only works because every file uses `CREATE … IF NOT EXISTS`.

**Why it matters**
The first `ALTER TABLE … ADD COLUMN` without `IF NOT EXISTS`, or any data backfill (both needed for BE-07), will fail or run again on every boot. Replicas starting at the same time would run DDL concurrently.

**Recommendation**
Adopt `pressly/goose` or `golang-migrate` with `embed.FS`, or write a 30-line runner. It needs a `schema_migrations(version)` table, a `pg_advisory_lock` around the run, and one transaction per file. Mark 0001–0010 as applied for existing databases.

### BE-11 — Auth design: credentials in the event log, identity keyed by email, no revocation (Medium, M)

**Evidence**
- Every login code request appends `auth.login_code_issued`, with a bcrypt code hash, and every login appends `auth.session_created`, with the session token hash (`internal/auth/commands.go:122-136,186-201`). These are permanent and replayed into `login_codes` and `sessions` on rebuild.
- The authenticated identity is the email string. Sessions are keyed by email (`migrations/0004_create_auth_tables.sql`), the context carries `email` (`internal/auth/middleware.go:50`), and every service starts with `GetByEmail`. Changing an email therefore needs a special `auth.session_identity_changed` event that rewrites session rows (`internal/auth/projection.go:157-168`).
- `sessions.revoked_at` exists but nothing ever sets it. There is no logout or revoke command, so the frontend's "logout" (commit 12d772b) only drops the token on the client, and the session lasts 24 hours (`auth/service.go:16`). Deactivation works only because the middleware also checks `ActiveByEmail` on every request (`middleware.go:45-48`).
- Brief security notes:
  - `canLogin` lets *any* email log in while the users table is empty, and the first verifier becomes admin (`auth/service.go:85-88`, `user/service.go:61-78`, guarded only by an in-process mutex).
  - One code can create two sessions if verified concurrently (BE-07).

**Why it matters**
Ephemeral, high-volume, secret-bearing state is the worst fit for an append-only log. It bloats the log (BE-18), makes rebuilds slower, and keeps credential hashes forever. Keying identity on a mutable attribute caused the session re-keying complexity.

**Recommendation**
Key sessions and the context on `user_id` and resolve email only for display. Add `auth.session_revoked` (logout, plus "log out everywhere" on deactivation). Consider moving login codes and sessions into ordinary tables with TTL and recording only security-relevant facts as events (`user.logged_in`). AGENTS.md already allows outbox-style operational tables, so this needs a short ADR. Disable empty-table bootstrap unless an explicit `ADMIN_BOOTSTRAP_EMAIL` is set.

### BE-12 — Inconsistent HTTP layer (Medium, S)

**Evidence**
- **Decoding:** `server.decodeJSON` limits the body to 1 MiB and rejects trailing data (`internal/server/server.go:216-225`). Seven other handlers use a bare `json.NewDecoder(r.Body).Decode` with no limit (`internal/booking/http.go:84,136`, `internal/broadcast/http.go:41`, `internal/user/http.go:124,186,226,265,301`).
- **Leaking errors:** raw `err.Error()` is returned to clients, including 500s that wrap pgx errors (`booking/http.go:57,90,112,141,157`, `broadcast/http.go:46`, `ical/http.go:82` `http.Error(w, err.Error(), 500)`).
- **Mixed formats:** the session middleware returns plain-text `http.Error(w, "unauthorized", 401)` (`internal/auth/middleware.go:33-47`), while handlers return `{"error": …}`.
- **Mixed key styles:** `bookingToMap` emits both `user_id` and `userId`, `created_at` and `createdAt`, and so on (`booking/http.go:183-201`). `BlockedPeriod` uses only snake_case (`booking/blocked.go:48-55`) and `User` only camelCase (`internal/user/model.go:61-70`).
- **Duplicated writers:** four copies of the JSON writer (`writeJSON`, `writeBookingJSON`, `writeUserJSON`, `writeICalJSON`) and three of `clientIP`.
- **Unbounded list:** `GET /bookings` with no range returns every active booking ever made, past ones included (`booking/projection.go:127-162`).

**Recommendation**
Create an `internal/httpx` package with `Decode(w, r, dst)` (using `http.MaxBytesReader` and `DisallowUnknownFields`), `JSON`, `Error(w, err)` that maps sentinel errors to status and a *stable code* and logs everything else as 500 "internal error", and `ClientIP`. Have the middleware use it. Choose one key style (the frontend seems to use camelCase) and remove the duplicates after checking the frontend. Default `GET /bookings` to `from=now-7d` and require `to - from <= 1 year`.

### BE-13 — AI-generated drift: aliases, duplicated boilerplate, dead code (Medium, M)

**Evidence**
- **Aliases:** `grep -i alias` finds 35 alias declarations in non-test code. Examples:
  - `UsersProjection` has `GetByID`, `ByID`, `Find`, `Get` and `GetByEmail`, `ByEmail`, `FindByEmail` (`internal/user/projection.go:269-328`).
  - `UserService.ChangeUserRole` has four aliases and takes `role any` (`internal/user/service.go:254-307`).
  - `ical` exports `RenderFeed`, `Render`, `RenderICal` and five handler aliases (`internal/ical/feed.go:36-38`, `ical/http.go:117-174`).
- **Error alias families:** `ErrForbidden = ErrPermissionDenied = ErrNotAuthorized = ErrAccessDenied` and similar (`internal/user/model.go:79-113`), and `userHTTPStatus` checks each alias with `errors.Is` (`user/http.go:51-60`).
- **Structural oddities:**
  - A self-referencing field `UsersProjection.Users` set to `p.Users = p` (`user/projection.go:18,123`).
  - Three fields that hold the same service, `Deps.ICal`, `ICalService` and `CalendarTokenService`, resolved by `icalServiceFromDeps` (`internal/server/server.go:34-36,98-106`).
  - `sidecar.NewClient(baseURL string, opts ...any)` with a type switch (`internal/sidecar/client.go:26-40`).
  - Package-level globals `defaultUsers`, `defaultChanges` and `defaultTokens` mutated by `Register` (`user/commands.go:120-130`, `ical/commands.go:33-38`).
- **Duplicated boilerplate:** 17 copies of the value/pointer command type switch (`grep "command is nil"`), and three identical `NewID()` (`booking/model.go:79`, `user/model.go:145`, `broadcast/broadcast.go:84`). Their `rand.Read` error fallback is dead on Go 1.26 (`go.mod:3`), and if it ever ran it would produce `"booking-<nanos>"`, which can't be inserted into a `UUID` column. That would be a poison event (BE-01).
- **Leftover comments:** comments such as `// accept "true"/"1" loosely? test uses "true"` (`internal/config/config.go:64`) and `// wrap code? errors.Is enough; message includes code maybe` (`sidecar/client.go:112`).
- **Import grouping** is inconsistent (`user/model.go:3-10`, `user/http.go:3-10` mix the standard library and module imports in one block).

**Why it matters**
Each model added a synonym instead of finding the existing name. The public surface keeps growing, test fakes must implement several names, and reviewers cannot tell which name is canonical. This is the clearest maintainability cost of the "many cheap models" factory.

**Recommendation**
Run a one-time cleanup PR: delete the aliases (the compiler will find callers), keep one sentinel per meaning, and remove `defaultUsers`/`RoleOf` globals. Add a generic helper:
```go
func As[T command.Command](cmd command.Command) (T, error) {
    switch c := any(cmd).(type) {
    case T:  return c, nil
    case *T: if c != nil { return *c, nil }
    }
    var zero T
    return zero, fmt.Errorf("command: expected %T, got %T", zero, cmd)
}
```
Use `github.com/google/uuid` instead of the three `NewID`s. Add `golangci-lint` (`dupl`, `revive:exported`, `gci`, `unused`) to Backend CI, and add an AGENTS.md rule: "never add alias functions or errors; rename callers instead."

### BE-14 — Test suite gaps (Medium, M)

**Evidence**
- CI runs `go test ./...` without `-race` (`.github/workflows/backend-ci.yml`), although the runner, limiter, worker and lock code are concurrent.
- The Postgres pool helper is copied 11 times (`newBookingTestPool`, `newAuthTestPool`, `newE2EPool`, …), and each package starts its own `postgres:16` container. With `DATABASE_URL` set, every package shares one database with no schema isolation or truncation, so tests that assert counts (`SELECT count(*) FROM bookings …`) can interfere when packages run in parallel.
- `TestNoUpdateOrDeleteAgainstEvents` greps the source of `eventstore.go` for `UPDATE EVENTS` (`internal/eventstore/surface_test.go`). It is a tautological guard that any other file can bypass.
- Untested: out-of-order commits (BE-01), projection failure in one projection, publish failure after append (BE-03), lock-pool starvation (BE-02), notifier loss, the sidecar midnight boundary, email timezone, rate limiting behind a proxy.
- On the positive side, the booking concurrency tests, notification Postgres tests and e2e flows use real Postgres and assert behavior rather than mocks.

**Recommendation**
Add `-race` and `-shuffle=on`. Extract `internal/testutil/pg.go` with a single container per `TestMain` and a fresh schema per test (`CREATE SCHEMA t_<rand>; SET search_path`). Add the regression tests listed above, starting with BE-01's out-of-order commit test.

### BE-15 — `sample` scaffolding registered in production (Low, S)

**Evidence**
`sample.Register(app)` runs in production `main` (`cmd/server/main.go:68`). Its projection is in every `Handle`, so every event costs an extra checkpoint read and write. Migration `0003_create_sample_items.sql` creates the `sample_items` table, and `projection_checkpoints` has a `sample_items` row. The sidecar still exposes `POST /functions/echo` (`projects/sauna/sidecar/internal/server/server.go:44`).

**Recommendation**
Remove the `sample` package and the `main.go` call. Keep 0003 in place, since migrations shouldn't be deleted, and add a later migration `DROP TABLE IF EXISTS sample_items; DELETE FROM projection_checkpoints WHERE projection_name='sample_items';`. This affects only derived data, not events. Move the "how to add a projection" example into `product/backend/README.md`.

### BE-16 — Config handling (Low, S)

**Evidence**
- An invalid `PORT` or `SMTP_PORT` silently falls back to the default (`internal/config/config.go:35-46`). `DEV_MODE` has an odd two-step parse (`config.go:59-67`).
- `Config.PublicBaseURL` is loaded but never used. `ical/http.go:187` reads `os.Getenv("PUBLIC_BASE_URL")` directly and otherwise builds URLs from `X-Forwarded-Host` (`ical/http.go:198`, a brief security note).
- If `DATABASE_URL` is empty, the server still starts, every route returns 503 and `/healthz` returns `ok` (`cmd/server/main.go:54`, `internal/server/server.go:46` `handleHealthz` returns a constant).
- The SMTP password is a plain field on a struct that gets passed around. It isn't logged today.

**Recommendation**
Have `config.Load() (Config, error)` validate everything. Require `DATABASE_URL` and `PUBLIC_BASE_URL` outside dev mode. Pass `PublicBaseURL` into `ical.HandleRegenerateToken`. Add `/readyz`, which pings the database and the sidecar, and keep `/healthz` for liveness.

### BE-17 — Observability gaps (Low, M)

**Evidence**
- There are spans for `command.execute` and `projection.apply`, and `otelhttp` on the server (`internal/command/service.go:78`, `internal/projection/runner.go:138`, `internal/server/server.go:90`).
- There is no pgx tracer, so the lock wait in BE-02 is invisible. The sidecar client and `/chrome` use plain `http.Client` and `http.DefaultClient` without `otelhttp.NewTransport`, so traces stop at the sidecar (`internal/sidecar/client.go:29`, `server/server.go:188`).
- `slog` logs carry no `trace_id`.
- `notifications.pending` is an in-process UpDownCounter that starts at 0 on every boot and goes negative once rows from before a restart are sent (`internal/notification/outbox.go:94-111`).
- There is no metric for projection lag or errors, and none for outbox depth or oldest pending age.

**Recommendation**
Add `github.com/exaring/otelpgx` to the pool config, `otelhttp.NewTransport` to both sidecar clients, and an `slog.Handler` wrapper that adds `trace_id` and `span_id`. Replace `pending` with an observable gauge that queries `SELECT status, count(*), min(created_at) … GROUP BY status` every 30 s. Export `projection.checkpoint_lag = max(events.id) − checkpoint` per projection.

### BE-18 — Performance hotspots (Low, M)

**Evidence**
- Every command takes the global `Runner.mu` (`runner.go:57-61`), and for each of the 8 projections runs `checkpoints.Get`, then `Apply` and `checkpoints.Set` per event (`runner.go:140-159`). That is about 24 sequential round-trips per command, even for a login code request that only touches `login_codes`, and it serializes every write in the process.
- `CatchUp` and `Rebuild` load the whole log into memory with `LoadAll` (`eventstore.go:174-183`). Auth events (BE-11) will dominate it.
- The iCal feed renders every active booking since the beginning on every poll (`ical/http.go:80`), and so does `GET /bookings` without a range.

**Recommendation**
Let projections declare the event types they handle (`Handles() []string`) and skip both `Apply` and `Set` for others. Advance the checkpoint lazily or batch it in the BE-01 transaction. Stream catch-up in pages (`WHERE id > $1 ORDER BY id LIMIT 1000`). Bound the feed to `now−30d … now+1y`. None of this is urgent at HOA scale. It matters once the product is reused for other deployments.

### BE-19 — Domain gaps (Low, S)

**Evidence**
- `user.removed` only flips `active` (`internal/user/projection.go:152-163`). The removed user's future bookings stay active and keep blocking slots, and no projection reacts.
- A blocked period is never checked against existing bookings (`internal/booking/blocked.go:73-119`). Blocks can't be lifted (there is no `blocked_period.lifted` event; a compensating event would be allowed under "no deletes"). There is no check that a block isn't in the past.
- Without a sidecar there is no upper bound on booking length or horizon (`internal/booking/model.go:95-105` checks only `start < end` and `start > now`).
- `ChangeUserRole` lets an admin demote the last admin, including themselves, or promote anyone to admin, although the spec says admin is "the system owner only". It also allows role changes on deactivated users (`user/commands.go:578-637`).
- The `STATUS:CANCELLED` branch in the feed is dead code, because the feed lists only active bookings (`ical/feed.go:25-29`, `booking/projection.go:127`).

**Recommendation**
Add an `on user.removed` policy that issues `CancelAnyBooking` for that user's future bookings, as a process manager driven by the checkpointed runner. Have `BlockTimePeriod` return conflicting bookings so the super user can choose to cancel them. Add `LiftBlockedPeriod`. Forbid demoting the last admin.

### BE-20 — Append-only by convention only; rebuild can't be triggered in operation (Low, S)

**Evidence**
- Nothing in the database stops `UPDATE` or `DELETE` on `events`. The only guard is the source-grep test (BE-14).
- `Runner.Rebuild` and `RebuildAll` exist (`internal/projection/runner.go:75-116`) but are called only from tests. There is no CLI flag or admin endpoint. `Reset` runs `TRUNCATE` on live tables before the replay (`booking/projection.go:68-73`), so readers briefly see empty data.

**Recommendation**
Add a migration with `CREATE TRIGGER events_append_only BEFORE UPDATE OR DELETE ON events FOR EACH ROW EXECUTE FUNCTION raise_exception();`, and optionally run the app as a role with only `INSERT, SELECT` on `events`. Add `server -rebuild=<name|all>` as a one-shot mode. Wrap `Reset` and the replay in one transaction (with BE-01 #3 this is straightforward), or build into a shadow table and swap.

## Prioritized roadmap

**Now (this week, mostly S effort, removes silent data loss and outages)**
1. BE-05: forward the real client IP from Caddy and use it everywhere. Prune limiter windows.
2. BE-01 (part 1): add `pg_advisory_xact_lock` in `Append` so IDs are ordered by commit. Make `Handle` pull `events WHERE id > checkpoint` instead of trusting the batch. Isolate projection failures and don't `os.Exit` on catch-up.
3. BE-03: return success once the append has committed. Log and retry projection or notify failures.
4. BE-02 (stopgap): set `pool_max_conns` (for example 20) and `SET lock_timeout` on the lock connection, returning 503 on timeout.
5. BE-06: raise the retry window to hours, and add SMTP dial and IO timeouts.
6. BE-08: add `DISPLAY_TIMEZONE` and format email times in it.

**Next (this month, the structural fixes)**
1. BE-01 (part 2) and BE-02: a transaction-aware command path, where the lock, decision, append, projection and checkpoint run in one transaction. Delete the session-level `Lock`.
2. BE-04: make notifiers checkpointed projections, or enqueue in the append transaction. Put the owner's user ID in `booking.cancelled`.
3. BE-10: versioned migrations, before any of the schema changes below.
4. BE-07: `stream_version` + unique index, `schema_version` + `metadata`, and reservation streams for email uniqueness.
5. BE-14: `-race`, a shared test harness, and regression tests for BE-01, BE-02 and BE-03.
6. BE-09: contract v1 with user context; remove the hard-coded capacity; fix the midnight bug.

**Later (quality and scale)**
1. BE-13 and BE-12: the alias and boilerplate cleanup plus an `httpx` package. Add golangci-lint to CI and an AGENTS.md rule against aliases.
2. BE-11: identity keyed on user ID, a logout/revoke event, and an ADR on keeping credentials out of the log.
3. BE-17: otelpgx, sidecar propagation, log–trace correlation, lag and outbox gauges.
4. BE-15, BE-16, BE-19, BE-20: remove `sample`, validate config and add `/readyz`, close the domain gaps, add the append-only trigger and a rebuild CLI.
5. BE-18: event-type filtering per projection and paged catch-up, before the product is reused for another deployment.

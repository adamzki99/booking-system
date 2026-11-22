# Observability and project insights: SigNoz, APM and factory telemetry

**Scope:**
- **SigNoz stack:** `dev-ops/signoz/**` (compose, collector config, ClickHouse config, server prometheus/opamp config, README)
- **Factory telemetry:** `dev-ops/factory/otel-collector.yaml`; event emission in `dev-ops/factory/tick.sh` and `dev-ops/factory/lib/factory.py`; `factory-tick.logrotate`
- **Backend instrumentation:** `product/backend/internal/telemetry/telemetry.go` and the code that uses it (`server`, `command`, `projection`, `notification`, `sidecar`)
- **Wiring:** the OTEL settings in `projects/sauna/docker-compose.yml`, `.env.example` and `dev-ops/scripts/deploy-environment.sh`

**Reviewed** 2026-11-19 at commit `45f6ee5`. Static reading of the local clone only.

**Questions answered:**
1. What actually reaches SigNoz?
2. Is SigNoz configured deterministically, so a fresh host gets the same setup on first start?
3. Does it give enough insight from a **project-management** perspective (ticks, sessions, models, skills, cost, delivery flow)?
4. Is the **APM** configuration sufficient for the booking system itself?

**Related findings:** OPS-12/OPS-13 (host overcommit and exposed ports) and SEC-12 (SigNoz exposure, tokens in traces) are in reports 03 and 06. BE-17 (backend observability gaps) is in report 04. FAC-13 (session-ID capture bug, no outcome or cost metrics) is in report 02. This report goes deeper on the telemetry model and doesn't repeat their fixes.

## Summary

SigNoz is a solid start for a two-week-old project:

- The stack is a separate, persistent compose project.
- Images are pinned by tag.
- Startup is ordered by health checks.
- Memory limits fit the 3.2 GB host.
- Host metrics are collected.
- The backend exports OTLP traces and metrics, with HTTP server spans, `command.execute` and `projection.apply` spans, and notification counters.

**For a project manager, though, SigNoz can answer almost none of the questions that matter.** The factory sends only flat log events, and only if a log shipper was installed by hand; nothing in the repo installs it. Those events carry tick and session timing and model names. They carry **no tokens or cost, no skills or tools used, no link to the OpenCode session** (the session-ID parser is broken), and no PR, CI or merge outcome. Nothing reports deploys, and nothing ties issues or PRs to sessions.

**SigNoz itself is only half deterministic.** The infrastructure is in code. Everything that makes it *useful* lives only in a Docker volume: users, dashboards, alerts, retention and notification channels. Today none of these exist in the repo, so a fresh host comes up as an empty SigNoz with an unclaimed admin signup on a public port.

**APM is basic.** It gives request rate, error rate and latency per service, but there are no database, sidecar or SMTP client spans, no logs, no version or environment attributes, no business or event-sourcing metrics, and nothing from the sidecar or frontend.

**What's working well**

- **A persistent, isolated stack:** compose project `name: signoz` with named volumes, unaffected by booking redeploys (`docker-compose.yml:20,228-236`).
- **Pinned versions and an ordered start:** ClickHouse `25.5.6`, SigNoz `v0.96.1`, collector and migrators `v0.129.6`, with `depends_on` health and completion conditions (`docker-compose.yml:31-57,193-195`).
- **Resource discipline:** container memory limits plus `memory_limiter` first in every pipeline (`otel-collector-config.yaml:35-38,95-110`).
- **SigNoz phone-home disabled** (`TELEMETRY_ENABLED=false`, `:147`).
- **Host metrics with a correct `/hostfs` setup** (`:173-183`, `otel-collector-config.yaml:11-21`).
- **Span-derived RED metrics** via `signozspanmetrics/delta`, with `deployment.environment` and `service.version` dimensions ready to use (`otel-collector-config.yaml:46-67`).
- **A versioned factory event schema:** `schema_version`, `tick_id`, `service.name`, `deployment.environment`, `host.name`, and about 30 event types including fallback-chain events (`usage_filled`, `backup_retry`, `free_retry`). `tick_start` records `opencode_version` (`tick.sh:220`).
- **Backend export is optional:** no endpoint means no-op providers (`telemetry.go:26-29`). `deploy-environment.sh:335-347` fills in the endpoint for QA.

## What reaches SigNoz today

| Source | Signal | How | Content | Reaches SigNoz? |
|---|---|---|---|---|
| Ubuntu host | Metrics | `hostmetrics` receiver in the SigNoz collector | CPU, memory, disk, filesystem, load, network, processes every 30 s | **Yes**, while SigNoz runs |
| SigNoz collector | Metrics | `prometheus` self-scrape of `:8888` | Collector internals | Yes |
| Booking backend (QA) | Traces | OTLP/HTTP `otelhttp` server spans, plus `command.execute` (`command/service.go:78`) and `projection.apply` (`projection/runner.go:138`) | One span per request, with a static operation name (`server.go:90`) | Yes, if the QA `.env` has the endpoint |
| Booking backend | Metrics | OTLP/HTTP | `notifications.{enqueued,sent,retried,failed,enqueue_failed,pending}` (`notification/outbox.go:84-95`), plus span metrics derived in the collector | Yes |
| Booking backend | Logs | `slog`, to stdout only | – | **No.** No OTLP log exporter, and Docker logs aren't collected. |
| Sidecar | – | No OpenTelemetry code | – | **No** |
| Frontend | – | No RUM or web-vitals | – | **No** |
| Postgres, Caddy, Authelia | – | No receivers | – | **No** |
| Factory `tick.sh` | Logs | JSONL file → `otelcol-contrib` `filelog` → OTLP (`factory/otel-collector.yaml`) | About 30 event types: tick start/end/result, session start/ok/failed, usage and fallback, claims, discovery errors | **Unknown.** It needs a manually installed user systemd unit that isn't in the repo (OBS-02). |
| Factory sessions (OpenCode) | – | The JSON stream goes to `/tmp/opencode/factory-*.log` and is deleted on success | Tokens, tool and skill calls, steps | **No** |
| QA deploys | – | `deploy-environment.sh` emits nothing | – | **No** |
| GitHub (issues, PRs, CI) | – | – | – | **No** |

## Project-management insight: what you can and can't answer

| Question | Answerable in SigNoz today? | Why |
|---|---|---|
| Did the factory tick every hour, and how long did ticks take? | **Partly** | `tick_start`/`tick_end` with `duration_ms`, but only if the shipper is running. There's no alert for a missing tick. |
| How many plan, build and fix sessions ran, on which model, and did they succeed? | **Partly** | `session_*` events with `kind`, `model`, `outcome`, `duration_ms`. But "ok" only means exit code 0, not "PR merged" (FAC-13). |
| How often do we hit the OpenCode Go quota, and how often do backup or free models run? | **Partly** | `usage_filled`, `backup_retry`/`backup_ok`, `free_retry`. False positives come from transcript scanning (FAC-07). |
| How many tokens, and how much money or quota, per issue, model or tier? | **No** | Not captured. The OpenCode JSON output with usage data is written to a session log that's deleted on success (`FACTORY_PRESERVE_SESSION_LOGS=on-failure`). |
| Which skills and tools did agents use, and do they help? | **No** | Not captured. `session_id` is always empty (`tick.sh:763`: a `python3 -c` with literal `\n` inside single quotes is a syntax error), so events can't even be joined to OpenCode's own session store. |
| Which agent ran? | **No** | `session_start` has `kind` and `model` but no `agent` field (`tick.sh:753-755`). |
| Lead time from issue to merge; queue depth by state (infant, planned, approved, in PR, blocked) | **No** | GitHub state is never emitted. |
| Rework: fix sessions per PR, CI failures per PR, PRs that stalled | **No** | `fix_selected` has a PR number, but merge and CI outcomes are never recorded. |
| Escaped defects: bugs traced back to a factory PR | **No** | – |
| Which commit is deployed in QA, did the deploy succeed, and did errors rise after it? | **No** | No deploy events, and the backend reports no `service.version` or `deployment.environment`. |
| Is the box healthy (memory, disk) while factory and QA share it? | **Host only** | No per-container metrics, so you can't tell whether OpenCode, ClickHouse or the backend is eating memory. |

## Is SigNoz configured deterministically?

| Aspect | In repo? | Deterministic on a fresh host? |
|---|---|---|
| Service topology, images, start order, limits, volumes | Yes | **Yes** (tags; no digests) |
| ClickHouse config, collector pipelines | Yes | Yes |
| `histogramQuantile` UDF | Downloaded at startup from GitHub with `wget`, no checksum (`docker-compose.yml:74-82`) | **No.** Needs internet; integrity unchecked. |
| `host.name` in the Hosts view | `resourcedetection: [env, system]` running *inside* the collector container, which has no `hostname:` (`otel-collector-config.yaml:43-45`, `docker-compose.yml:156-195`) | **Likely no.** The system detector probably reports the container's hostname, which changes when the container is recreated. Not verified on a running instance. |
| Admin user and organisation | No | **No.** The first visitor to `:3301` (published on all interfaces) creates the admin. |
| Dashboards, saved views, alerts, notification channels | No (stored in the `signoz-sqlite` volume) | **No.** Manual and lost on a rebuild. |
| Retention (traces, logs, metrics TTL) | No | **No.** SigNoz defaults apply, set through the UI. |
| Factory log shipper (`otelcol-contrib`) | Config only; no unit file, install script or pinned version | **No** |
| Starting SigNoz itself | README command only; no systemd unit or installer, and the deploy script doesn't ensure it | **No** (manual, then `restart: unless-stopped`) |
| Server config | `prometheus.yml` points at `alertmanager:9093`, which doesn't exist (`signoz/prometheus.yml:6-10`); the built-in alertmanager is selected by env (`:142`) | Harmless leftover, but misleading |

**Verdict:** the *plumbing* is reproducible; the *product* (users, dashboards, alerts, retention, shippers) is not.

## Findings

| ID | Severity | Effort | Title |
|---|---|---|---|
| OBS-01 | High | M | Factory telemetry can't answer cost, skill, outcome or flow questions |
| OBS-02 | High | S | The factory log shipper isn't installed by anything in the repo, so factory telemetry may never reach SigNoz |
| OBS-03 | High | M | SigNoz users, dashboards, alerts and retention aren't provisioned as code |
| OBS-04 | High | S | No alerting on anything: a silent factory, a failed deploy or a full disk all go unnoticed |
| OBS-05 | Medium | S | The `session_id` join key is always empty and `agent` isn't recorded |
| OBS-06 | Medium | S | Deploys aren't observable, and the backend carries no version or environment |
| OBS-07 | Medium | M | Backend APM lacks database, sidecar and SMTP spans, logs, route names and runtime metrics |
| OBS-08 | Medium | M | There are no business or event-sourcing health metrics |
| OBS-09 | Medium | S | No per-container, Postgres or Caddy metrics on a memory-starved shared host |
| OBS-10 | Medium | S | Factory events are logs with flat attributes rather than traces and metrics |
| OBS-11 | Medium | S | Telemetry can carry secrets and PII (session output tails, iCal tokens in URLs) |
| OBS-12 | Low | S | Fresh-host reproducibility gaps: unverified UDF download, unstable `host.name`, stale alertmanager target |
| OBS-13 | Low | S | Fragile shipper settings: `start_at: end` with no offset storage, and an unverified timestamp layout |
| OBS-14 | Low | M | The sidecar and frontend are invisible |

### OBS-01 - Factory telemetry can't answer cost, skill, outcome or flow questions (High, M)

**Evidence**
- The session events carry `kind`, `issue`/`pr`, `model`, `exit_code`, `duration_ms`, `outcome`, `session_id` and an optional `output_tail` (`tick.sh:753-904`). Nothing else.
- The OpenCode output is captured (`run_opencode … --format json`, `tick.sh:707,759`, teed to `factory-<kind>-<ref>.log`) but never parsed for usage. With the default `FACTORY_PRESERVE_SESSION_LOGS=on-failure`, it is deleted after every successful session (`dev-ops/factory/README.md`).
- No event records labels or tier, skills loaded, tools called, files changed, PR number for build sessions, CI result, merge result, or the time from approval to merge.

**Why it matters:** the factory is the product's development team. On a usage-limited OpenCode Go plan, the core management questions are *cost per delivered issue*, *which models and skills deliver*, *where work stalls*, and *how much rework happens*. None of them can be answered, so `models.yaml` and the skill set (report 07) get tuned blind.

**Recommendation:** define a factory telemetry model and emit it from `tick.sh`. Ideally move it into the Python orchestrator from FAC-17.

1. **Parse the OpenCode JSON stream** at session end, before the log is deleted. Sum tokens (input, output, reasoning, cache read and write) and cost from the step-finish events. Count tool calls by tool name, and list the names passed to the `skill` tool. Verify the exact event and field names against the OpenCode version on the box. Then add to `session_*`:
   `agent`, `tier_label`, `area_labels`, `fallback_level` (primary/backup/free), `tokens_in`, `tokens_out`, `tokens_reasoning`, `tokens_cache_read`, `cost`, `tool_calls`, `skills_loaded` (comma-separated), `files_changed`, `pr`, `prompt_version` (a hash of the prompt template and the agent file).
2. **Record delivery outcomes.** At the end of each tick, `tick.sh` already queries GitHub. Emit `pr_opened`, `ci_result` (per required check), `pr_merged` (with `issue_approved_at` and `merged_at`, giving lead time), and `issue_blocked`.
3. **Queue snapshot per tick.** Emit `factory_queue` with counts of infant, planned, approved-not-started, in-PR, blocked and needs-info issues.
4. Keep `schema_version` and bump it to 2.

### OBS-02 - The factory log shipper isn't installed by anything in the repo, so factory telemetry may never reach SigNoz (High, S)

**Evidence**
- `factory/otel-collector.yaml:1-4`: "Runs as a user systemd unit on the cron host". `dev-ops/factory/README.md` (Observability) says to ship via `otelcol-contrib` "running as a **user** systemd unit".
- `grep otelcol` across the repo finds only the README. There is no unit file, no installer, no pinned `otelcol-contrib` version, and no health check.
- By contrast, the QA deploy timer *is* installed by script (`install-deploy-timer.sh`).

**Why it matters:** nobody can tell from the repo whether any factory event has ever reached SigNoz. A fresh host certainly won't ship them.

**Recommendation:**
- Add `dev-ops/factory/install-telemetry.sh`, modeled on `install-deploy-timer.sh`. It should download a **pinned** `otelcol-contrib` release with a checksum (or run the `otel/opentelemetry-collector-contrib:<ver>` image under the existing `signoz` compose project), write `~/.config/systemd/user/factory-otelcol.service` with the env from a gitignored file, and enable it.
- **Simpler alternative:** mount the factory's JSONL file read-only into the existing SigNoz collector and add a second `filelog` pipeline there. One collector, already deterministic, with nothing extra to install.

### OBS-03 - SigNoz users, dashboards, alerts and retention aren't provisioned as code (High, M)

**Evidence:** none of these exist under `dev-ops/signoz/`. SigNoz keeps them in SQLite on the `signoz-sqlite` volume (`docker-compose.yml:140,144`). The UI port is published on all interfaces (`:137`), so the first visitor completes the admin signup.

**Why it matters:** rebuilding the host, or standing up a second environment, gives an empty SigNoz. Whatever someone set up by hand is lost, and there is no review trail for alert thresholds.

**Recommendation:** treat SigNoz content as code.

```
dev-ops/signoz/
  provision/
    dashboards/factory-overview.json  delivery-flow.json  model-cost.json
               agent-behaviour.json   qa-apm.json         event-sourcing.json  host-containers.json
    alerts/    factory-silent.json  session-failure-rate.json  usage-filled.json
               deploy-failed.json   backend-5xx.json  outbox-failed.json
               projection-lag.json  host-memory.json  host-disk.json
    retention.json        # e.g. traces 7d, logs 14d, metrics 30d - sized for the host's disk
    provision.sh          # idempotent: wait for /api/v1/health, register admin from .env if no user,
                          # obtain API key/token, upsert dashboards/alerts by title, set retention TTLs,
                          # create the notification channel (email/Slack/ntfy) from .env
```

- Run `provision.sh` as a one-shot `signoz-provision` service in the compose file (`depends_on: signoz-server: service_healthy`), so the same content appears on every first start and is reconciled on every restart.
- Export dashboards from the UI as JSON once, and edit them in git afterwards.
- The exact API endpoints and auth flow differ between SigNoz versions, so pin them to `v0.96.1` and verify on the box.
- Bind `:3301` to `127.0.0.1` (OPS-13) so nobody claims the admin account first.

### OBS-04 - No alerting on anything: a silent factory, a failed deploy or a full disk all go unnoticed (High, S)

**Evidence**
- No alert rules exist (`prometheus.yml:12` has `rule_files: []`, and none are provisioned).
- Deploy-failure notification is a GitHub issue under the owner's own identity, which never notifies the owner (OPS-01).
- Issues #85, #86 and #89 show QA deploys were broken for a while without anyone noticing (from GitHub metadata, report 03).

**Recommendation:** provision a minimal alert set (OBS-03), sent to a channel the owner actually reads, such as email, ntfy or a Slack webhook:

| Alert | Condition |
|---|---|
| Factory silent | No `tick_end` event for 2 h |
| Factory failing | `session_failed` / `session_*` above 50 % over 6 h, or any `discovery_failed` |
| Quota | Any `usage_filled`; or `free_retry` more than 2 in 24 h |
| Deploy | `deploy_failed` (OBS-06), or no `deploy_ok` for 26 h on an active day |
| QA errors | Backend 5xx above 2 % for 10 min, or p95 above 1 s |
| Event sourcing | `notifications.failed` rises, projection lag above N events (OBS-08) |
| Host | Memory above 90 % for 10 min, any filesystem above 85 %, no hostmetrics for 5 min (collector down) |

### OBS-05 - The `session_id` join key is always empty and `agent` isn't recorded (Medium, S)

**Evidence**
- `tick.sh:763` passes a multi-line Python program to `python3 -c` inside single quotes, with literal `\n` sequences. Python receives one line containing backslash-n, which raises `SyntaxError`, and `2>/dev/null` hides it. So `session_id` is empty on every event. (This is FAC-13, confirmed by reading the code.)
- `session_start` lacks `agent` (`tick.sh:753-755`).

**Recommendation:** move the parsing into `lib/factory.py` (`factory.py session-id <logfile>`) with a unit test, and add `agent="$agent"` to every `session_*` event. With `session_id` populated, any session can be opened in OpenCode's own store to see its full transcript, tokens and tool calls (`opencode session` commands or the export, depending on the version).

### OBS-06 - Deploys aren't observable, and the backend carries no version or environment (Medium, S)

**Evidence**
- `deploy-environment.sh` writes no telemetry; its only outputs are a commit to `main` and a GitHub issue on failure (report 03).
- The backend resource sets only `service.name` (`telemetry.go:36-38`). The collector's span-metric dimensions `service.version` and `deployment.environment` (`otel-collector-config.yaml:54-59`) therefore fall back to `default`.

**Why it matters:** you can't see "error rate went up after deploy X", tell QA apart from future release environments, or measure deploy frequency and failure rate (two of the four DORA metrics).

**Recommendation:**
- In `deploy-environment.sh`, emit `deploy_start`, `deploy_ok` and `deploy_failed` events (env, commit, previous commit, duration, failed step, health result) into the same JSONL and shipper path.
- Pass the version and environment to the backend:

```yaml
# projects/sauna/docker-compose.yml (backend)
OTEL_RESOURCE_ATTRIBUTES: "service.version=${DEPLOY_COMMIT:-unknown},deployment.environment=${ENV_NAME:-local},service.namespace=booking"
```

```go
// telemetry.go: honour OTEL_RESOURCE_ATTRIBUTES and add host/process/runtime info
res, err := resource.New(ctx,
    resource.WithFromEnv(), resource.WithHost(), resource.WithProcess(), resource.WithTelemetrySDK(),
    resource.WithAttributes(semconv.ServiceName(serviceName)))
```

### OBS-07 - Backend APM lacks database, sidecar and SMTP spans, logs, route names and runtime metrics (Medium, M)

**Evidence**
- `server.go:90` wraps the whole mux as `otelhttp.NewHandler(NewMux(deps), "http")`, so every server span shares the operation name `http`. Whether `http.route` is filled from the Go 1.22 mux pattern depends on the otelhttp version (`v0.72.0`, `go.mod:9`); not verified.
- `go.mod` has no `otelpgx` or other pgx tracer. The sidecar client doesn't use `otelhttp.NewTransport` (`grep` finds no `otelhttp` in `internal/sidecar/client.go`), so trace context doesn't reach the sidecar.
- No OTLP log exporter or `slog` bridge, so logs aren't correlated with traces. No Go runtime metrics. All of this matches BE-17.

**Recommendation:**
- **Route names:** `otelhttp.NewHandler(mux, "http", otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string { return r.Method + " " + r.Pattern }))`.
- **Database spans:** `otelpgx.NewTracer()` on the pgx pool config.
- **Sidecar client:** `otelhttp.NewTransport` on its `http.Client`, plus span attributes for the rule evaluated and its result.
- **Email:** an SMTP send span in `email/smtp_sender.go`.
- **Logs:** `otelslog` bridge plus `otlploghttp`. Add a logs pipeline exporter (the collector already has `logs` with `clickhouselogsexporter`) and include `trace_id` in stdout logs too.
- **Runtime metrics:** `go.opentelemetry.io/contrib/instrumentation/runtime` for goroutines, GC and heap, which matters on a 512 MB container.

### OBS-08 - There are no business or event-sourcing health metrics (Medium, M)

**Evidence:** the only custom metrics are the six notification counters (`outbox.go:84-95`), and `notifications.pending` is wrong after a restart (BE-17). There are no counters for events appended, bookings created or cancelled, logins, or rejected double bookings, and no projection-lag or checkpoint metrics, even though the projection runner can silently skip events (BE-01).

**Why it matters:** for an event-sourced system, *projection lag* and *events appended vs. applied* are the two numbers that tell you the read side is correct. For the HOA, *bookings per week* and *login success rate* are the product KPIs.

**Recommendation:** add a small `metrics` package.

- `events.appended{type}` counter in `command.Service`
- `projection.checkpoint{projection}` gauge, plus `projection.lag{projection}` = head event ID − checkpoint, observed in the runner
- `projection.errors{projection}` counter
- `bookings.created`, `bookings.cancelled`, `bookings.rejected{reason}` (double booking, blocked, sidecar rule)
- `auth.codes_issued`, `auth.logins{result}`, `ratelimit.rejected{limiter}`
- `sidecar.requests{result}` with a latency histogram

Put them on an "Event sourcing" and a "Product" dashboard (OBS-03).

### OBS-09 - No per-container, Postgres or Caddy metrics on a memory-starved shared host (Medium, S)

**Evidence**
- `hostmetrics` only (`otel-collector-config.yaml:11-21`). The README notes the host has about 3.2 GB of RAM (`signoz/README.md:104`).
- Memory limits were added after OOM pressure (#136, from git history).
- The factory (OpenCode, `go test`, `npm`), QA (Postgres, backend, frontend, sidecar, Caddy, Authelia) and SigNoz (ClickHouse, ZooKeeper, server, collector) all share the box (OPS-12).

**Recommendation:**
- Add a `docker_stats` receiver for per-container CPU and memory. It needs the Docker socket mounted read-only, which is a privilege trade-off; alternatively run cAdvisor scraped by the `prometheus` receiver.
- Add a `postgresql` receiver against the QA database with a read-only monitoring role.
- Enable Caddy's Prometheus `metrics` endpoint and scrape it.
- Add a `process` filter on the `processes` scraper to track `opencode` memory during sessions.

That gives a "Host & containers" dashboard that answers "who is eating the RAM during a factory session?"

### OBS-10 - Factory events are logs with flat attributes rather than traces and metrics (Medium, S)

**Evidence**
- `emit_event` writes one flat JSON object per event (`tick.sh:131-160`). The shipper parses it into **log attributes** (`json_parser`, `otel-collector.yaml:16-20`) and upserts only `service.name` on the resource (`:26-30`).
- `deployment.environment` and `host.name` stay as log attributes, so SigNoz's service and environment filters (which act on resource attributes) don't apply.
- Durations exist only as numbers inside log lines, so there are no histograms or rates without log-based queries.
- `emit_event … >/dev/null 2>&1 || true` (`tick.sh:133`) silently drops events when Python fails.

**Recommendation:**
- **Cheap path:** in the shipper, promote `deployment.environment`, `host.name` and `service.name` to resource attributes with the `transform` or `groupbyattrs` processor. Build log-based panels for counts by `event`, `kind`, `model` and `outcome`.
- **Better path:** emit a **trace per tick**. The root span is `factory.tick`, with child spans `factory.discovery`, `factory.plan`, `factory.build` and `factory.fix`, each carrying the OBS-01 attributes. Do it from the Python helper with the OTel SDK, or with `otel-cli` from bash. SigNoz then shows each tick as a waterfall, and span metrics give session-duration percentiles per `model` and `kind` for free.
- Count dropped events: write failures to stderr and add a `telemetry_errors` field to `tick_end`.

### OBS-11 - Telemetry can carry secrets and PII (session output tails, iCal tokens in URLs) (Medium, S)

**Evidence**
- `session_failed` includes `output_tail` (last 16 KiB of OpenCode output; `tick.sh:816-904`; README: `FACTORY_LOG_SESSION_OUTPUT=tail` is the default). That can include file contents, environment values or residents' data the agent read. It is shipped to SigNoz as a log attribute.
- Server spans for `/ical/<token>`-style URLs likely record the token in the URL path (SEC-12).
- `signoz/README.md:158-159` says host data contains "no secrets", but the factory and backend pipelines are not covered by that statement.

**Recommendation:**
- Default `FACTORY_LOG_SESSION_OUTPUT=metadata` for shipping, and keep tails only in the local file.
- Add a `redaction` or `transform` processor to both collectors to drop or mask `output_tail`, `url.full`/`url.path` on iCal routes, `user.email` and anything matching token patterns.
- Set retention (OBS-03) so PII doesn't sit in ClickHouse indefinitely (SEC-15).

### OBS-12 - Fresh-host reproducibility gaps: unverified UDF download, unstable `host.name`, stale alertmanager target (Low, S)

**Evidence**
- `docker-compose.yml:74-82` downloads `histogram-quantile` from GitHub releases at every init with no checksum, and the README says it "requires outbound network".
- The collector has no `hostname:`, and `resourcedetection` runs inside the container (`otel-collector-config.yaml:43-45`), so `host.name` is likely the container ID. It is also applied to the metrics pipeline only, not traces or logs (`:95-110`).
- `signoz/prometheus.yml:6-10` targets `alertmanager:9093`, which doesn't exist.
- Images are pinned by tag, not digest.

**Recommendation:**
- Verify the UDF tarball's SHA-256 in the init script, or vendor the binary per architecture.
- Set `hostname: ${HOST_HOSTNAME:-signoz-host}` on the collector, or `OTEL_RESOURCE_ATTRIBUTES=host.name=<stable>`, or use `resourcedetection` with `system: hostname_sources: [os]` reading the mounted `/hostfs/etc/hostname`. Add `resourcedetection` to all pipelines.
- Remove the stale alertmanager block.
- Pin images by digest (Dependabot's `docker` ecosystem can keep the digests fresh; see ST-07).

### OBS-13 - Fragile shipper settings: `start_at: end` with no offset storage, and an unverified timestamp layout (Low, S)

**Evidence**
- `factory/otel-collector.yaml:15` sets `start_at: end` with no `file_storage` extension. Every shipper restart skips events written while it was down, and the first start ships nothing historical.
- The timestamp is parsed with the strptime layout `%Y-%m-%dT%H:%M:%S.%fZ` (`:18-20`), while `tick.sh:147` writes milliseconds (`…T11:00:55.123Z`). Whether `%f` accepts 3 digits depends on the collector's strptime implementation. If it doesn't, the parse fails and events get ingestion time or are dropped. Not verified.

**Recommendation:** add `extensions: file_storage` with `storage: file_storage` on the receiver so offsets survive restarts, and use `start_at: beginning` for first-time backfill. Switch to `layout_type: gotime` with `layout: "2006-01-02T15:04:05.000Z07:00"`. Add a test that feeds one sample line through the collector (`otelcol validate` plus a fixture) in factory CI (FAC-18).

### OBS-14 - The sidecar and frontend are invisible (Low, M)

**Evidence:** no OpenTelemetry code under `projects/sauna/sidecar/` or `product/frontend-solid/src/` (grep).

**Recommendation:**
- **Sidecar:** wrap its handler with `otelhttp` and initialise the same telemetry package. Once OBS-07 adds `otelhttp.NewTransport` to the backend client, traces flow end to end, and you'll see rule-evaluation latency and failures. That matters because the sidecar fails open (BE-09).
- **Frontend:** a light RUM option is the OpenTelemetry web SDK with document-load and fetch instrumentation, sending to an OTLP path proxied by Caddy with a strict CORS and rate limit. Or simply log web-vitals to a backend endpoint. Keep this for later; residents are a small, known group.

## Proposed dashboard set (provisioned per OBS-03)

| Dashboard | Panels | Data needed |
|---|---|---|
| **Factory overview** | Ticks per day; tick duration; sessions by kind and outcome; failure rate; last tick age | Existing events (once OBS-02 is done) |
| **Delivery flow** | Queue by state per tick; issue lead time (approved → merged) p50/p90; PRs needing fixes; fix attempts per PR; stalled PRs | OBS-01 outcome and queue events |
| **Models & cost** | Tokens and cost per session, issue, tier and model; quota hits; backup/free share; success rate by model × tier | OBS-01 usage fields |
| **Agent behaviour** | Skills loaded (top N, and success rate when loaded); tool calls per session; sessions hitting the timeout; prompt_version vs. outcome | OBS-01 skills and tools fields |
| **QA service APM** | RED per route; p95/p99; error traces; DB and sidecar latency; deploy markers by `service.version` | OBS-06, OBS-07 |
| **Event sourcing & product** | Events appended by type; projection lag and errors; outbox enqueued/sent/failed/pending; bookings, cancellations, rejections; logins | OBS-08 |
| **Host & containers** | Host CPU, memory, disk; per-container memory; Postgres connections; ClickHouse disk use | OBS-09 |

## Prioritized roadmap

**Now (this week)**
1. OBS-02: get factory events flowing. The quickest route is a second `filelog` pipeline in the existing SigNoz collector, with the JSONL mounted read-only.
2. OBS-05: fix the `session_id` parser and add `agent` to session events.
3. OBS-04 (minimal): three alerts - factory silent, deploy failed, host disk/memory - to a channel the owner reads. Bind `:3301` to localhost first (OBS-03, OPS-13).
4. OBS-11: ship `metadata` only, and redact `output_tail`.

**Next (this month)**
5. OBS-01: parse OpenCode usage, skills and tools into session events. Add outcome and queue events.
6. OBS-03: a provisioning container plus dashboards, alerts and retention as JSON in git.
7. OBS-06: deploy events, plus `service.version` and `deployment.environment` on the backend.
8. OBS-07 and OBS-08: DB, sidecar and SMTP spans, route names, logs bridge, runtime metrics, event-sourcing and product metrics.
9. OBS-09: container, Postgres and Caddy metrics.

**Later**
10. OBS-10: a trace per tick.
11. OBS-12 and OBS-13: hardening (UDF checksum, stable `host.name`, digests, offset storage, timestamp layout test).
12. OBS-14: sidecar tracing, then optional frontend RUM.

## Limitations

- **Static reading only.** I read the local clone; I did not access the running SigNoz instance or the Ubuntu host. Whether dashboards, alerts, users or a factory shipper exist *on the box* today is unknown. This report states only that none of them are defined in the repo.
- **Some behaviour is inferred and should be checked on the host.** That covers the OpenCode JSON event field names, the otelhttp route attribute, the `%f` timestamp parsing, and the container `host.name`. Each is marked where it appears.

# Let's Encrypt TLS for dev/QA and prod

Each deployed environment (dev/QA, prod, ...) serves HTTPS with its own
Let's Encrypt certificate, issued and renewed by Caddy over ACME. Environments
never share a certificate or private key: each compose project keeps its own
ACME account and certificate store in its own `caddy-data` volume.

The stack involved:

- `projects/sauna/config/Caddyfile` — site address, ACME options, shared app
  snippet.
- `projects/sauna/docker-compose.yml` — publishes `80`/`443`, passes
  `SITE_ADDRESS`/`ACME_EMAIL`/`ACME_CA` to Caddy, and names the per-environment
  `caddy-data` volume.
- `projects/sauna/.env.example` — the non-secret variables documented here.

## How it works

- `SITE_ADDRESS` is the public FQDN (for example `qa.booking.example.com` for
  dev/QA and `booking.example.com` for prod). Caddy obtains and auto-renews a
  Let's Encrypt certificate for it using the **HTTP-01 challenge**, which
  requires port `80` to be reachable from the public internet and pointed at the
  host running Caddy.
- The ACME account is registered with the address in `ACME_EMAIL`.
- `ACME_CA` selects the ACME directory. It defaults to Let's Encrypt production;
  set it to the staging CA while validating the setup (see [Test with staging](#test-with-staging)).
- Certificate state is stored under `/data/caddy/certificates` inside the Caddy
  container (the `caddy-data` volume). Caddy renews automatically, by default
  around 30 days before expiry, and stores the new cert/keys in the same volume.
- The `:80` site block keeps serving plain HTTP on the health-check listener
  (`http://127.0.0.1:${PORT}/healthz`, used by `deploy-environment.sh`) without
  redirecting. Requests whose `Host` matches `SITE_ADDRESS` are auto-redirected
  HTTP→HTTPS by Caddy.

## Separate instances per environment

The deploy script (`dev-ops/scripts/deploy-environment.sh`) sets
`COMPOSE_PROJECT_NAME=booking-<env>`, which gives each environment its own
compose project and therefore its own `caddy-data` volume
(`booking-<env>-caddy-data`). Set a distinct `SITE_ADDRESS` and `ACME_EMAIL`
per environment so the ACME account and issued certificate are also distinct.
For example, dev/QA uses `SITE_ADDRESS=qa.booking.example.com` while prod uses
`SITE_ADDRESS=booking.example.com`. Never reuse one environment's `SITE_ADDRESS`
for another.

Verify the two environments hold different certificates:

```sh
openssl s_client -connect <host>:443 -servername <domain> -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -serial -subject -issuer -enddate
```

The serial number (and SANs) must differ between dev/QA and prod.

## Required DNS

For each environment, create a DNS `A` (and/or `AAAA`) record pointing the
`SITE_ADDRESS` FQDN at the public IP of the host that runs Caddy and publishes
port `80`/`443`. HTTP-01 requires that Let's Encrypt can reach
`http://<domain>/.well-known/acme-challenge/...` on port `80`.

## Test with staging

Issuance against production Let's Encrypt is rate-limited; always validate a
new domain against the staging CA first, in that environment's `.env`:

```dotenv
SITE_ADDRESS=qa.booking.example.com
ACME_EMAIL=ops@example.com
ACME_CA=https://acme-staging-v02.api.letsencrypt.org/directory
```

Then `docker compose up -d` and check `https://<domain>/healthz`. Staging
certs are untrusted by browsers/curl — use `curl -k` or inspect the issuer to
confirm issuance — then switch `ACME_CA` back to the production default and
redeploy.

## Rate limits

Let's Encrypt production rate limits include (approximate, subject to change —
see https://letsencrypt.org/docs/rate-limits/):

- **Certificates per registered domain:** ~50 per week.
- **Duplicate certificates:** ~5 per set of hostnames per week.
- **New orders per account:** ~300 per 3 hours.
- **Failed validation:** ~5 failures per account, per hostname, per hour.

Staging has much higher limits, which is why first issuance should go through
staging.

## Verification

```sh
# 1. Health endpoint over TLS
curl -fsSI "https://${SITE_ADDRESS}/healthz"

# 2. HTTP redirects to HTTPS
curl -sI "http://${SITE_ADDRESS}/" | grep -i '^location:'

# 3. Issuer / SANs
openssl s_client -connect "${SITE_ADDRESS}:443" -servername "${SITE_ADDRESS}" -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer -subject -ext subjectAltName

# 4. Cert persists across a recreate
docker compose down && docker compose up -d
openssl s_client -connect "${SITE_ADDRESS}:443" -servername "${SITE_ADDRESS}" -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -serial
```

## Interaction with Cloudflare Tunnel

This is the *direct* TLS mode: the host publishes `80`/`443` and Let's Encrypt
validates via HTTP-01. If the origin is instead reachable only through a
Cloudflare Tunnel (see `dev-ops/self-hosting-cloudflare-tunnel.md`, tracked in
issue #38), the HTTP-01 challenge cannot reach Caddy and plain Let's Encrypt
issuance fails. In that mode, use DNS-01 (a custom Caddy image with a DNS
provider plugin plus an API token) or a Cloudflare Origin Certificate instead of
Let's Encrypt. Both are out of scope for this change.

## Multiple environments on one host

Because HTTP-01 must be served on host port `80` and the issued certificate on
`443`, two Caddy instances cannot share one host for different environments
(`80`/`443` are published directly, not remappable). Put dev/QA and prod on
separate hosts (or separate IPs), or use DNS-01 for the additional environment
instead of HTTP-01.

# Self-hosting with Cloudflare Tunnels (HTTPS-compliant)

This guide prepares a deployment of the booking system for self-hosting behind a
[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/).
It is written for the repository layout used here:

- `product/` contains the generic product (no deployment-specific identifiers).
- `projects/<name>/` contains deployment configuration (compose, Caddy, Authelia, etc.).
- The first deployment is `projects/sauna/`.

The goal is **HTTPS-compliant public access**: users reach the app over `https://`,
the application generates HTTPS URLs, authentication/cookie flows work on the
public hostname, and no secrets or tunnel identifiers are committed to `product/`.

> Related: GitHub issue #38 tracks repo preparation for this setup. Issue #14
> tracks Docker Compose / single setup-script work that may later integrate an
> optional tunnel profile.

## How it fits together

1. **Cloudflare** terminates public TLS for your hostname (for example,
   `booking.example.com`).
2. **`cloudflared`** (the tunnel connector) runs near the origin and maintains an
   outbound connection to Cloudflare. No inbound firewall port-forwarding is required.
3. Cloudflare routes requests through the tunnel to your origin service.
4. **Caddy** (in `projects/<name>/docker-compose.yml`) receives HTTP from the tunnel
   and proxies `/api/*` to the backend while serving the frontend.

For this stack, the usual origin target is the Caddy service on port 80 inside the
Compose network:

```text
Internet (HTTPS) -> Cloudflare -> cloudflared -> http://caddy:80 -> backend/frontend
```

## Prerequisites

- A Cloudflare account and a zone (domain) managed by Cloudflare DNS.
- A host that can run Docker Compose for the chosen `projects/<name>/` deployment.
- Access to Cloudflare Zero Trust to create/manage a tunnel (or equivalent CLI flow).

## 1. Keep deployment-specific config out of `product/`

Do **not** commit these to `product/`:

- Tunnel tokens/credentials
- Public hostnames
- Cloudflare account/zone/tunnel identifiers
- Environment-specific `.env` files

Place deployment-specific values in `projects/<name>/` configuration and/or
environment variables. Use `.env` files for local/operator secrets; this repo's
`.gitignore` ignores `.env` and `.env.*` (except `!.env.example`).

Recommended pattern:

```text
projects/<name>/
  .env.example                # documents required variables; no secrets
  .env                        # operator-provided; gitignored
  docker-compose.yml
  docker-compose.cloudflare-tunnel.yml  # optional override/profile (if added)
  config/
```

Example variables to document (names are illustrative; align with the compose/script
you implement):

```dotenv
# Public URL users visit (always https)
PUBLIC_BASE_URL=https://booking.example.com

# Cloudflare Tunnel token (remotely managed tunnel). Keep secret.
CLOUDFLARE_TUNNEL_TOKEN=
```

## 2. Create and configure the Cloudflare Tunnel

1. In Cloudflare Zero Trust, create a tunnel for the deployment.
2. Choose the **cloudflared** connector and obtain the tunnel token for the
   environment where Docker runs.
3. Add a **Public Hostname** route:
   - Hostname: your public FQDN (for example, `booking.example.com`)
   - Service: `http://caddy:80` when `cloudflared` runs in the same Docker Compose
     network as `caddy` (recommended). If `cloudflared` runs outside that network,
     route to the published origin address instead (for example, `http://127.0.0.1:8080`).
4. Apply Cloudflare Access/policies if the deployment should not be fully public.

Store the token only in secret-managed config (`.env`, host secret store, or CI/CD
secrets). Never commit it.

## 3. Run `cloudflared` with Docker Compose

Add an optional connector service or a Compose override in `projects/<name>/`.
The exact integration may be finalized with issue #14; the following is the
expected shape:

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    depends_on:
      - caddy
    restart: unless-stopped
```

Notes:

- Use a Compose profile or a separate override file if the tunnel should be
  optional for local/non-tunneled environments.
- Do not publish extra host ports for `cloudflared`; it connects outbound.
- Pin or regularly update the image according to your operational policy.

## 4. Caddy and HTTPS-compliant behavior

The current sauna Caddyfile (`projects/sauna/config/Caddyfile`) listens on `:80`
and proxies API traffic to the backend. Behind Cloudflare Tunnel, Cloudflare
provides public HTTPS; Caddy typically remains the HTTP origin.

To keep behavior **HTTPS-compliant**, ensure the stack treats the *public* request
as HTTPS:

- **Forwarded headers:** `cloudflared`/Cloudflare send forwarding headers (including
  the original protocol). Caddy and upstream services must interpret them correctly
  for URL generation, redirects, and security decisions.
- **Trusted proxies:** configure Caddy to trust the proxy in front of it. In a
  Docker Compose deployment, trusting private/Docker network ranges is a common
  starting point; tighten this for your network topology.
- **No insecure public redirects:** public clients should use `https://` URLs.
  Avoid redirecting users to plain HTTP.
- **App base URL:** configure the backend/frontend/auth components that generate
  absolute links (emails, callbacks, redirects) with the public HTTPS base URL.

Example Caddy preparation (adapt to the real deployment; this is illustrative):

```caddyfile
{
	servers {
		trusted_proxies static private_ranges
	}
}

:80 {
	# Existing reverse_proxy / file_server config...
}
```

If you later terminate TLS at Caddy with an origin certificate instead of using a
tunneled HTTP origin, update the Caddy/site configuration, certificate handling,
and Cloudflare SSL/TLS mode accordingly. That is a different operating mode than
the basic tunnel-to-HTTP-origin setup described here.

For terminating TLS at Caddy with **Let's Encrypt** certificates issued per
environment (the direct mode, where the host publishes `80`/`443`), see
[`tls-letsencrypt.md`](tls-letsencrypt.md). Note that when the origin is only
reachable through a Cloudflare Tunnel, Let's Encrypt's HTTP-01 challenge cannot
reach Caddy, so that setup needs DNS-01 or a Cloudflare Origin Certificate.

## 5. Authelia / authentication considerations

Authelia is present in the sauna deployment, but its role is currently TBD
(see `projects/sauna/config/authelia/configuration.yml` and
`product/backend/README.md`). When Authelia is used behind the public HTTPS
hostname:

- Configure session/cookie settings for the public domain and HTTPS.
- Set redirect URIs/callback URLs to `https://<public-hostname>/...`.
- Ensure forwarded headers are trusted/passed so Authelia and the backend see the
  correct scheme and host.
- Re-test login, logout, and protected routes after enabling the tunnel.

Do not enable assumptions that conflict with the backend-owned passwordless flow
until that architecture decision is finalized.

## 6. Validation checklist

After deployment, verify:

- [ ] `https://<public-hostname>/` loads without browser TLS/mixed-content errors.
- [ ] HTTP is not required for normal user access (Cloudflare redirect/HSTS policy
      is intentional and documented).
- [ ] Frontend assets and API calls (`/api/*`) succeed over HTTPS.
- [ ] Authentication flows work end-to-end; cookies are set with expected `Secure`
      behavior on HTTPS.
- [ ] Absolute links in emails/notifications use the public HTTPS base URL.
- [ ] `CLOUDFLARE_TUNNEL_TOKEN` and other secrets are not present in git history
      or committed files.

## 7. Operational and security notes

- **Access control:** decide whether the app is public or protected by Cloudflare
  Access/service policies.
- **Origin exposure:** prefer keeping the origin non-publicly routable; the tunnel
  removes the need for inbound port forwarding in typical setups.
- **Updates:** keep `cloudflared`, Caddy, Authelia, and product images updated.
- **Logs/privacy:** review what request data is logged by Cloudflare, Caddy,
  backend, and Authelia; handle personal data according to your policies.
- **Ports mapping:** `dev-ops/environments.yaml` tracks dev-machine environment
  ports. A production self-hosted tunnel may not need a published host port if
  `cloudflared` connects to `caddy:80` over the Compose network; document the
  chosen approach for that deployment.

## Summary

Repo preparation for Cloudflare Tunnel self-hosting should provide:

1. A documented, deployment-specific config surface (`projects/<name>/`, env vars).
2. A clear `cloudflared` Compose/override pattern with secret-managed tokens.
3. Caddy/app/auth settings that are correct when the public scheme is HTTPS.
4. Operator documentation and a smoke-test checklist.

All tunnel identifiers, hostnames, and secrets remain deployment configuration,
never generic product code.

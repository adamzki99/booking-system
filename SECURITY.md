# Security Policy

## How to report a vulnerability

Please report security issues privately through the repository's **Security** tab:
"Report a vulnerability" (GitHub private vulnerability reporting). Do not open a
public issue or pull request for a suspected vulnerability, and do not post
details in public channels.

## In scope

- `product/backend` - Go backend and its APIs
- `product/frontend` - Solid frontend
- `projects/sauna/sidecar` - deployment sidecar
- `dev-ops/factory` and the `.opencode/` agents and commands
- The QA deployment

## Rules of engagement

- Do not test against real residents' data on QA. Use seeded test data.
- Do not run denial-of-service or load tests against shared environments.
- Do not access accounts you do not own.
- Keep reports confidential until a fix is released.

## Response

Best effort. Acknowledgement within 7 days. Fix timeline depends on severity.

## Note on the factory

The software factory does not act on security advisories. It reads issues only,
so a private advisory never enters the plan or build loop. Please use the channel
above and not a public issue.

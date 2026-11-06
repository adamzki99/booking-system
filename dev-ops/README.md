# Dev-ops

CI/CD, the software factory, and code quality for the booking system.

## Software factory

See [`factory/`](factory/README.md). [`factory/tick.sh`](factory/tick.sh) runs
on a 1-hour interval and picks up GitHub issues and pull requests:

- **No labels** → the issue is in its infant state → a planning agent posts an
  implementation plan as a comment and categorizes the issue with labels.
- **Open factory PR blocked from merge** → a fix agent resolves failing checks,
  requested changes, or merge conflicts and merges when possible (capped per
  tick; idempotent per PR head SHA + blocking reasons).
- **`owner approved` label** (no open factory PR) → a builder agent implements
  the issue, creates a PR, and merges it.
- Labels select which model a session uses (`factory/models.yaml`).
- Each hourly tick may create **one planning** session plus build-path sessions
  (fixes and/or a new build), with configurable caps to spread token usage.

The system owner steers the project purely by interacting with GitHub issues.

Deployment to the development environment happens at **12 am and 12 pm** daily,
leaving ~12 h for Playwright testing on the development environment.

## Branches and environments

- There is always a **QA environment** built from the base branch.
- Every **release branch** gets one **candidate environment**.
- Everything runs via Docker Desktop; each environment is reachable on a
  distinct port on the dev machine. Ports are recorded in
  [`environments.yaml`](environments.yaml).

## Code quality

A Semgrep instance runs on the development server, connected to this repo. It
performs checks on merges into the `main` and release branches.

## Open-source skills

[`scripts/request-skills.sh`](scripts/request-skills.sh) calls for the addition
of open-source [OpenCode skills](https://opencode.ai/v2/docs/skills/) to this
repository. It vendors each skill listed in [`skills.yaml`](skills.yaml) into
`.opencode/skills/` and opens a pull request proposing the addition:

```sh
dev-ops/scripts/request-skills.sh          # vendor + open a PR
dev-ops/scripts/request-skills.sh --local  # vendor only, no PR
```

Skills already present are skipped. Each vendored skill carries a `.source`
file recording its origin (repo, path, ref). Review licenses and content before
merging — skills are instructions loaded by the factory agents.

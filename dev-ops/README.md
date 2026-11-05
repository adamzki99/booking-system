# Dev-ops

CI/CD, the software factory, and code quality for the booking system.

## Software factory

See [`factory/`](factory/README.md). [`factory/tick.sh`](factory/tick.sh) runs
on a 1-hour interval and picks up GitHub issues:

- **No labels** → the issue is in its infant state → a planning agent posts an
  implementation plan as a comment and categorizes the issue with labels.
- **`owner approved` label** → a builder agent implements the issue, creates a
  PR, and merges it.
- Labels select which model a session uses (`factory/models.yaml`).
- Each hourly tick may create at most **one planning** and **one building**
  session (total sessions are not limited), to spread token usage over the day.

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

# Software factory

The automation that turns GitHub issues into merged PRs.

## How it works

1. [`tick.sh`](tick.sh) runs on a 1-hour interval (e.g. via cron) and fetches
   issues from GitHub.
2. Per tick, it may start at most:
   - **one planning session** — for issues with no labels (infant state). A plan
     agent posts the implementation plan as a comment and categorizes the issue
     with labels.
   - **one building session** — for issues labeled `owner approved`. A builder
     agent implements the issue, creates a PR, and merges it.
3. Labels select the model for the session, per [`models.yaml`](models.yaml).

The total number of sessions is not limited — only the rate at which they are
created. The system owner steers the project by interacting with issues only.

## Files

- `tick.sh` — one factory tick: starts at most one planning and one building
  session (see `--dry-run`). Finished work carries `<!-- factory:plan -->` /
  `<!-- factory:build -->` comment markers, making ticks idempotent.
  Scheduling: `0 * * * * /path/to/repo/dev-ops/factory/tick.sh`
- `models.yaml` — label → model selection for factory sessions.

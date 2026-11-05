# Software factory

The automation that turns GitHub issues into merged PRs.

## How it works

1. [`tick.sh`](tick.sh) runs on a 1-hour interval (e.g. via cron) and fetches
   issues from GitHub.
2. Per tick, it may start at most:
   - **one planning session** — for issues with no labels (infant state). A plan
     agent posts the implementation plan as a comment and categorizes the issue
     with labels.
   - **one building session** — for issues labeled `owner approved`, selected by
     build priority: issues in a GitHub Project (v2) come before others; among
     project issues, the oldest project (by `createdAt`) wins, then the numeric
     `Build order` project field ascending (from 1). A builder agent implements
     the issue, creates a PR, and merges it.
3. Labels select the model for the session, per [`models.yaml`](models.yaml).

The total number of sessions is not limited — only the rate at which they are
created. The system owner steers the project by interacting with issues only.

## Label taxonomy

The planner categorizes each infant issue with labels from the sets below.

### Model-selection labels

Exactly one complexity tier per issue — it selects the build-session model via
[`models.yaml`](models.yaml). If several tiers are present, the first one in
`models.yaml` order (heaviest first) wins.

| Label | When the planner applies it | Model |
|-------|-----------------------------|-------|
| `trivial-task` | Docs, renames, config tweaks | `opencode-go/beam-free` |
| `light-build-task` | Small, well-scoped changes | `opencode-go/claude-haiku-5-5` |
| `standard-build-task` | Typical feature work | `opencode-go/deepseek-v4-pro` |
| `heavy-build-task` | Large or architectural work | `opencode-go/kimi-k3.1-pro` |

The `plan-task` label is not applied to issues; it selects the model for the
planning session itself (`opencode-go/qwen3.7-plus`). A session started for an
issue without any model-selection label falls back to the `default` entry
(`opencode-go/deepseek-v4-pro`).

### Area labels

One or more per issue, for categorization only — they do not select a model:

- `backend` — `product/backend` (Go service)
- `frontend` — `product/frontend` (React SPA)
- `dev-ops` — `dev-ops/` (CI/CD, factory, tooling)

### Gate label

- `owner approved` — applied by the repository owner only; sends a planned
  issue to a builder session. The planner never sets it.

## Files

- `tick.sh` — one factory tick: starts at most one planning and one building
  session (see `--dry-run`). Finished work carries `<!-- factory:plan -->` /
  `<!-- factory:build -->` comment markers, making ticks idempotent.
  `--on-usage-filled=backup|skip|fail` (default `backup`, or
  `FACTORY_ON_USAGE_FILLED`) controls what happens when a session fails because
  usage/quota is filled: retry once with the configured `backup_model`, skip
  that session, or fail the tick.
  Scheduling: `0 * * * * /path/to/repo/dev-ops/factory/tick.sh`
- `models.yaml` — label → model selection for factory sessions (`model` plus
  optional `backup_model` per entry / `default`).

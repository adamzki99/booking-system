# Software factory

The automation that turns GitHub issues into merged PRs.

## How it works

1. A script runs on a 1-hour interval and fetches issues from GitHub.
2. Per tick, it may start at most:
   - **one planning session** — for issues with no labels (infant state). A plan
     agent posts the implementation plan as a comment and categorizes the issue
     with labels.
   - **one building session** — for issues labeled `owner approved`. A builder
     agent implements the issue, creates a PR, and merges it.
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

- `models.yaml` — label → model selection for factory sessions.

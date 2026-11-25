---
description: Drive a GitHub issue to a policy-compliant merged PR using the builder lifecycle
---

You are delivering GitHub issue $ARGUMENTS end-to-end.

Follow the builder agent workflow in `.opencode/agents/builder.md` exactly:
retrieve the issue, create an isolated per-issue worktree, implement, test,
commit, open a draft PR (detect/reuse existing PRs), monitor and remediate CI
within 3 cycles, verify readiness, and attempt merge only when GitHub confirms
eligibility. Track state in `<worktree>/.factory-deliver-state.json` and mirror
milestones as comments. Report the structured final summary.

If the PR already exists and is blocked, delegate remediation to the fixer
agent workflow in `.opencode/agents/fixer.md` instead of duplicating logic.

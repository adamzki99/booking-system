---
description: Create an agentic-compliant GitHub issue from the repository template
---

Create a GitHub issue that is self-contained and implementable by an autonomous
agent. The issue body must follow `dev-ops/issue-templates/agentic.md` and pass
`dev-ops/scripts/validate-issue-body.sh` before creation.

Inputs: `$ARGUMENTS` may be an issue title, a path to a pre-filled Markdown
body, or empty.

## Workflow

1. Read the template at `dev-ops/issue-templates/agentic.md`. Use it as the
   starting structure; do not omit required sections.
2. Determine the draft body:
   - If `$ARGUMENTS` points to an existing Markdown file, read it as the draft.
   - Otherwise treat `$ARGUMENTS` as the issue title and gather the missing
     content from the user (or from the current conversation).
3. Ensure every required section is present and non-empty:
   - `## Problem Statement`
   - `## Motivation`
   - `## Relevant Repository Context`
   - `## Functional Requirements`
   - `## Acceptance Criteria` (at least one measurable `- [ ] ...` checkbox)
   - `## Implementation Tasks`
   - `## Testing and Validation`
   - `## Constraints and Considerations`
   Also include `## Known Facts`, `## Assumptions`, and `## Proposed Solution`
   where useful, as in the template.
4. Write the final body to a temporary file (for example
   `/tmp/opencode/issue-body.md`).
5. Validate it before creating anything:

   ```sh
   dev-ops/scripts/validate-issue-body.sh /tmp/opencode/issue-body.md
   ```

   If validation fails, fix the body and rerun the validator. Do not call
   `gh issue create` until validation passes.
6. Determine the title. If none was provided, derive a concise title from the
   Problem Statement.
7. Create the issue using the validated body file:

   ```sh
   gh issue create --title "<title>" --body-file /tmp/opencode/issue-body.md
   ```

   Do not apply labels here; the factory's planning agent categorizes issues
   after creation. Only add labels if the user explicitly requests them.
8. Report the created issue URL and confirm that validation passed.

## Notes

- Acceptance criteria must be measurable and verifiable; avoid subjective
  completion language.
- Keep the problem statement scoped to avoid duplicate or vague issues.
- This command preserves the repository's existing `gh` CLI workflow and the
  factory's planning/labeling workflow.
- Limitations: this is instruction-level guidance. Stronger enforcement would
  require a plugin or server-side validation; see the issue for context.

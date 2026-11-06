---
description: Run frontend lint and typecheck in product/frontend and report results
subtask: true
---

Lint results (exit code printed at the end):

!`cd product/frontend && npm run lint --silent 2>&1 | tail -n 200; echo "lint exit: ${PIPESTATUS[0]}"`

Typecheck results:

!`cd product/frontend && npm run typecheck --silent 2>&1 | tail -n 200; echo "typecheck exit: ${PIPESTATUS[0]}"`

Summarize the two results above. Do not modify any files and do not run
auto-fix flags.

## Report format
1. **Verdict**: PASS only if both exit codes are 0, otherwise FAIL.
2. **Counts**: errors and warnings for lint, errors for typecheck.
3. **Findings**: grouped by file, each as `path:line  rule  message`. List at
   most 20, most severe first, and say how many were omitted.
4. **Notes**: if output looks truncated, or a command could not run (missing
   `node_modules`, missing script), say so instead of guessing. Do not install
   dependencies.

$ARGUMENTS

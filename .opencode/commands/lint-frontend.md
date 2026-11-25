---
description: Run frontend typecheck and tests in product/frontend-solid and report results
subtask: true
---

Typecheck results (exit code printed at the end):

!`cd product/frontend-solid && npm run typecheck --silent 2>&1 | tail -n 200; echo "typecheck exit: ${PIPESTATUS[0]}"`

Test results:

!`cd product/frontend-solid && npm test --silent 2>&1 | tail -n 200; echo "test exit: ${PIPESTATUS[0]}"`

Summarize the two results above. Do not modify any files and do not run
auto-fix flags.

## Report format
1. **Verdict**: PASS only if both exit codes are 0, otherwise FAIL.
2. **Counts**: errors for typecheck, pass/fail counts for tests.
3. **Findings**: grouped by file, each as `path:line  message` when available. List at
   most 20, most severe first, and say how many were omitted.
4. **Notes**: if output looks truncated, or a command could not run (missing
   `node_modules`, missing script), say so instead of guessing. Do not install
   dependencies.

$ARGUMENTS

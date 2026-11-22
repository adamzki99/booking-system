---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

If the user passes a ticket reference, fetch it from the issue tracker and state its title before starting. If the reference is ambiguous, ask.

For frontend/UI work, follow supplied mockups and design references for layout, styling, coloring, spacing, typography, and component states. Use the `ui-mockup-alignment` and `frontend-design` skills as relevant, and respect the fixed frontend stack (Solid 2, TypeScript, Vite, @solidjs/router) with shared UI primitives and theme tokens.

Call the Skill tool with "tdd" where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, call the Skill tool with "code-review" to review the work.

Commit your work to the current branch.

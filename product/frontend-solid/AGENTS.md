# AGENTS.md (product/frontend-solid)

## Scope

This directory contains the **generic Solid frontend** for the booking platform. It provides reusable UI, routing, auth/session flows, booking/account views, and shared theming primitives. Deployment-specific branding and configuration belong in `projects/<name>/`, not in the generic theme or app logic.

**Fixed frontend stack (do not replace):** Solid 2, TypeScript, Vite, and @solidjs/router. Implement UI work with this stack and existing project patterns.

Read the root [`../../AGENTS.md`](../../AGENTS.md) and [`../AGENTS.md`](../AGENTS.md) first for repository-wide and product-level rules.

## Local verification and workflow commands

Run commands from `product/frontend-solid/` unless noted.

- Install dependencies: `npm ci` (preferred when `package-lock.json` is present) or `npm install`
- Development server: `npm run dev`
- Typecheck: `npm run typecheck`
- Lint (Solid 2 rules): `npm run lint`
- Build (typecheck + production bundle): `npm run build`
- Test: `npm test` (runs `vitest run`)
- Preview production build: `npm run preview`

If you change code, ensure lint, typecheck/build, and tests pass and keep style consistent with surrounding files.

## Conventions and invariants

- **Follow supplied mockups/design references:** when mockups or design references are provided for the relevant UI, treat them as the visual source of truth for layout, hierarchy, spacing, coloring, typography, radii, iconography cues, component states, and responsive behavior. Do not invent a conflicting visual direction. For deployment-specific mockups (for example sauna mockups under `projects/sauna/docs/mocks/`), align that deployment's UI to the mockups and extract reusable patterns into generic theme tokens/components in `product/frontend-solid/` only when they are useful across deployments.
- **Respect the fixed stack:** use Solid 2, TypeScript, Vite, and @solidjs/router. Do not introduce a different UI framework, router, bundler, or language stack.
- **Solid 2 agent tooling:** before writing Solid code, read `node_modules/solid-js/CHEATSHEET.md` (especially "What changed from 1.x"). Use installed skills when relevant: `node_modules/solid-js/skills/solid-2.0/SKILL.md`, `node_modules/solid-js/skills/reactivity-diagnostics/SKILL.md`, `node_modules/@solidjs/web/skills/server-components/SKILL.md`, and `node_modules/@solidjs/diagnostics/skills/agent-loops/SKILL.md` when present. For external docs, prefer https://docs.solidjs.com/llms.txt or append `.md` to a Solid docs page URL.
- **Solid 2 only:** use `solid-js` 2.x and `@solidjs/web` 2.x. Do not use Solid 1 APIs (`createResource`, `createComputed`, `batch`, `onMount`, `mergeProps`, `splitProps`, `Index`, `Suspense`, `ErrorBoundary`, `classList`, `use:` directives, `startTransition`, `useTransition`, `Context.Provider`). Props are read, never destructured; pass values, not accessors. `createEffect` takes `(compute, apply)`. Stores are written through draft setters (no path setters, no `produce`). Do not read reactive values at the top of a component body, and do not write signals/stores from memos, effect compute functions, or component bodies; write from event handlers, `onSettled`, or actions. Name signals, memos, and effects so diagnostics read clearly.
- **Lint and diagnostics feedback:** run `npm run lint`. Oxlint is the only linter; Solid 2 rules come from `eslint-plugin-solid` loaded through oxlint `jsPlugins`, with TypeScript-aware JSX checks and oxlint correctness/suspicious categories enabled. Treat bracketed Solid console diagnostic codes as defects; look them up in the reactivity diagnostics skill before suppressing or working around them.
- **UI primitives and theme:** prefer shared UI primitives in `src/ui/`, theme tokens in `src/theme.ts`, and existing component patterns over ad-hoc styling. Keep deviations minimal and documented.
- **Theming boundaries:** `src/theme.ts` contains generic/base tokens and component defaults. Reuse or extend tokens there instead of duplicating ad-hoc values. Do not add deployment-specific branding here; deployment-specific branding/copy/assets belong in `projects/<name>/`.
- **Testing helper:** use the provider-aware render helper in `src/test-utils.tsx` for component tests so router/session context resolves correctly.
- **Test environment:** `src/tests.setup.ts` configures jsdom/Vitest behavior. Preserve these assumptions when adding tests.
- **Generic product boundary:** keep deployment-specific UI rules, copy, and configuration out of generic product code unless the capability is useful to every deployment.
- **API and behavior alignment:** when backend contracts or session/auth behavior change, update frontend API usage, route guards, and tests together.

## Canonical references

- [`README.md`](README.md): stack, commands, UI patterns, testing, and theming.
- [`package.json`](package.json): authoritative npm scripts and dependencies.
- [`src/theme.ts`](src/theme.ts): base theme tokens and component defaults.
- [`src/test-utils.tsx`](src/test-utils.tsx): shared test render helper.
- [`src/tests.setup.ts`](src/tests.setup.ts): Vitest/jsdom test setup.
- [`../README.md`](../README.md): generic product scope and architecture.

# AGENTS.md (product/frontend)

## Scope

This directory contains the **generic React frontend** (Vite + TypeScript + Chakra UI) for the booking platform. It provides reusable UI, routing, auth/session flows, booking/account views, and shared theming primitives. Deployment-specific branding and configuration belong in `projects/<name>/`, not in the generic theme or app logic.

Read the root [`../../AGENTS.md`](../../AGENTS.md) and [`../AGENTS.md`](../AGENTS.md) first for repository-wide and product-level rules.

## Local verification and workflow commands

Run commands from `product/frontend/` unless noted.

- Install dependencies: `npm ci` (preferred when `package-lock.json` is present) or `npm install`
- Development server: `npm run dev`
- Build (typecheck + production bundle): `npm run build`
- Test: `npm test` (runs `vitest run`)
- Preview production build: `npm run preview`

No separate lint or format script is defined in `package.json`. If you change code, ensure TypeScript/build checks pass via `npm run build` and keep style consistent with surrounding files.

## Conventions and invariants

- **Chakra UI first:** prefer Chakra primitives, theme tokens, and component recipes over bespoke CSS. Reach for custom CSS only when a Chakra primitive cannot express the requirement; follow the guidance in [`README.md`](README.md).
- **Theming boundaries:** `src/theme.ts` contains generic/base tokens and component defaults. Do not add deployment-specific branding here; deployments extend the base theme from `projects/<name>/`.
- **Testing helper:** use the provider-aware render helper in `src/test-utils.tsx` for component tests so Chakra context/hooks resolve correctly (see existing tests such as `theme.test.tsx`-style usage patterns and `RequireSession.test.tsx`).
- **Test environment:** `src/tests.setup.ts` configures jsdom/Vitest behavior (UTC timezone, `matchMedia` stub, explicit cleanup). Preserve these assumptions when adding tests.
- **Generic product boundary:** keep deployment-specific UI rules, copy, and configuration out of generic product code unless the capability is useful to every deployment.
- **API and behavior alignment:** when backend contracts or session/auth behavior change, update frontend API usage, route guards, and tests together.

## Canonical references

- [`README.md`](README.md): stack, Chakra usage, design tokens, component recipes, testing, and deployment theming.
- [`package.json`](package.json): authoritative npm scripts and dependencies.
- [`src/theme.ts`](src/theme.ts): base theme tokens and component defaults.
- [`src/test-utils.tsx`](src/test-utils.tsx): shared test render helper.
- [`src/tests.setup.ts`](src/tests.setup.ts): Vitest/jsdom test setup.
- [`../README.md`](../README.md): generic product scope and architecture.

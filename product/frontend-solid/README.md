# Frontend (Solid)

Generic Solid frontend for the booking platform. It provides booking calendar, account, and user management views, and talks to the backend REST API.

## Stack

- **Solid 2** (`solid-js`, `@solidjs/web`)
- **TypeScript**
- **Vite**
- **@solidjs/router**
- **Solid UI** (https://www.solid-ui.com/) for UI component patterns and primitives

## Commands

Run commands from `product/frontend-solid/`.

```sh
npm ci
npm run dev
npm run typecheck
npm run lint
npm test
npm run build
npm run preview
```

- `npm run dev`: start the Vite development server.
- `npm run typecheck`: run TypeScript checks with no emit.
- `npm run lint`: run oxlint with the shared Oxc base config (`dev-ops/code-quality/oxlint.base.json`) and Solid 2 rules from `eslint-plugin-solid`.
- `npm test`: run the Vitest suite.
- `npm run build`: run typecheck and create a production build.
- `npm run preview`: preview the production build locally.

## Formatting

Formatting for JS, TS, JSX, TSX, JSON, JSONC, CSS, and HTML is handled by `oxfmt` from the repository root. Run `npm run fmt` to write changes and `npm run fmt:check` to verify. To leave a JS/TS block unchanged, add `// oxfmt-ignore` on the line before it. Editor setup comes in prompt 08.

## Project structure

- `src/index.tsx`: app entrypoint and providers.
- `src/App.tsx`: route definitions.
- `src/auth/`: session context and auth state.
- `src/api/`: backend API clients.
- `src/components/`: shared app components.
- `src/pages/`: route-level pages.
- `src/ui/`: reusable UI primitives.
- `src/theme.ts`: base theme tokens and defaults.
- `src/test-utils.tsx`: provider-aware render helper for tests.
- `src/tests.setup.ts`: Vitest/jsdom setup.

## UI and theming

The frontend uses shared UI primitives in `src/ui/` and theme tokens in `src/theme.ts`, following [Solid UI](https://www.solid-ui.com/) patterns where they fit the product. Keep generic visual patterns reusable across deployments. Deployment-specific branding, copy, and assets belong under `projects/<name>/`.

## Testing

Component tests use Vitest, jsdom, and `@solidjs/testing-library`. Use `src/test-utils.tsx` so components render with the required providers.

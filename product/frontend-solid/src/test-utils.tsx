import { render as solidRender } from "@solidjs/testing-library";
import type { JSX } from "@solidjs/web";

/**
 * Provider-aware render helper (Solid).
 *
 * Currently wraps with a fragment/root; add providers here as the app grows
 * (e.g. router/session/theme context). Mirrors the role of
 * product/frontend/src/test-utils.tsx.
 */
function customRender(ui: () => JSX.Element, options?: Parameters<typeof solidRender>[1]) {
  return solidRender(ui, options);
}

export * from "@solidjs/testing-library";
export { customRender as render };

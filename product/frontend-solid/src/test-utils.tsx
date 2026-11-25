import { render as solidRender } from "@solidjs/testing-library";
import type { JSX } from "@solidjs/web";

/**
 * Provider-aware render helper (Solid).
 *
 * Currently renders the UI as-is; add providers here as the app grows
 * (for example router, session, or theme context). Mirrors the role of a
 * provider-aware test-utils helper.
 */
function customRender(ui: () => JSX.Element, options?: Parameters<typeof solidRender>[1]) {
  return solidRender(ui, options);
}

// Re-export testing utilities so tests can import from "../test-utils" and still
// use the provider-aware render.
export * from "@solidjs/testing-library";
export { customRender as render };

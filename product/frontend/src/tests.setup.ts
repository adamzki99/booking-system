import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

// Node honors TZ at call time, so pin parse/format expectations to UTC —
// datetime-local inputs then convert to a predictable ISO instant.
process.env.TZ = "UTC";

// Chakra UI's ColorModeProvider calls `window.matchMedia` to detect the
// system color scheme, but jsdom does not implement it. Provide a minimal
// stub so tests don't throw.
Object.defineProperty(window, "matchMedia", {
  writable: true,
  value: (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }),
});

// @testing-library/react only auto-cleans when afterEach is a global; we keep
// vitest globals off, so clean up explicitly between tests.
afterEach(cleanup);

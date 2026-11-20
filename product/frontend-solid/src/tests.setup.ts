import "@testing-library/jest-dom/vitest";
import { cleanup } from "@solidjs/testing-library";
import { afterEach } from "vitest";

// Node honors TZ at call time, so pin parse/format expectations to UTC.
process.env.TZ = "UTC";

// jsdom does not implement `window.matchMedia`. Provide a minimal stub so tests
// don't throw if browser APIs query it.
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

// Keep tests isolated by cleaning up rendered components between runs.
afterEach(cleanup);


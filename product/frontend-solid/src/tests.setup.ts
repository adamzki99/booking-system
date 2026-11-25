import "@testing-library/jest-dom/vitest";
import { cleanup } from "@solidjs/testing-library";
import { afterEach } from "vitest";

// Node honors TZ at call time, so pin parse/format expectations to UTC.
process.env.TZ = "UTC";

// jsdom does not implement all browser APIs used by UI components.
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

Object.defineProperty(window, "scrollTo", {
  writable: true,
  value: () => {},
});

// Keep tests isolated by cleaning up rendered components between runs.
afterEach(() => {
  cleanup();
});

import "@testing-library/jest-dom/vitest";

// Node honors TZ at call time, so pin parse/format expectations to UTC.
process.env.TZ = "UTC";

// Chakra UI's ColorModeProvider calls `window.matchMedia` in the React app,
// but jsdom does not implement it. Provide a minimal stub so tests don't throw
// if browser APIs are queried.
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

import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

// Node honors TZ at call time, so pin parse/format expectations to UTC —
// datetime-local inputs then convert to a predictable ISO instant.
process.env.TZ = "UTC";

// @testing-library/react only auto-cleans when afterEach is a global; we keep
// vitest globals off, so clean up explicitly between tests.
afterEach(cleanup);

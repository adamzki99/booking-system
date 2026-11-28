import { defineConfig } from "oxlint";

import playwrightPlugin from "eslint-plugin-playwright";
import base from "../code-quality/oxlint.base.json" with { type: "json" };

// eslint-plugin-playwright is exact-pinned in package.json, so the
// recommended set spread below cannot drift under us.
const playwrightRecommended = playwrightPlugin.configs.recommended;

export default defineConfig({
  extends: [base],
  options: {
    // tsconfig.json type-checks cleanly against @playwright/test types, so the
    // type-aware rules from the base config apply here as well.
    typeAware: true,
  },
  env: {
    node: true,
    es2022: true,
    ...playwrightRecommended.env,
  },
  // JS plugins resolve relative to this config file, so eslint-plugin-playwright
  // must stay a devDependency of this package.
  jsPlugins: ["eslint-plugin-playwright"],
  rules: {
    // The recommended set is what this package needs: missing-playwright-await
    // (Playwright calls must be awaited), no-focused-test, no-skipped-test,
    // no-wait-for-timeout, prefer-web-first-assertions, valid-expect, ...
    ...playwrightRecommended.rules,
    // Promoted from "warn" to "error": CI runs oxlint with --deny-warnings, so
    // these already block a build. Stating it here keeps the intent visible in
    // the config instead of only in the CI flag.
    "playwright/no-focused-test": "error",
    "playwright/no-skipped-test": "error",
    "playwright/no-wait-for-timeout": "error",
  },
});

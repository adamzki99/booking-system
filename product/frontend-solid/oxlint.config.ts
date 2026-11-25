import { defineConfig } from "oxlint";

import solidV2 from "eslint-plugin-solid/configs/v2";
import base from "../../dev-ops/code-quality/oxlint.base.json" with { type: "json" };

export default defineConfig({
  extends: [base],
  options: {
    typeAware: true,
  },
  env: {
    browser: true,
    es2022: true,
  },
  ignorePatterns: base.ignorePatterns,
  jsPlugins: ["eslint-plugin-solid", "eslint-plugin-testing-library"],
  settings: {
    ...solidV2.settings,
    vitest: {
      typecheck: true,
    },
  },
  rules: {
    ...solidV2.rules,
    "no-console": "error",
  },
  overrides: [
    {
      files: ["**/*.test.ts", "**/*.test.tsx", "src/tests.setup.ts"],
      env: {
        browser: true,
        node: true,
      },
      globals: {
        vi: "readonly",
        describe: "readonly",
        it: "readonly",
        expect: "readonly",
        beforeEach: "readonly",
        afterEach: "readonly",
        beforeAll: "readonly",
        afterAll: "readonly",
      },
      rules: {
        "no-console": "off",
        "vitest/no-disabled-tests": "warn",
        "vitest/no-focused-tests": "error",
        "vitest/expect-expect": "error",
        "testing-library/await-async-queries": "error",
        "testing-library/await-async-utils": "error",
        "testing-library/no-await-sync-events": "error",
        "testing-library/no-await-sync-queries": "error",
        "testing-library/no-debugging-utils": "warn",
        "testing-library/no-dom-import": "error",
        "testing-library/prefer-screen-queries": "warn",
      },
    },
    {
      files: ["vite.config.ts", "oxlint.config.ts"],
      env: {
        browser: false,
        node: true,
      },
      rules: {
        "no-console": "off",
      },
    },
  ],
});

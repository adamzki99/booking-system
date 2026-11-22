import { defineConfig } from "oxlint";

import solidTs from "eslint-plugin-solid/configs/typescript";
import solidV2 from "eslint-plugin-solid/configs/v2";

// Oxlint is the only linter in this package. Solid rules are loaded through
// oxlint's jsPlugins support; eslint core is not required.
export default defineConfig({
  jsPlugins: ["eslint-plugin-solid"],
  settings: solidV2.settings,
  categories: {
    correctness: "error",
    suspicious: "warn",
  },
  rules: {
    ...solidV2.rules,
    // Keep Solid 2 severities from v2, but use TypeScript-aware JSX checks.
    "solid/jsx-no-undef": solidTs.rules["solid/jsx-no-undef"],
    "solid/no-unknown-namespaces": solidTs.rules["solid/no-unknown-namespaces"],
  },
  ignorePatterns: ["dist/**", "node_modules/**", "coverage/**"],
});

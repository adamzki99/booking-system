import { defineConfig } from "oxlint";

import solidV2 from "eslint-plugin-solid/configs/v2";
import base from "../../dev-ops/code-quality/oxlint.base.json" with { type: "json" };

export default defineConfig({
  extends: [base],
  ignorePatterns: base.ignorePatterns,
  jsPlugins: ["eslint-plugin-solid"],
  settings: solidV2.settings,
  rules: solidV2.rules,
});

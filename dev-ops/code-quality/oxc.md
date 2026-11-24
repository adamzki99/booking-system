# Oxc adoption baseline and decisions

Status: foundation in place (prompt 02).

## 1. Purpose and scope

This document records the baseline measurements for adopting Oxc tools across
`adamzki99/booking-system`. It is read-only evidence for prompt 01 of the Oxc
prompt set; it does not change tools or configuration.

**In scope for later prompts**

- `oxlint`: the only JS/TS linter, repo-wide (already used in
  `product/frontend-solid`).
- `oxfmt`: the only formatter for JS, TS, JSX, TSX, JSON, CSS, YAML, Markdown
  and HTML, repo-wide.
- Type-aware linting via `--type-aware` (backend choice recorded below).

**Stays as-is**

- `tsc --noEmit` for type checking (see section 7).
- Vitest for tests.
- Vite for build/dev (Rolldown/Oxc inside Vite 8 noted in section 8).
- `gofmt` for Go.
- Semgrep for security/static checks.

**Not adopted now**

- `oxc-parser`, `oxc-transform`, `oxc-resolver`, isolated declarations as
  libraries: not needed because this repo does not emit library `.d.ts` files
  through Oxc; the frontend is an app built by Vite.

## 2. Tool versions measured

| Tool                             |          Version | Notes                                                      |
| -------------------------------- | ---------------: | ---------------------------------------------------------- |
| oxlint (frontend installed)      |           1.94.0 | from `product/frontend-solid/package-lock.json` / `npm ci` |
| oxlint (latest checked)          |           1.95.0 | `npm view oxlint version` on 2026-11-24                    |
| oxfmt (latest checked)           |           0.80.0 | `npm view oxfmt version` on 2026-11-24                     |
| oxlint-tsgolint (latest checked) |         7.0.2008 | `npm view oxlint-tsgolint version` on 2026-11-24           |
| tsrs (latest checked)            | 7.1.0-beta.tsrs5 | `npm view tsrs version` on 2026-11-24                      |
| Node (measurement env)           |          v26.8.1 | `node --version`                                           |
| npm (measurement env)            |           12.1.0 | `npm --version`                                            |
| Vite (frontend)                  |            8.3.0 | `product/frontend-solid/package.json`                      |
| TypeScript (frontend)            |            5.6.3 | `product/frontend-solid/package.json` / lock               |
| @solidjs/vite-plugin             |            3.0.1 | frontend dependency                                        |

All later prompts should pin exact versions before committing configs.

## Formatting

`oxfmt` is the repository formatter for JS, TS, JSX, TSX, MJS/CJS, JSON, JSONC, CSS, HTML, YAML, and Markdown. `opencode.jsonc` is formatted in prompt 08.

- Format all in-scope files: `npm run fmt` (from repo root)
- Check formatting: `npm run fmt:check` (from repo root)
- Ignore a block in JS/TS: `// oxfmt-ignore` on the line before the code to leave unchanged
- Config: `.oxfmtrc.jsonc` at repo root
- Editor setup comes in prompt 08.

## Git blame

Mechanical formatting commits are listed in `.git-blame-ignore-revs`. Configure git locally to skip them in blame:

```sh
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

GitHub uses this file automatically.

## 3. Inventory

Exclusions applied (per common rules): `**/node_modules/**`, `**/dist/**`,
`package-lock.json`, `.opencode/skills/**` (vendored third-party skills),
`projects/sauna/docs/mocks/**` (canonical UI mockups), generated files, and
Go/Python files.

| Package / area         |    JS |     TS |    TSX |   JSON | JSONC |   CSS |  HTML |   YAML | Markdown |   Total |
| ---------------------- | ----: | -----: | -----: | -----: | ----: | ----: | ----: | -----: | -------: | ------: |
| .github                |     0 |      0 |      0 |      0 |     0 |     0 |     0 |      1 |        0 |       1 |
| .github/workflows      |     0 |      0 |      0 |      0 |     0 |     0 |     0 |      8 |        1 |       9 |
| .opencode              |     0 |      0 |      0 |      0 |     0 |     0 |     0 |      0 |        8 |       8 |
| README.md (root)       |     0 |      0 |      0 |      0 |     0 |     0 |     0 |      0 |        1 |       1 |
| SECURITY.md (root)     |     0 |      0 |      0 |      0 |     0 |     0 |     0 |      0 |        1 |       1 |
| dev-ops                |     0 |      0 |      0 |      7 |     0 |     0 |     0 |     13 |       24 |      44 |
| dev-ops/testing        |     0 |      2 |      0 |      1 |     0 |     0 |     0 |      0 |        0 |       3 |
| product                |     0 |      0 |      0 |      5 |     0 |     0 |     0 |      9 |        4 |      18 |
| product/backend        |     0 |      0 |      0 |      0 |     0 |     0 |     0 |      0 |        2 |       2 |
| product/frontend-solid |     0 |     18 |     30 |      2 |     0 |     9 |     1 |      0 |        2 |      62 |
| projects               |     0 |      0 |      0 |      0 |     0 |     0 |     0 |      6 |        6 |      12 |
| root guardrail files   |     0 |      0 |      0 |      0 |     1 |     0 |     0 |      0 |        1 |       2 |
| **Total**              | **0** | **20** | **30** | **15** | **1** | **9** | **1** | **37** |   **50** | **163** |

Guardrail files (owner-reviewed / factory-tag sensitive): `AGENTS.md`,
`opencode.jsonc`, `.opencode/agents/*.md` (none currently present; `.opencode/`
contains commands/skills references in inventory). Workflow files:
`.github/workflows/*.yml` (8 files) are owner-reviewed by CODEOWNERS and must
keep actions pinned by full commit SHA.

## 4. Lint baseline

### 4.1 Current frontend lint

Command: `cd product/frontend-solid && npm ci && npm run lint`

Result: **7 warnings, 0 errors**.

| Count | Severity | Rule               | Classification                                 |
| ----: | -------- | ------------------ | ---------------------------------------------- |
|     7 | warning  | `solid/reactivity` | Real Solid diagnostic; fix or justify per case |

All 7 warnings are in `src/pages/Users.tsx` (5) and `src/pages/Calendar.tsx`
(2): "This function should be passed to a tracked scope (like createEffect) or
an event handler because it contains reactivity, or else changes will be
ignored."

### 4.2 Expanded baseline (native plugins + categories)

Command (oxlint 1.94.0, existing config with eslint-plugin-solid JS plugin):

```sh
npx oxlint -c oxlint.config.ts -D correctness -W suspicious -W perf \
  --import-plugin --vitest-plugin --jsx-a11y-plugin --promise-plugin -f json
```

Result: **137 diagnostics (110 errors, 27 warnings), 231 rules**.

| Count | Severity | Rule                                     | Classification                                                                                  |
| ----: | -------- | ---------------------------------------- | ----------------------------------------------------------------------------------------------- |
|    83 | error    | `vitest(require-mock-type-parameters)`   | Style/preference; noisy in existing tests, not a runtime defect                                 |
|    19 | error    | `jsx-a11y(label-has-associated-control)` | Mostly real a11y findings; verify case by case (some may need label/control wiring)             |
|     7 | warning  | `import(no-unassigned-import)`           | False positive/style for side-effect imports (CSS, test setup); configure or allowlist patterns |
|     7 | warning  | `solid(reactivity)`                      | Real Solid diagnostic                                                                           |
|     5 | warning  | `import(no-named-as-default-member)`     | Style/preference; low value in this codebase                                                    |
|     4 | error    | `jsx-a11y(prefer-tag-over-role)`         | A11y preference; evaluate against existing markup semantics                                     |
|     4 | warning  | `unicorn(consistent-function-scoping)`   | Style/preference                                                                                |
|     3 | warning  | `promise(always-return)`                 | Mixed; inspect handlers, may be noisy for UI callbacks                                          |
|     2 | error    | `jsx-a11y(no-redundant-roles)`           | Real a11y cleanup                                                                               |
|     1 | error    | `vitest(expect-expect)`                  | Test quality; inspect test intent                                                               |
|     1 | error    | `jsx-a11y(control-has-associated-label)` | Real a11y finding candidate                                                                     |
|     1 | warning  | `import(no-named-as-default)`            | Style/preference                                                                                |

### 4.3 React plugin misfire check

Command: same config with `--react-plugin` and correctness/suspicious/perf
enabled.

Result: **463 React diagnostics**. Top rules:

| Count | Severity | Rule                                       | Notes                                        |
| ----: | -------- | ------------------------------------------ | -------------------------------------------- |
|   452 | error    | `react(react-in-jsx-scope)`                | Not applicable: modern JSX transform / Solid |
|     4 | error    | `react(no-unstable-nested-components)`     | React-specific heuristic                     |
|     3 | error    | `react(purity)`                            | React-specific                               |
|     3 | error    | `react(immutability)`                      | React-specific                               |
|     1 | error    | `react(jsx-no-constructed-context-values)` | React-specific                               |

**Decision:** do not enable the `react` plugin for Solid code. Keep
`eslint-plugin-solid` as the JS plugin source for Solid rules.

### 4.4 eslint-plugin-solid JS plugin status

- Loaded successfully under oxlint 1.94.0 with `oxlint.config.ts`.
- Produced the same 7 `solid/reactivity` warnings as current lint.
- No plugin load errors observed during baseline runs.
- JS plugins remain alpha in Oxc; later prompts should pin oxlint and retest
  plugin behavior before broad rollout.

### 4.5 Frontend rule set (prompt 05)

Implemented in prompt 05 on `oxlint` 1.95.0 with `oxlint-tsgolint` 7.0.2008.
The frontend lint command is:

```sh
oxlint --type-aware --deny-warnings --report-unused-disable-directives-severity=error .
```

| Rule or category                                    | Severity                  | Reason                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------------------------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `correctness` category                              | error                     | Catches real defects with low false-positive rate.                                                                                                                                                                                                                                                                                                                                           |
| `suspicious` category                               | error                     | Catches likely bugs; noisy rules are disabled individually below.                                                                                                                                                                                                                                                                                                                            |
| `perf` category                                     | warn                      | Performance hints; promoted to CI failure by `--deny-warnings`.                                                                                                                                                                                                                                                                                                                              |
| `pedantic` and `style` categories                   | off                       | Not enabled by default; add individual rules only with a reason.                                                                                                                                                                                                                                                                                                                             |
| `typescript` plugin                                 | enabled                   | TypeScript-aware lint rules and type-aware checks.                                                                                                                                                                                                                                                                                                                                           |
| `unicorn` plugin                                    | enabled                   | General JS/TS bug and quality rules; noisy style rules disabled below.                                                                                                                                                                                                                                                                                                                       |
| `oxc` plugin                                        | enabled                   | Oxc-specific correctness rules.                                                                                                                                                                                                                                                                                                                                                              |
| `import` plugin                                     | enabled                   | Module graph checks.                                                                                                                                                                                                                                                                                                                                                                         |
| `import/no-cycle`                                   | error                     | Prevents circular dependencies.                                                                                                                                                                                                                                                                                                                                                              |
| `import/no-unresolved`                              | not available             | Not present in oxlint 1.95.0 rules; tracked for later if added upstream.                                                                                                                                                                                                                                                                                                                     |
| `import/no-duplicates`                              | error                     | Prevents duplicate imports.                                                                                                                                                                                                                                                                                                                                                                  |
| `import/no-self-import`                             | error                     | Prevents a module importing itself.                                                                                                                                                                                                                                                                                                                                                          |
| `import/no-empty-named-blocks`                      | error                     | Removes empty import blocks.                                                                                                                                                                                                                                                                                                                                                                 |
| `import/no-unassigned-import`                       | off                       | Side-effect imports are used for CSS and test setup files.                                                                                                                                                                                                                                                                                                                                   |
| `import/no-named-as-default`                        | off                       | Style/preference; low value in this codebase.                                                                                                                                                                                                                                                                                                                                                |
| `import/no-named-as-default-member`                 | off                       | Style/preference; low value in this codebase.                                                                                                                                                                                                                                                                                                                                                |
| `promise` plugin                                    | enabled                   | Promise handling checks; noisy UI callback rules disabled below.                                                                                                                                                                                                                                                                                                                             |
| `promise/always-return`                             | off                       | Noisy for UI callbacks and event handlers; mixed value in baseline.                                                                                                                                                                                                                                                                                                                          |
| `promise/catch-or-return`                           | off                       | Noisy for UI callbacks and action handlers; mixed value in baseline.                                                                                                                                                                                                                                                                                                                         |
| `promise/no-callback-in-promise`                    | off                       | Noisy in UI code; low signal for this codebase.                                                                                                                                                                                                                                                                                                                                              |
| `vitest` plugin                                     | enabled                   | Test quality rules, scoped to test files by convention and overrides.                                                                                                                                                                                                                                                                                                                        |
| `vitest/no-focused-tests`                           | error                     | Prevents `.only` tests from landing.                                                                                                                                                                                                                                                                                                                                                         |
| `vitest/expect-expect`                              | error                     | Ensures tests make assertions.                                                                                                                                                                                                                                                                                                                                                               |
| `vitest/no-disabled-tests`                          | warn                      | Flags skipped tests without blocking unrelated work as hard errors.                                                                                                                                                                                                                                                                                                                          |
| `vitest/require-mock-type-parameters`               | off                       | Style/preference; 83 noisy baseline errors with low runtime value.                                                                                                                                                                                                                                                                                                                           |
| `jsx-a11y` plugin                                   | enabled                   | Accessibility findings are treated as real defects.                                                                                                                                                                                                                                                                                                                                          |
| `jsx-a11y/label-has-associated-control`             | error                     | Requires label/control association; configured with `controlComponents: ["Input","Select","Textarea"]` and `depth: 3`.                                                                                                                                                                                                                                                                       |
| `react` plugin                                      | not enabled               | React rules misfire on Solid/modern JSX (463 diagnostics in baseline).                                                                                                                                                                                                                                                                                                                       |
| `eslint-plugin-solid/configs/v2` (JS plugin)        | enabled                   | Solid 2 lint rules required by frontend AGENTS.md.                                                                                                                                                                                                                                                                                                                                           |
| `eslint-plugin-testing-library` (JS plugin)         | enabled in test overrides | Testing Library rules for test files; loaded and verified under oxlint 1.95.0.                                                                                                                                                                                                                                                                                                               |
| `no-console`                                        | error in src              | Prevents accidental console output in app code; disabled in tests and config files.                                                                                                                                                                                                                                                                                                          |
| `no-debugger`                                       | error                     | Prevents debugger statements.                                                                                                                                                                                                                                                                                                                                                                |
| `eqeqeq`                                            | error                     | Prevents accidental type-coercing equality.                                                                                                                                                                                                                                                                                                                                                  |
| `typescript/no-unsafe-type-assertion`               | off                       | Type-aware rule is too noisy for existing DOM and test-mock assertions; revisit after typed test helpers are improved.                                                                                                                                                                                                                                                                       |
| `typescript/no-unnecessary-type-assertion`          | error                     | Type-aware rule enabled in prompt 06; removes redundant assertions and aligns types. Four generator-action yield casts in `Account.tsx` keep inline disables because tsc 5.6.3 types `yield` as `unknown` while tsgolint infers the resolved type.                                                                                                                                           |
| `typescript/no-misused-promises`                    | error                     | Type-aware rule enabled in prompt 06; catches ignored Promise returns and conditional/spread misuse. `checksVoidReturn.attributes` stays enabled (default) to catch async handlers passed to JSX attributes; Solid form handlers were wrapped with `void` (for example `onSubmit={(e) => { void submitCreate(e); }}` in `Calendar.tsx`) because the actions already handle their own errors. |
| `typescript/switch-exhaustiveness-check`            | error                     | Type-aware rule enabled in prompt 06; ensures union switches handle all cases. No findings in current frontend code.                                                                                                                                                                                                                                                                         |
| `--report-unused-disable-directives-severity=error` | error                     | Keeps inline suppressions honest and current.                                                                                                                                                                                                                                                                                                                                                |

Inline suppressions remain in source for narrow false positives or tool-friction cases (text-initial Avatar using `role="img"`, Solid custom control label association, Solid/reactivity action-handler false positives, and the tsc/tsgolint generator-yield typing mismatch in `Account.tsx`). Each has a reason comment.

## 5. Formatter churn comparison

Measured with `oxfmt@0.80.0` on temp copies of the worktree (excluding
`.git`, `node_modules`, `dist`, `.opencode/skills/**`,
`projects/sauna/docs/mocks/**`, `package-lock.json`). Each config was run as:

```sh
npx --yes oxfmt@0.80.0 -c .oxfmtrc.jsonc .
```

The line counts below are added+removed lines from unified diffs against the
unformatted copy.

### 5.1 Candidate configs

| Config                       | Settings                                                                                                     | Files changed | Lines changed |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------: | ------------: |
| A: defaults                  | oxfmt defaults + ignorePatterns for exclusions                                                               |            93 |          7691 |
| B: inferred                  | A + `printWidth:120`, `singleQuote:false`, `semi:true`, `trailingComma:"all"`, `tabWidth:2`, `useTabs:false` |            93 |          7818 |
| C: inferred + printWidth 100 | B with `printWidth:100`                                                                                      |            93 |          7691 |

Observed style sample (frontend TS/TSX): double quotes dominant, semicolons
present, 90th percentile line length ~106 chars, 95th ~162. No existing
`.editorconfig` or Prettier config found.

### 5.2 Churn by file type

| Type     | A files | A lines | B files | B lines | C files | C lines |
| -------- | ------: | ------: | ------: | ------: | ------: | ------: |
| TS       |       5 |      33 |       7 |      66 |       5 |      33 |
| TSX      |      20 |     222 |      20 |     344 |      20 |     222 |
| JSON     |      14 |     535 |      14 |     535 |      14 |     535 |
| JSONC    |       1 |      25 |       1 |      25 |       1 |      25 |
| CSS      |       1 |       1 |       1 |       1 |       1 |       1 |
| YAML     |      19 |    4266 |      17 |    4239 |      19 |    4266 |
| Markdown |      33 |    2609 |      33 |    2608 |      33 |    2609 |

### 5.3 Representative diff excerpts

Config A/C (TSX, `product/frontend-solid/src/components/AppShell.tsx`):

```diff
-                title={chrome().nextRedeploy ? new Date(Date.parse(chrome().nextRedeploy)).toLocaleString() : undefined}
+                title={
+                  chrome().nextRedeploy
+                    ? new Date(Date.parse(chrome().nextRedeploy)).toLocaleString()
+                    : undefined
+                }
```

Config B (same file, different wrapping at `printWidth:120`):

```diff
-    to === "/"
-      ? location.pathname === "/"
-      : location.pathname === to || location.pathname.startsWith(`${to}/`);
+    to === "/" ? location.pathname === "/" : location.pathname === to || location.pathname.startsWith(`${to}/`);
```

YAML sample (Config A, `.github/workflows/frontend-ci.yml`):

```diff
-          node-version: '22'
+          node-version: "22"
```

### 5.4 Recommendation

- **Recommend Config A/C equivalent**: oxfmt defaults with explicit
  `ignorePatterns`, `proseWrap: "preserve"` for Markdown/YAML safety, and no
  style overrides unless a later measured diff justifies them. Defaults already
  match observed style: double quotes, semicolons, trailing commas all,
  tabWidth 2, printWidth 100.
- **Do not use printWidth 120** as initial default: it changed wrapping shape
  and increased TS/TSX churn in this sample (344 vs 222 TSX lines).
- **Treat YAML and Markdown churn as high-risk mass changes**: 4266 YAML and
  2609 Markdown lines changed under defaults. Run formatter in a dedicated
  mechanical commit and review YAML workflow quoting/comment/blank-line
  behavior carefully.
- Keep `proseWrap: "preserve"` for Markdown and YAML.

## 6. Type-aware linting

Implemented for `product/frontend-solid` in prompt 06 (building on prompt 05,
which enabled `--type-aware` with `oxlint-tsgolint`).

### Backend

| Item            | Value                                                                  | Notes                                                                                                                                                                                                                             |
| --------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Backend         | `oxlint-tsgolint`                                                      | Stable documented backend; oxlint auto-detects installed type-aware backends. `tsrs` is not installed; if both were installed, oxlint would prefer `tsrs` per current docs, so keep only the intended backend in devDependencies. |
| Package version | `7.0.2008`                                                             | Pinned exact in `product/frontend-solid/package.json` and lockfile.                                                                                                                                                               |
| Oxlint version  | `1.95.0`                                                               | Pinned exact; same major/minor line as tsgolint.                                                                                                                                                                                  |
| Config          | `options.typeAware: true` in `product/frontend-solid/oxlint.config.ts` | Config preferred so editors pick it up; lint script also passes `--type-aware`.                                                                                                                                                   |

Platform notes (checked for oxlint-tsgolint 7.0.2008):

- Linux x64 and arm64, macOS x64/arm64, Windows x64/arm64 have published optional platform packages.
- No `linux-x64-musl`/Alpine musl package is published. `npm ci` succeeds in the frontend Docker build (`node:26.13.1-alpine`) because tsgolint platform packages are optional dependencies; the Dockerfile runs only `npm run build` (no lint), so missing musl backend binary does not break the image build. `docker build -f product/frontend-solid/Dockerfile product/frontend-solid` was verified locally.
- CI runs on `ubuntu-latest` (Linux x64) and installs dependencies with `npm ci`; type-aware lint runs in the normal lint step.

### tsconfig compatibility

`product/frontend-solid/tsconfig.json` was checked against Oxc type-aware
constraints: no `baseUrl`, no deprecated TS6/removed TS7 options observed.
`tsgolint` uses TypeScript 7.0 behavior; `tsrs` uses 7.1. Invalid tsconfig
options are reported when `--type-check` is enabled.

### Enabled type-aware rules

The named prompt 06 rules are enabled at error level:

| Rule                                       | Status                       | Reason / notes                                                                                                                                                                                                                                                               |
| ------------------------------------------ | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `typescript/no-floating-promises`          | error (correctness default)  | Catches unhandled Promises in API/session/event flows. No findings on current code.                                                                                                                                                                                          |
| `typescript/no-misused-promises`           | error (enabled in prompt 06) | Catches Promise misuse in conditionals/spreads/void returns. `checksVoidReturn.attributes` kept enabled (default) to catch async JSX handlers; 9 Solid form handlers were wrapped as `onSubmit={(e) => { void handler(e); }}` because they already handle errors internally. |
| `typescript/await-thenable`                | error (correctness default)  | Catches awaiting non-Promise values. No findings on current code.                                                                                                                                                                                                            |
| `typescript/no-unnecessary-type-assertion` | error (enabled in prompt 06) | Removes redundant assertions. 15 findings fixed; 4 generator-action `yield` casts in `Account.tsx` keep inline disables because tsc 5.6.3 types generator yields as `unknown` while tsgolint infers the resolved type.                                                       |
| `typescript/restrict-template-expressions` | error (correctness default)  | Prevents unsafe template string interpolation. No findings on current code.                                                                                                                                                                                                  |
| `typescript/switch-exhaustiveness-check`   | error (enabled in prompt 06) | Ensures union switches are exhaustive. No findings on current code.                                                                                                                                                                                                          |

Rules left off:

| Rule                                  | Status | Reason                                                                                                                                          |
| ------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `typescript/no-unsafe-type-assertion` | off    | Type-aware rule is too noisy for existing DOM and test-mock assertions; revisit after typed test helpers are improved (carried from prompt 05). |

### Baseline backend comparison (prompt 01, measured on oxlint 1.94.0)

| Metric          | oxlint-tsgolint               | tsrs                          |
| --------------- | ----------------------------- | ----------------------------- |
| Package version | 7.0.2008                      | 7.1.0-beta.tsrs5              |
| Run time (real) | ~1.41s                        | ~1.04s                        |
| Diagnostics     | 211 (118 errors, 93 warnings) | 211 (118 errors, 93 warnings) |

Prompt 01 recommended tsgolint for stable rollout; prompt 06 keeps that choice.

### Timings

Local measurements on 2026-11-24 (`product/frontend-solid`, Node v26.8.1,
Linux x64, warm cache):

| Measurement                                                       | Real time                                                       |
| ----------------------------------------------------------------- | --------------------------------------------------------------- |
| `npm run lint` after prompt 06 (type-aware + 3 new rules enabled) | ~1.52s (3 runs: 1.52s/1.52s/1.50s user+sys varied; real ~1.52s) |
| Same command with the 3 prompt 06 rules turned off                | ~1.79s                                                          |

The small delta is within noise; type-aware linting overhead was already present
from prompt 05. CI lint timing should be observed on the PR run; frontend CI
continues to run lint as a dedicated step.

## 7. `--type-check` vs `tsc --noEmit`

Commands (frontend):

```sh
npx tsc --noEmit
npx oxlint -c oxlint.config.ts --type-aware --type-check -f json
```

Results:

| Check                              | Result                                                                                                                                                                                  |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tsc --noEmit`                     | Exit 0, no diagnostics                                                                                                                                                                  |
| `oxlint --type-aware --type-check` | Exit 0, no TypeScript type-error diagnostics observed; 15 lint warnings from active rules/config (7 `solid/reactivity`, 7 `typescript(await-thenable)`, 1 `typescript(unbound-method)`) |

**Recommendation:** keep `tsc --noEmit` as the authoritative typecheck in CI and
package scripts. `--type-check` can be evaluated later as an additive signal,
but this baseline does not justify replacing `tsc`.

## 8. Vite / Rolldown findings

Source: `product/frontend-solid/package.json`, `vite.config.ts`,
`@solidjs/vite-plugin@3.0.1` package metadata, and
`FORCE_COLOR=0 npx vite build --debug` output.

| Observation               | Evidence                                                                                                                                                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Vite version              | `vite@8.3.0`                                                                                                                                                 |
| Bundler/runtime options   | Debug config shows `rolldownOptions` for build/optimizer environments                                                                                        |
| Minifier                  | Debug config shows `minify: 'oxc'` and `cssMinify: true`                                                                                                     |
| Transform/runtime plugins | Debug log includes `builtin:oxc-runtime`, `vite:oxc`, `builtin:vite-transform`                                                                               |
| esbuild presence          | `esbuildOptions` appears in debug config (optimizer/prebundle areas), but build minify/transform path is Oxc/Rolldown-oriented in Vite 8                     |
| Solid JSX transform       | `@solidjs/vite-plugin@3.0.1` depends on `@solidjs/compiler@^2.0.0`; no `babel` string found in build debug log; Babel appears only in plugin devDependencies |

**Conclusion:** Vite 8 already uses Rolldown/Oxc for core transform/minify paths.
No extra Rolldown/Oxc minify plugin is needed. The Solid plugin uses the Solid
compiler; this baseline found no evidence that it uses Babel for JSX in the
production build.

## 9. Rollout plan (remaining prompts)

| Prompt | Branch (expected) | Expected scope / size  | Notes                                                                                                                                                  |
| ------ | ----------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 02     | `oxc/02-*`        | Small/medium config PR | Add root formatter/lint tooling layout decisions; may include `.git-blame-ignore-revs` only if mechanical commit already merged earlier (not expected) |
| 03     | `oxc/03-*`        | Medium mechanical PR   | Repo-wide oxfmt formatting; separate mechanical commit with exact command/version                                                                      |
| 04     | `oxc/04-*`        | Small follow-up        | Add merged mechanical SHA to `.git-blame-ignore-revs`                                                                                                  |
| 05     | `oxc/05-*`        | Medium                 | Frontend oxlint config/rule cleanup, fix real findings                                                                                                 |
| 06     | `oxc/06-*`        | Medium                 | dev-ops/testing and repo-wide lint coverage                                                                                                            |
| 07     | `oxc/07-*`        | Small/medium           | Type-aware linting enablement and tuning                                                                                                               |
| 08     | `oxc/08-*`        | Small                  | CI/editor/agent workflow integration                                                                                                                   |
| 09     | `oxc/09-*`        | Small                  | Docs/cleanup and final verification                                                                                                                    |

Sizes are estimates; actual PRs must stay focused and follow common-rule
mechanical/manual commit separation.

## 10. Open decisions for owner

1. **Formatter churn tolerance:** defaults produce 93 changed files / 7691
   changed lines (including 4266 YAML and 2609 Markdown). Is this acceptable in
   a dedicated mechanical PR?
2. **Type-aware backend:** recommend `oxlint-tsgolint` for stable rollout now;
   confirm whether to revisit `tsrs` when it leaves beta.
3. **Rule strictness:** keep CI at `--deny-warnings` eventually, but initial
   rollout needs staged rule selection to avoid 110+ noisy errors from
   style-heavy rules.
4. **A11y and Solid findings:** fix as code changes (manual) rather than
   suppress; confirm priority for 19 `jsx-a11y(label-has-associated-control)`
   findings.
5. **YAML workflow formatting:** Oxfmt changed quoting style in workflow YAML;
   confirm this is acceptable given owner-reviewed workflow files.

## Appendix: commands run

All commands were run in worktree `/home/adsv/booking-system-wt-oxc-01` on
branch `oxc/01-baseline` unless noted.

| Command                                                                                                                                          | Result                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `git fetch origin`                                                                                                                               | OK                                                                                                                  |
| `git worktree add -b oxc/01-baseline /home/adsv/booking-system-wt-oxc-01 origin/main`                                                            | OK (based on `origin/main` at 7fc7794)                                                                              |
| `git status --short`                                                                                                                             | clean before and after measurements                                                                                 |
| `npm view oxlint version && npm view oxfmt version && npm view oxlint-tsgolint version`                                                          | 1.95.0, 0.80.0, 7.0.2008                                                                                            |
| `npm view tsrs version`                                                                                                                          | 7.1.0-beta.tsrs5                                                                                                    |
| Inventory Python script over `git ls-files` with exclusions                                                                                      | 163 Oxc-handled files                                                                                               |
| `cd product/frontend-solid && npm ci`                                                                                                            | OK                                                                                                                  |
| `cd product/frontend-solid && npm run lint`                                                                                                      | 7 warnings, 0 errors                                                                                                |
| `npx oxlint -c oxlint.config.ts -D correctness -W suspicious -W perf --import-plugin --vitest-plugin --jsx-a11y-plugin --promise-plugin -f json` | 137 diagnostics (110 errors, 27 warnings)                                                                           |
| `npx oxlint -c oxlint.config.ts --react-plugin -D correctness -D suspicious -D perf -f json`                                                     | 463 React diagnostics; 452 `react/react-in-jsx-scope`                                                               |
| `npx --yes oxfmt@0.80.0 --check` / temp copy write runs with configs A/B/C                                                                       | A/C: 93 files, 7691 lines; B: 93 files, 7818 lines                                                                  |
| `npm install --no-save oxlint-tsgolint@7.0.2008` + `oxlint --type-aware ... -f json`                                                             | 211 diagnostics, ~1.41s real                                                                                        |
| `npm uninstall --no-save oxlint-tsgolint` + `npm install --no-save tsrs@7.1.0-beta.tsrs5` + same command                                         | 211 diagnostics, ~1.04s real                                                                                        |
| `npm view @oxlint-tsgolint/linux-x64@7.0.2008 dist.unpackedSize`                                                                                 | 23037889 bytes                                                                                                      |
| `du -sh node_modules/tsrs node_modules/@tsrs*` (while installed)                                                                                 | 5.7M + 35M                                                                                                          |
| `npx tsc --noEmit`                                                                                                                               | exit 0                                                                                                              |
| `npx oxlint -c oxlint.config.ts --type-aware --type-check -f json`                                                                               | exit 0, no TS type errors reported; 15 lint warnings                                                                |
| `FORCE_COLOR=0 npx vite build --debug`                                                                                                           | build succeeded; debug log shows rolldownOptions, minify oxc, builtin:oxc-runtime, vite:oxc, builtin:vite-transform |
| `grep -ia babel /tmp/opencode/vite-build.log`                                                                                                    | no matches                                                                                                          |
| `npm uninstall --no-save tsrs` (cleanup)                                                                                                         | OK                                                                                                                  |
| `git status --short` after cleanup                                                                                                               | clean                                                                                                               |

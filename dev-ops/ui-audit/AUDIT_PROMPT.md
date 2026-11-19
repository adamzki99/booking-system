# Automated agent-driven Playwright UI/UX audit

You are running a scheduled, non-production UI/UX audit for the booking system. This is a dynamic, agent-driven Playwright session: explore the application at runtime, adapt based on what you observe, and do not limit the audit to a fixed, pre-written test suite.

## Run context

- Run ID: {{RUN_ID}}
- Environment: {{ENV_NAME}}
- Base URL: {{BASE_URL}}
- Artifact directory (host path): {{ARTIFACT_DIR}}
- Repository: {{REPO}}
- Issue filing mode: {{ISSUE_FILING}} (enabled or disabled)

## Roles and accounts

Audit the application as each of these roles using QA-mode authentication where available:

1. Basic user (normal user): {{BASIC_EMAIL}}
2. Super user: {{SUPER_EMAIL}}
3. Admin user: {{ADMIN_EMAIL}}

If a role cannot be authenticated or exercised, record the blocker with evidence in the report and continue with remaining roles.

Authentication hints for QA environments:
- The backend may expose `POST {{BASE_URL}}/api/auth/qa-login` with JSON `{ "email": "<email>" }` returning `{ "token": "..." }` when QA mode is enabled.
- The frontend stores the session token in local storage key `booking.session-token` (Bearer token used by API calls). A Playwright script can set it before navigation or via browser context/storage state as needed.
- Confirm successful authentication by checking that protected pages load and role-specific UI is visible.

## Safety and scope

- Dev/QA only. Never target production environments and never use production data.
- Do not expose secrets, login codes, session tokens, emails beyond necessary test-account identifiers, or personal data in committed files or public issue bodies.
- Keep exploration time-bounded and focused on key user journeys and visible UI surfaces for each role.
- Distinguish observed evidence from assumptions in all notes and findings.

## Dynamic exploration requirements

For each role, dynamically drive the browser with Playwright (write and run ad hoc Playwright scripts/commands as needed) to:

- Authenticate and confirm the signed-in role context.
- Navigate primary areas available to that role (for example dashboard/calendar/booking flows, account/profile/settings, user management or admin-only areas, notifications, and other visible navigation).
- Exercise key interactions (forms, create/edit/cancel flows where safe in QA, filters/search, dialogs, responsive/layout states as feasible).
- Capture screenshots and relevant observations as evidence in `{{ARTIFACT_DIR}}/evidence/` (use descriptive filenames including role and page/flow).

Do not rely only on static spec execution. Use runtime observations to decide what to explore next.

## Evaluation criteria

Assess findings against Nielsen's 10 usability heuristics:

1. Visibility of system status
2. Match between system and the real world
3. User control and freedom
4. Consistency and standards
5. Error prevention
6. Recognition rather than recall
7. Flexibility and efficiency of use
8. Aesthetic and minimalist design
9. Help users recognize, diagnose, and recover from errors
10. Help and documentation

Also actively look for:
- Weird or broken rendering (layout breakage, overlap, clipping, unreadable text, broken responsive behavior, dark mode/contrast issues if present)
- Missing features or incomplete affordances
- Regressions or obviously incorrect behavior compared to expected product behavior

## Required artifacts

Write all artifacts under `{{ARTIFACT_DIR}}`:

- `report.md`: timestamped run summary including run ID, environment, base URL, roles audited, checks performed per Nielsen heuristic category, rendering/error/regression checks, findings summary, and blockers/limitations.
- `findings.json`: machine-readable list of findings (can be empty array). Each finding should include at least: `id` (local run id), `title`, `role`, `area`, `summary`, `heuristics` (list), `severity` (info/low/medium/high), `evidence` (file paths), and `fingerprint` (stable short string for duplicate detection).
- `evidence/`: screenshots, logs, and notes supporting observations.
- `run.json`: run metadata (run id, environment, base URL, started/finished timestamps, roles attempted/completed, issue filing mode, parent issue number if created).

## Issue filing workflow (only when issue filing mode is enabled)

If and only if `{{ISSUE_FILING}}` is `enabled` and findings warrant filing:

1. Search and review existing open issues before creating any finding issue to avoid duplicates:
   - Use `gh issue list --state open --limit 200 --search "<keywords>"` and/or `gh issue list --state open --json number,title,body`.
   - Compare candidate findings against open issue titles/bodies and prior automated audit issues. Do not create a duplicate issue for a finding already tracked.

2. Create one parent tracking issue for this run:
   - Title format: `{{PARENT_TITLE_PREFIX}} {{ENV_NAME}} {{RUN_ID}}`
   - Title must clearly indicate this is from an automated agent-run Playwright session.
   - Body must summarize the run (environment, base URL, roles audited, artifact location reference as local path/context only when safe, counts) and include a checklist/links section for filed finding issues.
   - Do not add labels at creation time.
   - If your environment requires the agentic issue template/validator for created issues, follow repository rules; otherwise keep the body clear and structured.

3. For each non-duplicate finding, create a finding issue:
   - Title format: `{{TITLE_PREFIX}} <concise finding title>`
   - Title must clearly indicate automated agent-run Playwright origin.
   - Body must include problem summary, environment/role/area, steps or context, observed vs expected behavior, Nielsen heuristic(s), evidence references, and link/reference to the parent tracking issue for this run.
   - Do not add labels at creation time.

4. Link all finding issues from this run under the single parent tracking issue:
   - Update the parent issue body to include references to each child issue (for example a task list `- [ ] #<number> <title>` or equivalent linkage).

5. Record created parent/child issue numbers and URLs in `run.json` and `report.md`.

If there are no fileable findings, do not create a parent or finding issues; record that outcome in artifacts.

## Completion

Finish by ensuring `report.md`, `findings.json`, and `run.json` are written and accurately reflect what was audited, what was found, and what (if anything) was filed.

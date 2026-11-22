# Frontend, UX and E2E Review: React SPA, Mockups and Playwright

**Scope** `product/frontend-solid/**` (App.tsx, main.tsx, RequireSession, api/*, auth/SessionContext, components/AppShell, pages/*, theme.ts, index.css, index.html, all `*.test.ts(x)`, vite.config.ts, tsconfig.json, package.json + lockfile, Dockerfile), `projects/sauna/docs/mocks/*.html` (unpacked and read), `dev-ops/testing/**`, `dev-ops/scripts/run-playwright.sh`, `.github/workflows/frontend-ci.yml`, issues #120–#123 and their `factory:plan` comments (read with `gh issue view` before a no-network restriction took effect; everything taken from them is marked "(from GitHub issue)"). I also read the backend/sidecar/Caddy code that the SPA depends on (`product/backend/internal/{auth,booking,server}`, `projects/sauna/sidecar/internal/server/server.go`, `projects/sauna/config/Caddyfile`). This was a static review only: I did not install, build or run anything. · **Reviewed** 2026-11-19 at commit 45f6ee5

## Summary

The frontend is a small (~1.1k production lines) and fairly tidy React 18 + Chakra UI v2 SPA. It has four routes (login, calendar, account, users), a thin typed `fetch` wrapper, a bearer token kept in `localStorage`, and a test file next to almost every module. It covers the happy-flow features but is still a functional prototype rather than a resident-facing product. Booking means typing two free-form `datetime-local` values. Destructive admin actions fire without confirmation, which goes against flow step 10 ("the super user confirms the cancellation"). Pages have no loading states, and the session logic signs users out on any transient error, which matters in an hourly-redeploy factory. Several correctness bugs (the address/role selects, half-enabled dark mode, stale cached `index.html` after redeploys) are not caught by the unit tests or the single Playwright spec. That spec is not run in CI and, as written, cannot pass. The owner-approved redesign issues (#120–#123) are detailed but not ready for an unsupervised builder. According to the issues and their plans (from GitHub issue), the plans predate the theme work merged today (#152) and the email-change rework (#133). They also collide with each other in `Calendar.tsx`, and they need data the API does not have (member names, notifications, search).

What's working well:
- **Small, honest API layer.** `src/api/client.ts` has one `request()` with a typed `ApiError` carrying `status`, `localStorage` access wrapped for private mode, and per-resource modules (`bookings.ts`, `users.ts`, ...) that normalize the backend's duplicated snake/camel keys in one place (`bookings.ts:17-25`).
- **Tests use the right primitives.** React Testing Library role and label queries, a provider-aware `render` (`src/test-utils.tsx`), explicit `cleanup`, and mocks at module boundaries. `formatRedeployCountdown` has proper edge-case tests (`AppShell.test.tsx:94-108`).
- **The theme encodes the mockup with good contrast.** White on `accent` #9A2F22 is 7.5:1, `muted` #5E4B45 on canvas is 7.6:1, and the placeholder is 5.2:1. Controls are 44 px, which suits touch (`theme.ts:113-117, 165`).
- **Runtime configuration lives in the deployment, not the build.** The header, footer and redeploy schedule come from `/api/chrome` (the sidecar), so `product/` has no baked-in sauna strings and no `VITE_*` environment variables.
- **The CI basics are sound.** Actions are pinned to SHAs, the install uses `npm ci`, and `npm run build` runs `tsc --noEmit` under `strict` + `noUnusedLocals` (`frontend-ci.yml:27-43`, `tsconfig.json:8-11`).
- **The issues are unusually concrete (from GitHub issue).** They give measurements, ARIA names and acceptance criteria, and the plans flag real traps (for example, the #122 plan notes that a closed Chakra `Menu` unmounts the `Cancel booking` button the tests rely on).

## Findings

| ID | Severity | Effort | Title |
|----|----------|--------|-------|
| FE-01 | High | S | Session restore deletes the token on any error; no global 401 handling |
| FE-02 | High | M | Cancel, remove and broadcast run without confirmation, busy state or success feedback |
| FE-03 | High | S | Change-address/change-role selects submit an empty user id by default |
| FE-04 | High | S | Dark mode is half-enabled, so key text and controls become near-invisible |
| FE-05 | High | M | Redesign issues #120–#123 are not build-ready (stale plans, collisions, missing data) |
| FE-06 | High | M | E2E: one spec, never run in CI, and it cannot pass as written |
| FE-07 | Medium | M | Booking UX is not phone-friendly: free datetime fields, full history, no owner, no availability |
| FE-08 | Medium | M | Time zone, locale and error-message handling are ad hoc |
| FE-09 | Medium | M | Data fetching is ad hoc: no loading states, caching or abort; the client hides contract errors |
| FE-10 | Medium | S | Accessibility structure: nested `<main>`, invisible nav state, label mismatch, small targets |
| FE-11 | Medium | S | Static serving: no cache policy; redeploys can white-screen open tabs; no compression or CSP |
| FE-12 | Medium | S | Login flow: no way back from the code step, deep links lost, no OTP and autofill hints |
| FE-13 | Medium | S | The iCal URL can only be seen by regenerating it, which silently breaks existing subscriptions |
| FE-14 | Medium | S | Logout is client-only; 24-hour bearer token in `localStorage`; a dormant cookie path has no CSRF guard |
| FE-15 | Medium | S | Test suite: change-detector theme tests, UTC-pinned dates, no lint, no a11y checks |
| FE-16 | Low | S | Routing and app structure: duplicated guards per route, no error boundary, blank loading |
| FE-17 | Low | S | Dead code and multi-model drift (shim pages, unused aliases, misplaced types, wrong README) |
| FE-18 | Low | S | Dependency hygiene: Vite/Vitest two majors behind, odd overrides, no Dependabot for npm |

### FE-01: Session restore deletes the token on any error; no global 401 handling (High, S)

**Evidence**
- `product/frontend-solid/src/auth/SessionContext.tsx:39-45`: `.catch(() => { // Token expired or revoked: treat as signed out. setToken(null); ...})`. Every rejection is handled the same way, whether it is a network error, a 502 or 503 while the backend restarts, or a real 401.
- `product/frontend-solid/src/api/client.ts:52-63`: a non-OK response just throws `ApiError`. Nothing reacts to `status === 401` (grep finds no `401` anywhere in `src/`).
- The factory redeploys dev/QA hourly (`AppShell.tsx` shows a "Next redeploy" countdown), and logging in needs a fresh emailed code, which is rate-limited to 5 per 15 minutes (`product/backend/internal/auth/service.go:20-21`).

**Why it matters.** A resident who opens the app during a redeploy, or on a flaky mobile connection, is silently logged out and has to fetch a new email code. The opposite case also exists: when a token really expires mid-session (TTL is 24 hours, `auth/service.go:16`), the user stays on the page and every action shows "unauthorized" with no route back to login except the manual Log out button.

**Recommendation.** Only clear the token on 401 or 403. Add a central 401 hook in the client:
```ts
// client.ts
let onUnauthorized: (() => void) | null = null;
export const setUnauthorizedHandler = (fn: () => void) => { onUnauthorized = fn; };
...
if (res.status === 401) { setToken(null); onUnauthorized?.(); }
// SessionContext.tsx
useEffect(() => setUnauthorizedHandler(() => setUser(null)), []);
.catch((err) => {
  if (err instanceof ApiError && err.status === 401) setToken(null);
  else setRestoreError(err);   // show "Can't reach server – retry" instead of logging out
  if (!cancelled) setLoading(false);
});
```
Add tests for "network error keeps the token" and "401 mid-session redirects to /login".

### FE-02: Cancel, remove and broadcast run without confirmation, busy state or success feedback (High, M)

**Evidence**
- `pages/Calendar.tsx:84-92, 159-166`: `onClick={() => void onCancel(booking.id)}` cancels immediately. `projects/sauna/README.md` alternative flow step 10 says "The super user confirms the cancellation."
- `pages/Users.tsx:90-97, 179-186`: `Remove` deactivates a user in one tap. `Users.tsx:137-146`: `Broadcast` emails every basic user in one tap and then just clears the fields, with no success message.
- None of the forms in `Calendar.tsx:68-82` or `Users.tsx:78-146` has a busy or disabled state while the request runs (only Login and Account use `isLoading`), so a double tap on a phone can create two bookings or send two broadcasts.
- `Block` (`Users.tsx:123-135`) and `Copy` (`Account.tsx:99-106`) also give no feedback on success.

**Why it matters.** The system is event-sourced and has "no deletes" (`AGENTS.md`), so a mis-tap is permanent history plus an email to the affected resident. On phones, accidental taps on adjacent "Cancel booking" buttons are likely.

**Recommendation.** Add a reusable `ConfirmDialog` (Chakra `AlertDialog`) that names the object, for example "Cancel Tue 17 Nov 09:00–10:00 booked by anna@…? They will be emailed." Require it for cancel (own and other people's), remove user and broadcast (show the recipient count). Add a single `useMutation`-style helper (see FE-09) that disables the trigger while pending and calls `useToast()` on success. Put this in place before #122 moves cancel into a `Menu` (from GitHub issue).

### FE-03: Change-address/change-role selects submit an empty user id by default (High, S)

**Evidence**
- `pages/Users.tsx:47` and `:51` initialize `addressUserId` and `roleUserId` to `""`. The `<Select>`s at `:231-244` and `:268-281` have no placeholder option. React therefore shows the first email as selected while state stays `""`, so submitting without touching the select calls `changeUserAddress("", …)`, which builds a request to `PATCH /api/users//address` (`api/users.ts:50`).
- The tests always pick an option first (`Users.test.tsx:69, 109, 142`), so they never exercise the default path.
- Related problems on the same page: the visible label is "User id" while `aria-label="User"` overrides it (`:230-233`), and the select lists emails, not ids. Inactive users still get a `Remove` button (`:177`). The action cell has no `<Th>` (`:163-168` vs `:177-188`). "Active" renders as the raw string `true` or `false` (`:176`).

**Why it matters.** It is the most direct super-user workflow ("Change the address of a basic user"), and it fails with an opaque error on first use.

**Recommendation.** Add `<option value="" disabled>Choose a member…</option>` (or `placeholder="Choose a member"`) and disable submit until an id is set. Drop the conflicting `aria-label` and rename the label "Member". Hide `Remove` for `!u.active`. Add an empty `<Th><VisuallyHidden>Actions</VisuallyHidden></Th>` and render a status `Badge`. Add a regression test that submits without selecting and asserts the API is not called. Better still, move the per-user actions onto the row (an "Edit address" button per row, which #123 is about to restyle anyway).

### FE-04: Dark mode is half-enabled, so key text and controls become near-invisible (High, S)

**Evidence**
- `theme.ts:41-44`: `initialColorMode: "system", useSystemColorMode: true`. `index.css:4-6`: `:root { color-scheme: light dark; }`.
- The semantic tokens define only `default` values (`theme.ts:74-87`), and the body is forced to the light canvas (`theme.ts:99-104`). So on a phone in dark mode, Chakra's built-in components switch to their dark palettes while sitting on a light page:
  - `Code` with the default subtle/gray scheme renders `gray.200` text. That makes the iCal URL (`Account.tsx:175`) almost invisible on #FAF6F1.
  - `colorScheme="red" variant="outline"` buttons ("Cancel booking", "Remove", "Log out") use `red.200` (#FEB2B2) text, which is 1.6:1 against the canvas.
  - Table `Th` text uses light grays.
  - `color-scheme: dark` makes the native `datetime-local` picker indicator light-coloured, but the theme forces the input to `bg: "white"` (`theme.ts:171`).
- There is no `ColorModeScript` in `index.html`, so the mode can also flash on load.
- The colour values come from Chakra v2's default theme; I verified them by reading, not by rendering.

**Why it matters.** Many residents' phones run in dark mode, and the most important controls (cancel, the calendar URL) are the ones affected.

**Recommendation.** Until dark tokens exist, make the app light-only: `config: { initialColorMode: "light", useSystemColorMode: false }` and `:root { color-scheme: light; }`. Add a test asserting `theme.config.useSystemColorMode === false`. If dark mode is wanted later, give every semantic token a `_dark` value and test with Playwright `colorScheme: "dark"` (FE-06).

### FE-05: Redesign issues #120–#123 are not build-ready (High, M)

**Evidence** (all issue and plan content below is from GitHub issue; repository facts are from the local clone)
- **The plans are stale.** All four `factory:plan` comments were written between 2026-11-11 and 2026-11-17, before the theme tokens and recipes landed in `8566498` (#152, 2026-11-19) and before the verified email change in `dbaa86f` (#133, 2026-11-18).
  - The #123 plan proposes adding tokens that already exist under other names (`hairline`/`avatarText`/`canvas` vs the existing `line`/`avatarFg`/`bgCanvas`). It says "`radii.card = 1rem` (currently `0.5rem`)", although `theme.ts:96` already has `card: "16px"`. It plans a "new" `Account.test.tsx`, which already exists, and references `updateMyEmail` and a "Change email" button, neither of which exists (the API is `requestEmailChange`/`confirmEmailChange`, and the button is "Send verification code").
  - The #122 and #121 plans hardcode `bg="#EFE3D6"` and checked-chip hexes and say "do not add them to theme.ts", but the `Avatar` recipe and tokens are already there (`theme.ts:223-230`).
- **Collisions.** #121 and #122 both rewrite `Calendar.tsx` and both define `formatDayLabel`, with different contracts: #121 returns `Tue 17 Nov`, #122 returns `Today`/`Tomorrow`/`Wed 11 Nov`. #120 (plan) makes the shell CTA navigate to `/?create=1`, while the #121 plan says "The shell `Create booking` CTA … does not exist" and keeps the form always visible. The #121 plan also renames the h1 to `Bookings`, which breaks `dev-ops/testing/tests/login.spec.ts:14` (`getByRole("heading", { name: "Booking calendar" })`), and no issue mentions the e2e suite.
- **Data the API does not have.** The mockups (unpacked from `docs/mocks/*.html`) show member names ("Priya Nair"), session types ("Standard session", "Initial consultation", which are generic template leftovers), a notifications bell, "Search members" and nav items "Page 1 … Page 5". `User` has no name field (`api/auth.ts:4-10`), and there is no notifications endpoint (`product/backend/internal/server/server.go:46-82`). The #122 plan fills the gap with `user?.address ?? "Member"`, while #120 shows "user name/email": two different identity labels for the same person.
- **Semantics.** "Upcoming bookings" (#122) is built on `listBookings()` with no `from` (`Calendar.tsx:55`), so past bookings stay listed. In #121, "Quick book" lists every member's bookings as sources and computes +1..+4 weeks from the source date, which can land in the past (the #121 plan's risk 3, from GitHub issue). Neither says whether a basic user may "repeat" someone else's slot.

**Why it matters.** A builder model will follow the plan text literally. Here that means duplicate tokens, raw hex values that ignore the theme, merge conflicts between #121 and #122, and a broken e2e spec that nobody runs.

**Recommendation.** Before releasing these to the factory:
1. Re-run planning for all four on current `main` and require the plans to use the existing tokens (`accent`, `accentTint`, `line`, `avatarBg`/`avatarFg`, `bgSubtle`) and component recipes.
2. Sequence them: **FE-16 layout route → #120 → #121 → #122 → #123**, and make #121/#122 extract shared formatters into `src/lib/datetime.ts` (FE-08) so they don't each invent one.
3. Owner decisions to record in the issues: the member display label (add an optional `displayName` to the user model, or use the email local-part); drop or stub "Notifications" and keep "Search members" as client-side `?q=` only; whether Quick book repeats only *your own* bookings, with targets after today.
4. Add the acceptance criterion "`listBookings({ from: now })` for Upcoming".
5. Add "update `dev-ops/testing` specs" to every issue that renames headings, labels or nav items.

### FE-06: E2E: one spec, never run in CI, and it cannot pass as written (High, M)

**Evidence**
- `dev-ops/testing/tests/login.spec.ts` is the only spec. `playwright.config.ts:12` runs only `Desktop Chrome`. No workflow runs Playwright (`.github/workflows/` has backend, frontend, security, semgrep and sidecar CI only). It runs only through `dev-ops/scripts/run-playwright.sh` over SSH on the dev host.
- `run-playwright.sh:78` calls `get-login-code.sh … --request`, which POSTs `/api/auth/request-code` and scrapes the code from logs. The spec then clicks "Request code" again (`login.spec.ts:9`), which issues a newer code. Verification only checks the latest unconsumed code (`product/backend/internal/auth/projection.go:88-95`, `commands.go:131-143`), so the pre-fetched `LOGIN_CODE` is stale and sign-in should fail every time. I did not run it.
- There is no mail sink: codes are scraped from backend logs, so the README's flows that involve email (steps 7–8, 11–12) cannot be checked in a browser.

**Why it matters.** The main UI flows, including the super-user alternative flow, have no browser-level coverage. The UI redesign (#120–#123) will change every page's structure with nothing to catch regressions in real Chrome or Safari layouts.

**Recommendation.** Fix the spec first: either drop `--request` and fetch the code *after* the UI click, or skip the UI request step. Then add Mailpit (or similar) to the dev/QA compose so tests read mail over its API, seed users through an admin fixture, and run the suite in a GitHub workflow against `docker compose up` on PRs touching `product/**`. Add Playwright projects `Mobile Safari` (iPhone 13) and `Pixel 7`, plus an `@axe-core/playwright` scan per page. Critical journeys to cover:
1. Login: request code, then verify. Also wrong code, expired code, rate-limit message, and "use a different email".
2. Deep link: `/account` while signed out, then login, then back on `/account` (FE-12).
3. Happy flow: create a booking, see it in the list, receive the confirmation email (steps 4–8).
4. Booking rejections: past start, overlapping slot (`booking: slot already booked`), crossing midnight (sidecar single-day rule), a blocked period.
5. Basic user cancels own booking with confirmation; sees no cancel control on others' bookings.
6. Alternative flow: super user cancels another member's booking, confirms, and the member gets a cancellation email (steps 9–12).
7. Super user adds a user, who can then log in; removes a user, who can no longer request a code; changes an address.
8. Super user blocks a period; a basic user's booking inside it is rejected.
9. Broadcast reaches basic users' inboxes.
10. Email change: request, code sent to the new address, confirm; the old address can no longer log in; the current session survives.
11. iCal: get the URL and fetch the `.ics`, which contains the booking; after regenerating, the old URL fails.
12. Admin changes a role; the new super user sees the management tools.
13. Logout or expired token on a protected route redirects to `/login`.
14. Mobile viewport plus dark-mode emulation smoke test (FE-04) and the #120 drawer/dock.

### FE-07: Booking UX is not phone-friendly (Medium, M)

**Evidence**
- `Calendar.tsx:108-125`: two independent `datetime-local` inputs with no `min` (past times allowed until the backend rejects with `booking: start must be in the future`), no `step`, and no default end (for example start + 1 h). On iOS that means two full date-and-time wheel interactions per booking.
- `Calendar.tsx:55`: `listBookings()` with no range. The backend returns every *active* booking since the beginning (`product/backend/internal/booking/projection.go:127-142`), so the list grows forever and past bookings show "Cancel booking".
- Rows show only a time range (`Calendar.tsx:155-157`), with no owner and no "yours" marker. There is no availability view, so a resident finds a taken slot only by trial and error (409 `slot already booked`). Blocked periods are never shown, although `GET /blocked-periods` exists (`server.go:65`).
- `Calendar.tsx:142-144` shows "No bookings yet." while the first fetch is still in flight.
- `AppShell.tsx:58, 81-114`: the drawer is open by default and pushes content down on phones. "Log out" sits below the footer. The `Users` table needs horizontal scrolling at 390 px (`Users.tsx:160-193`).

**Why it matters.** Residents will mostly book from phones. The mockups show a card-based "Quick book" and "Upcoming bookings" layout with a bottom CTA dock, which is far from the current form.

**Recommendation.** Before or alongside #121/#122, define the booking interaction: a date picker plus duration chips (for example 30/60/90 min) or day-slot chips generated in the deployment time zone, with `min` set to now. Query `listBookings({ from: startOfToday })`. Show "You" or the owner on each row. Fetch blocked periods and render them as unavailable. Use a `Skeleton` while loading. Track this as a separate issue; none of #120–#123 covers it (from GitHub issue).

### FE-08: Time zone, locale and error-message handling are ad hoc (Medium, M)

**Evidence**
- The sidecar evaluates the "single day" rule in `Europe/Stockholm` by default (`projects/sauna/sidecar/internal/server/server.go:143, 181`). The SPA parses input and renders output in the *browser's* zone (`Calendar.tsx:34-43, 72-73`; `new Date(start).toISOString()`).
- There are three formatting styles: a hand-rolled `YYYY-MM-DD HH:mm` (`Calendar.tsx:29-43`), `toLocaleString()` in the browser locale (`AppShell.tsx:48`), and the mockups' en-GB "Tuesday, 10 November 2026". No `Intl` usage anywhere (grep).
- Unit tests pin `process.env.TZ = "UTC"` (`tests.setup.ts:7`), so local-time conversion is never tested.
- Raw backend error strings reach users: `booking: slot already booked`, `user: duplicate email` (asserted in `Account.test.tsx:120-122`).
- All strings are hardcoded English. `index.html:2` has `lang="en"`, while the mockups carry Swedish branding ("Stennäsets byförening", "Bastubokning").

**Why it matters.** A resident whose phone is set to another time zone, or travelling, books the wrong hour. The day-boundary rule disagrees with what the UI shows near midnight. Go error prefixes look broken to end users.

**Recommendation.** Create `src/lib/datetime.ts` with `Intl.DateTimeFormat(locale, { timeZone })`. Get `timeZone` (and optionally `locale`) from `/api/chrome`, which already comes from the sidecar's `BOOKING_TIMEZONE`, so the product stays generic. Convert `datetime-local` values with that zone, not the browser's. Map `ApiError.status` plus known backend messages to friendly copy in one `describeError()` helper. Ask the owner whether the UI language is English or Swedish. If Swedish, or both, add a minimal message catalogue (for example `i18next` or a typed dictionary) *before* #120–#123 add many new strings. Add a test suite run with `TZ=America/New_York`.

### FE-09: Data fetching is ad hoc (Medium, M)

**Evidence**
- Each page uses its own `useEffect` + `useState` with different patterns. `Calendar.tsx:53-66` uses `useCallback` with no unmount guard. `Users.tsx:65-76` uses a plain function and an effect with missing deps (there is no ESLint to flag it). `Account.tsx:34-49` refetches `currentUser()` even though the session already holds it, and keeps a second `me` copy.
- There are no loading states on any authenticated page (FE-07). `Account.tsx:32` shares one `busy` flag between the email form and the Regenerate button.
- `client.ts:68-76` returns `undefined as T` for an empty or unparseable 200 body. A proxy or captive-portal HTML page then crashes later at `list.map` (`bookings.ts:34`) with an unhelpful TypeError. There is no request timeout or `AbortController`.

**Why it matters.** #121 and #122 add more parallel fetches (bookings plus the users directory) to the same page. Without a shared pattern, each builder model will invent another one.

**Recommendation.** Adopt `@tanstack/react-query` (small, and fits event-sourced read models: `invalidateQueries(["bookings"])` after commands). Or, at minimum, write one `useApi()` / `useMutation()` hook that standardizes `{data, error, isLoading}`, abort-on-unmount and busy flags. In `request()`, throw `ApiError("invalid response", res.status)` on JSON parse failure instead of returning `undefined`, and add `signal: AbortSignal.timeout(15000)`.

### FE-10: Accessibility structure (Medium, S)

**Evidence**
- **Nested landmarks.** `AppShell.tsx:106` renders `<main>`, and `Calendar.tsx:97`, `Account.tsx:109` and `Users.tsx:149` each render another `Box as="main"` inside it.
- **Navigation.** Chakra's CSS reset makes `<a>` inherit colour with no underline, and `AppShell.tsx:100-102` adds no styling, so links look like plain text and the active route has no visual indicator (NavLink only sets `aria-current`). The "Toggle drawer" button has no `aria-expanded` or `aria-controls` (`:87-95`).
- **SPA focus.** `document.title` stays "Booking" on every route (`index.html:6`). Focus is not moved to the new `h1` on navigation, and there is no skip link.
- **Forms.** Errors are page-level `Alert`s, not tied to fields (no `isInvalid`/`FormErrorMessage`). There is a label mismatch in Users (FE-03).
- **Targets and contrast.** `size="xs"` Remove (`Users.tsx:180`) is about 24 px, and `size="sm"` (36 px) is used for Cancel, Copy, Regenerate and Log out, all below the theme's own 44 px target. The input border `line` #E9DDD5 on white is 1.33:1 (WCAG 1.4.11 asks for 3:1 for component boundaries), and the focus halo `accentTint` on white is about 1.2:1.

**Recommendation.** Have only AppShell render `<main id="main" tabIndex={-1}>`, and make pages render `<Box as="section">`. Style nav links with `_activeLink`/`aria-current` (the #120 spec already defines the active tint, from GitHub issue). Add a `usePageTitle("Bookings")` hook that also focuses the h1. Use `size="md"` for all touch actions. Darken the input border token (for example #B9A79D, about 2.3:1, or use `muted` for 3:1+) and use `accent` for the focus ring. Add `eslint-plugin-jsx-a11y` and the axe e2e checks from FE-06.

### FE-11: Static serving: no cache policy, redeploys can white-screen open tabs, no compression or CSP (Medium, S)

**Evidence**
- `product/frontend-solid/Dockerfile:17-20`: on start it runs `rm -rf /srv/*; … cp -a /www/. /srv/; exec sleep infinity`, so every deploy deletes the previous hashed `/assets/*.js`.
- `projects/sauna/config/Caddyfile:41-44`: `try_files {path} /index.html` + `file_server`. There is no `Cache-Control` and no `encode`.
- A browser that heuristically cached `index.html` (it has a `Last-Modified` and no `no-cache`) requests the old `/assets/index-<oldhash>.js`. `try_files` answers with `index.html` (`text/html`), the module fails to load, and the user sees a blank page. The same happens to any open tab that lazy-loads after a deploy.
- No security headers. That matters more because the session token is readable from JS (FE-14).

**Recommendation.** In the Caddyfile:
```caddy
encode zstd gzip
@assets path /assets/*
header @assets Cache-Control "public, max-age=31536000, immutable"
@html not path /assets/*
header @html Cache-Control "no-cache"
header Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'"
header X-Content-Type-Options nosniff
header Referrer-Policy same-origin
handle /assets/* { file_server }   # real 404 for missing assets instead of index.html
```
Chakra/Emotion injects inline styles, so `style-src` needs `'unsafe-inline'` (or a nonce). Copy the new build *before* removing old assets, or keep the previous build's assets for one release. Better: build a Caddy image with `dist` baked in and drop the `sleep infinity` sidecar container.

### FE-12: Login flow (Medium, S)

**Evidence**
- `Login.tsx:67-93`: once `codeSent`, there is no "Use a different email" or "Send a new code" control. A typo in the email means reloading the page.
- `RequireSession.tsx:18` stores `state={{ from: location }}`, but `Login.tsx:53` always runs `navigate("/")` (grep finds no reader of `state.from`).
- Inputs lack mobile hints. Email (`:100-106`) has no `autoComplete="email"`. The code field (`:75-81`) has no `autoComplete="one-time-code"`, `autoCapitalize="characters"`, `inputMode` or `spellCheck={false}`. The Account code field (`Account.tsx:152-159`) has no `maxLength` and no upper-casing, unlike Login.
- A signed-in user who opens `/login` sees the form again.

**Recommendation.** Add a "Use a different email" link-button and a "Send a new code" button with a cooldown. Navigate to `location.state?.from?.pathname ?? "/"`. Add the autofill attributes. Extract one `<CodeInput>` used by both Login and Account. Redirect `/login` to `/` when `user` is set. Cover these with RTL tests and e2e journey 2.

### FE-13: The iCal URL can only be seen by regenerating it (Medium, S)

**Evidence**
- `Account.tsx:168-193`: the Calendar section shows only a "Regenerate" button, and the URL appears only after calling `POST /api/account/calendar-token` (`api/calendar.ts:4-5`). The backend has no read endpoint (`server.go:79` is the only calendar-token route). Every visit to "get my link" therefore rotates the token and invalidates the feed already subscribed on the resident's phone, with no warning.
- Copy gives no feedback (`:99-106`), and there is no `webcal://` link for one-tap subscription on iOS/Android.

**Recommendation.** Add `GET /account/calendar-token`, which returns the current URL and creates one if none exists (backend). In the UI, show it with "Add to calendar" (`webcal://…`) and "Copy" (with a toast), and move "Regenerate" behind a confirm dialog that explains old links will stop working.

### FE-14: Logout is client-only; 24-hour bearer token in `localStorage`; a dormant cookie path has no CSRF guard (Medium, S)

**Evidence**
- `client.ts:1, 24-34` stores the session token in `localStorage`. `SessionContext.tsx:67-70`: `logout()` only clears it locally. There is no logout or revoke route (`server.go:46-82`), although sessions have a `revoked_at` column (`auth/projection.go:183`). The TTL is 24 hours (`auth/service.go:16`).
- The backend also accepts a `session` cookie (`product/backend/internal/auth/middleware.go:66`). The SPA never sets it, and the POST endpoints have no CSRF or Origin checks. Today the bearer-header design makes CSRF moot.

**Why it matters.** On a shared family tablet, "Log out" does not end the session server-side, and any XSS can exfiltrate a token valid for 24 hours (no CSP, FE-11). If someone later "simplifies" auth to cookies, the cookie path is CSRF-able.

**Recommendation.** Add `POST /auth/logout`, which revokes the presented token, and call it from `logout()` with fire-and-forget plus a local clear. Either remove the cookie branch from `extractToken`, or document it as requiring `SameSite=Strict`, `HttpOnly` and an Origin check. Keep the bearer model for now, but add the CSP from FE-11.

### FE-15: Test suite: change-detector theme tests, UTC-pinned dates, no lint, no a11y checks (Medium, S)

**Evidence**
- `src/theme.test.ts` (236 lines) mostly re-asserts hex constants that are copied from `theme.ts` (`:43-55, 58-86`). Any intentional palette change needs two edits, and it catches no behaviour.
- `tests.setup.ts:7` pins `TZ=UTC` (FE-08). The `Calendar.test.tsx:22-24` fixture creates zero-length bookings (`end: start`).
- The `Users.test.tsx` select tests always pick an option first (FE-03).
- Missing tests: SessionContext restore failure (network vs 401), 401 mid-session, `App` routing/redirects, `Login` deep-link return, the Account Regenerate/Copy flow (mocked at `Account.test.tsx:17` but never exercised), and the Users add-user/block/broadcast forms (only tested at the API-module level).
- `package.json` has no ESLint at all (no `react-hooks/exhaustive-deps`, no `jsx-a11y`), and CI (`frontend-ci.yml:39-43`) runs only test and build, with no coverage report.

**Recommendation.** Cut `theme.test.ts` down to behavioural checks: the Button default variant renders with the accent token, Input height is 44 px, and the light-only config (FE-04). Add the missing tests listed above. Add `eslint` + `typescript-eslint` + `eslint-plugin-react-hooks` + `eslint-plugin-jsx-a11y` and an `npm run lint` CI step. Add `vitest --coverage` with a modest floor so builder models can't add untested pages. Run part of the suite under a non-UTC `TZ`.

### FE-16: Routing and app structure (Low, S)

**Evidence**
- `App.tsx:13-42` repeats `<RequireSession><AppShell>…</AppShell></RequireSession>` for every route.
- `RequireSession.tsx:14-16` renders `null` while restoring, which shows a blank screen on slow networks.
- There is no error boundary, so any render exception white-screens the app. `BrowserRouter` (declarative mode) cannot use RR7 `errorElement`.

**Why it matters.** #120 needs shell-level state (from GitHub issue) (drawer, CTA, search `?q=`) shared across pages. A layout route is the natural home for it.

**Recommendation.**
```tsx
<Route element={<RequireSession><AppShell /></RequireSession>}>  {/* AppShell renders <Outlet/> */}
  <Route index element={<Calendar />} />
  <Route path="account" element={<Account />} />
  <Route path="users" element={<Users />} />
</Route>
```
Show a centered `Spinner` while `loading`. Wrap the shell in a small `ErrorBoundary` with a "Reload" button, or move to `createBrowserRouter` with `errorElement`. Do this as a prep PR before #120.

### FE-17: Dead code and multi-model drift (Low, S)

**Evidence**
- **Unused re-export shims.** `pages/AccountPage.tsx`, `pages/SuperUser.tsx` and `pages/UserDirectory.tsx` are one-line re-exports added in `4ef24c5`, and nothing imports them.
- **Unused aliases.** `getMe` (`api/auth.ts:43-44`, "plan naming"), `updateUserRole`, `setUserRole` and `changeAddress` (`api/users.ts:58-63`) are never imported.
- **Misplaced types and misleading comments.** `Booking` is defined in `api/auth.ts:13-22` rather than `bookings.ts`. `RawUser`'s comment claims dual key styles, but nothing normalizes them (`users.ts:4-11`).
- **Signs of several models writing.** There are three different code-input behaviours (Login upper-cases with maxLength 6, Account does neither). Some tests use `userEvent.setup()` and others call `userEvent.*` directly. `AppShell.test.tsx:34, 69` has misindented lines. Pages render `main` inside the shell's `main`. Colours are hardcoded (`gray.600`, `gray.50`, `colorScheme="red"`) right next to the new semantic tokens (`AppShell.tsx:46, 97`; `Calendar.tsx:143`).
- **Wrong README.** `product/frontend-solid/README.md` says deployments extend the theme from `projects/<name>/`, but no such mechanism exists (`main.tsx:7` imports `./theme` directly, and `projects/sauna` has no theme). Its example `extendTheme({ colors: … }, ...baseTheme)` would let the base override the deployment colours. The sidecar's chrome strings ("Sauna booking system" / "Homeowner association sauna", `sidecar/.../server.go:203-204`) also differ from the mockup branding that #120 expects (from GitHub issue).

**Recommendation.** Delete the shims and aliases, move `Booking` to `api/bookings.ts`, fix the README (or implement a `projects/sauna/frontend/theme.ts` override with a build-time alias), and add a short `product/frontend-solid/AGENTS.md` with conventions: one test style, tokens instead of `gray.*`/hex values, no alias exports, a single `main`. Cheaper models follow local conventions far better than repo-wide prose.

### FE-18: Dependency hygiene (Low, S)

**Evidence**
- **Behind on majors.** The lockfile resolves `vite` 5.4.21, `vitest` 2.1.9 and `esbuild` 0.21.5, two majors behind the current Vite/Vitest lines. esbuild below 0.25 carries the dev-server CORS advisory (GHSA-67mh-4wv8-2f99); it is dev-only but flagged by scanners.
- **Unexplained override.** `package.json:34-36` forces `tinypool` to `^2.2.0`, while vitest 2.1.9 declares `tinypool ^1.0.1` (lockfile). This came in with the initial scaffold `ef01a88` without a reason.
- **Type mismatch.** `@types/node` ^26 while Docker and CI run Node 22 (`Dockerfile:6`, `frontend-ci.yml:32`).
- **Pinned and unwatched.** `@playwright/test` is pinned at 1.49.0 (`dev-ops/testing/package.json:7`). There is no `.github/dependabot.yml`.
- **Chakra UI** v2 (2.10.10) is in maintenance, and v3 is a breaking rewrite (no `extendTheme`, different recipes and APIs). The whole redesign (#120–#123) and `theme.ts` are written against v2.

**Recommendation.** Decide explicitly to stay on Chakra v2 through the redesign. Pin `~2.10` and note it in the README so a builder model doesn't "upgrade" mid-issue. Upgrade Vite/Vitest together in one PR (removing the `tinypool` override), align `@types/node` with `22.x`, and add Dependabot for `/product/frontend-solid` and `/dev-ops/testing` (npm), grouped minor/patch, so the existing Dependabot PR flow covers the frontend. `framer-motion`, Emotion and React 18 are the correct peers for Chakra v2 and are not unnecessary.

## Prioritized roadmap

**Now (before the factory picks up #120–#123)**
1. FE-01: keep the token on non-401 errors and add central 401 handling (S).
2. FE-03 and FE-04: fix the default-select bug and force light mode (S each, with tests).
3. FE-02: confirm dialog + busy state + toasts for cancel, remove and broadcast (M). This closes the spec gap in alternative flow step 10.
4. FE-05: re-plan #120–#123 (from GitHub issue) on current `main`, record the owner decisions (member label, notifications/search scope, Quick-book semantics, `from=now`), and sequence them behind a prep PR.
5. FE-06 (part 1): fix `login.spec.ts` so the code is fetched after the UI request, and update its heading assertion together with #121.

**Next (alongside the redesign)**
1. Prep PR: FE-16 (layout route + error boundary) + FE-17 (delete dead code, `product/frontend-solid/AGENTS.md`) + ESLint from FE-15.
2. FE-08: `src/lib/datetime.ts` with the deployment time zone from `/api/chrome`, friendly error mapping, and an i18n decision.
3. FE-09: TanStack Query (or a shared hook) so #121/#122 build on one data layer.
4. FE-10 and FE-12: landmark, title and focus fixes, 44 px targets, login back/resend, deep-link return and OTP attributes.
5. FE-11: Caddy cache headers, compression and CSP; stop deleting live assets on deploy.
6. FE-06 (part 2): Mailpit, seeded users, the journeys 1–6 and 13 in CI, plus mobile projects and axe.

**Later**
1. FE-07: a real booking interaction (slot/duration picker, availability, blocked periods, owner on rows) as its own owner-approved issue with mockups for the creation flow.
2. FE-13 and FE-14: calendar-token read endpoint and webcal link; server-side logout and a decision on the cookie path.
3. FE-15 and FE-18: trim the theme tests, coverage floor, non-UTC test run, Vite/Vitest upgrade and Dependabot; revisit Chakra v3 only after the redesign has shipped.
4. Remaining e2e journeys 7–12 and 14.

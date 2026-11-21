# Solid migration baseline and parity checklist

Issue: [#329 - Solid 2.0 migration 01: Record the React baseline and write the parity checklist](https://github.com/adamzki99/booking-system/issues/329)

This document records the React frontend baseline as observed in `product/frontend` and defines the user-visible parity checklist for the Solid migration.

## Baseline results

Environment:
- Working directory: `product/frontend` (run inside worktree branch `issue/329-solid-migration-baseline` at commit `8f59983`)
- Node: `v26.8.1`
- npm: `12.1.0`

### `npm ci`

- Result: **PASS** (exit code `0`)
- Notable output:
  - `added 259 packages, and audited 260 packages in 3s`
  - `5 vulnerabilities (3 moderate, 1 high, 1 critical)` with `npm audit` suggested
  - `npm warn deprecated whatwg-encoding@3.1.1: Use @exodus/bytes instead for a more spec-conformant and faster implementation`
  - `npm warn install-scripts 1 package had install scripts blocked because they are not covered by allowScripts: esbuild@0.21.5 (postinstall: node install.js)`

### `npm test` (`vitest run`)

- Result: **FAIL** (exit code `1`)
- Summary: `Test Files 2 failed | 12 passed (14)`, `Tests 11 failed | 81 passed (92)`
- Duration: `14.75s`
- Notable output:
  - Repeated Node warning: `ExperimentalWarning: localStorage is not available because --localstorage-file was not provided.`
  - Failing suites/tests (all with `TypeError: Cannot read properties of undefined (reading 'clear')` from `localStorage.clear()` in `beforeEach`):
    - `src/api/client.test.ts` (6 failed): `sends GET requests and parses JSON responses`, `attaches the stored bearer token`, `posts JSON bodies with a content-type header`, `throws an ApiError carrying the backend error message`, `falls back to the status text when the body is not JSON`, `patches JSON bodies with a content-type header`
    - `src/auth/SessionContext.test.tsx` (5 failed): `starts signed out when no token is stored`, `restores the session from a stored token`, `logs in: verifies the code, stores the token and loads the user`, `logs out by clearing the token and the user`, `refresh reloads the signed-in user`
  - Passing areas included theme, AppShell, Account, Users, users API, Calendar, Login, auth/bookings/calendar/broadcast API tests, and RequireSession tests (81 tests total passing).

### `npm run build` (`tsc --noEmit && vite build`)

- Result: **PASS** (exit code `0`)
- Notable output:
  - `vite v5.4.21 building for production...`
  - `✓ 1048 modules transformed.`
  - `dist/index.html 0.39 kB │ gzip: 0.26 kB`
  - `dist/assets/index-B3LPTY_w.css 0.03 kB │ gzip: 0.05 kB`
  - `dist/assets/index-Bkj1XKBh.js 549.89 kB │ gzip: 179.34 kB`
  - Vite warning: chunk larger than 500 kB after minification (`(!) Some chunks are larger than 500 kB ...`)
  - `✓ built in 5.22s`

## Environment and build assumptions

### Scripts (`product/frontend/package.json`)

- `dev`: `vite`
- `build`: `tsc --noEmit && vite build`
- `test`: `vitest run`
- `preview`: `vite preview`

No separate lint or typecheck script is defined; type checking runs as part of `build`.

### Vite dev proxy and SPA behavior (`vite.config.ts`, `index.html`)

- The SPA always talks to `/api/...`.
- In development, Vite proxies `/api` to `http://localhost:8080` with `changeOrigin: true` and rewrites the path by stripping the `/api` prefix (`rewrite: (path) => path.replace(/^\/api/, "")`), matching production `handle_path /api/*` behavior in Caddy.
- The app is an SPA: `index.html` mounts at `<div id="root"></div>` and loads `/src/main.tsx`; client routing is handled by React Router (`BrowserRouter` in `main.tsx`).

### Routes and page mapping (`src/App.tsx`)

- `/login` -> `src/pages/Login.tsx`
- `/` -> `src/pages/Calendar.tsx` (protected by `RequireSession`, wrapped in `AppShell`)
- `/account` -> `src/pages/Account.tsx` (protected by `RequireSession`, wrapped in `AppShell`)
- `/users` -> `src/pages/Users.tsx` (protected by `RequireSession`, wrapped in `AppShell`)
- Any other path (`*`) -> redirects to `/` with `replace`

### Token storage and session flow (`src/api/client.ts`, `src/auth/SessionContext.tsx`, `src/RequireSession.tsx`, `src/api/auth.ts`)

- Session token storage: browser `localStorage` key `booking.session-token` (`TOKEN_KEY`).
  - `getToken()` reads the token (returns `null` if unavailable).
  - `setToken(token)` stores or removes the token (storage failures are ignored so the session is simply not persisted).
- API requests (`request/get/post/patch` in `src/api/client.ts`) send `Authorization: Bearer <token>` when a token is present, serialize non-string request bodies as JSON with `Content-Type: application/json`, parse JSON responses (treating empty/204/non-JSON bodies as `undefined` where applicable), and throw `ApiError` with backend `error` message or status text on non-OK responses.
- Auth/session endpoints used by the frontend: `GET /api/auth/config`, `POST /api/auth/request-code`, `POST /api/auth/verify`, `POST /api/auth/qa-login`, `GET /api/users/me` (current user).
- `SessionProvider` initializes `loading` to `true` only when a stored token exists. On mount, if a token exists it validates it via `currentUser()`; success sets `user`, failure clears the token and leaves the user signed out, and loading ends in both cases. If no token exists, loading is `false`.
- `login(email, code)` verifies credentials, stores the returned token, then loads and sets the current user.
- `loginWithQAMode(email)` performs QA login, stores the returned token, then loads and sets the current user.
- `refresh()` reloads the current user when a token exists and updates session state.
- `logout()` clears the stored token and user.
- `RequireSession` renders nothing while `loading` is true (avoids flashing login on reload), redirects unauthenticated users to `/login` with `state={{ from: location }}` and `replace`, and renders children for authenticated users.

## Parity checklist

### Route, session, and shell behaviors

- [ ] Unauthenticated visits to protected routes (`/`, `/account`, `/users`) redirect to `/login` (replace) and preserve the attempted location in navigation state.
- [ ] While a stored session token is being validated on load, protected routes render nothing instead of flashing the login page.
- [ ] Invalid or expired stored tokens are cleared and treated as signed out.
- [ ] Unknown routes redirect to `/` (replace); unauthenticated users are then sent to `/login`.
- [ ] Authenticated protected pages render inside `AppShell` with page content in the main area.
- [ ] App shell loads chrome info on mount (`getChrome`) and displays header/footer branding with graceful fallback to empty values on failure.
- [ ] Desktop sidebar shows brand lockup, "Create booking" button, Pages navigation (Bookings `/`, Members `/users`, Account `/account`) with active-state styling, and member footer.
- [ ] Member footer shows signed-in user avatar initials, email (or "Not signed in" fallback), role label (`Member`, `Super user`, `Admin`, or "Signed out"), and a "Log out" button.
- [ ] "Log out" clears the session and navigates to `/login` (replace).
- [ ] "Create booking" in the desktop sidebar, mobile drawer, and mobile bottom dock navigates to `/?create=1` (and closes the mobile drawer when used there).
- [ ] Desktop top bar includes a member-search form that submits to `/users` or `/users?q=<trimmed query>`.
- [ ] Mobile top bar includes menu and member-search icon actions; search icon navigates to `/users` or `/users?q=<trimmed query>`.
- [ ] Redeploy indicator shows a countdown derived from chrome `nextRedeploy` when valid (updates periodically, shows "Next redeploy due now" / "Next redeploy in <1m>" / day-hour-minute forms) with full target time in `title`, and is hidden when unavailable/invalid.
- [ ] Mobile slide-over menu opens from the menu button, can be closed via the close button or navigation link clicks, and displays brand lockup, "Create booking", Pages navigation, and member footer.
- [ ] Notifications icon button is present in the top bar (visual/action affordance shown in shell).

### Login page (`/login`)

- [x] Displays the booking mark, "Booking" heading, and mode/step-appropriate description.
- [x] On mount, fetches auth config to determine QA mode and falls back to non-QA behavior if config loading fails.
- [x] QA mode: shows email form with "Sign in" button; button is disabled without email and shows loading while busy; successful QA sign-in navigates to `/` (replace).
- [x] Non-QA initial step: shows email form with "Request code" button; button is disabled without email and shows loading while busy.
- [x] Requesting a code sends the entered email and transitions to the code-entry step on success.
- [x] Code-entry step shows confirmation text including the destination email and 10-minute validity, an uppercased 6-character code input, and a "Sign in" button disabled until the code length is 6.
- [x] Successful code sign-in navigates to `/` (replace).
- [x] Sign-in/request-code failures are shown in an error alert with a user-displayable message.
- [x] Relevant inputs receive focus automatically for the active step/mode.

### Calendar page (`/`)

- [ ] Shows "Bookings" heading and the current date formatted for the page.
- [ ] Loads bookings on mount (sorted by start time) and best-effort loads users for member labels.
- [ ] Quick book: lets the user choose a source booking to repeat (defaulting to the first available booking), disables controls and shows placeholder messaging when there are no bookings.
- [ ] Quick book: offers repeat targets for 1-4 weeks with day labels, shows a summary of the new booking when a source and target week are selected, and creates the repeated booking on "Quick book" then refreshes the list.
- [ ] Create booking form provides start/end datetime-local inputs, enables submission only when both are set, creates a booking on submit, clears inputs, and refreshes bookings.
- [ ] When the page is opened with `?create=1`, focus moves to the booking start input.
- [ ] Upcoming bookings shows an error alert on load/create/cancel/quick-book failures.
- [ ] Upcoming bookings shows "No bookings yet." when there are no bookings and no error.
- [ ] Upcoming bookings lists bookings (first 5 by default) with member avatar/label (member address or "Member"), formatted day label, and formatted time range.
- [ ] "View all bookings" / "Show fewer bookings" toggles visibility when more than 5 bookings exist.
- [ ] Cancel action is shown only for bookings the current user may cancel (own booking, or super/admin for any booking) and removing a booking refreshes the list.

### Account page (`/account`)

- [x] Shows page header "Account" with subtitle "Update your email address and manage your calendar feed."
- [x] Loads the current user on mount (falling back to the session user if the request fails) and displays the current email.
- [x] Email change request form allows entering a new email and submitting "Send verification code"; on success it enters a pending-confirmation state.
- [x] Pending confirmation state explains that a verification code was sent to the pending email and that the address changes only after confirmation (old address no longer signs in), then allows entering and confirming the code.
- [x] Confirming the email change updates the displayed email, clears pending/code state, and refreshes the session so it matches the new identity.
- [x] Calendar section "Regenerate" action fetches and displays a regenerated iCal URL.
- [x] When an iCal URL is present, "Copy" copies it to the clipboard.
- [x] Failures in account actions are shown in an error alert.

### Users page (`/users`)

- [ ] Shows page header "User directory" with subtitle "Search, review and manage the members of your booking system."
- [ ] Loads and displays the user directory on mount; API failures are shown in an error alert.
- [ ] "Search members" input is driven by the `q` URL query parameter (trimmed, updated with replace navigation) and filters visible member rows by email, address, or role (case-insensitive).
- [ ] Member directory table shows each visible member's avatar/initials, email, role badge, address, and active status.
- [ ] Management controls are shown only to super/admin users; basic users see the directory without management forms.
- [ ] Super/admin users can add a user (email and address), after which the form clears and the directory refreshes.
- [ ] Super/admin users can change a basic user's address by selecting from the full user list (not narrowed by search filtering), after which the form clears and the directory refreshes.
- [ ] Super/admin users can block a time period by submitting start/end values.
- [ ] Super/admin users can broadcast a message (subject and body), after which the form clears.
- [ ] Admin users additionally see "Change role (admin)" and can change another user's role (basic/super/admin), excluding themselves from the selector; the directory refreshes after success.
- [ ] Eligible directory rows show a "Remove" action for super/admin users according to role rules (super: basic users; admin: basic or super users), and removal refreshes the directory.
- [ ] Management form selects continue to use the complete users list so options remain available while a search filter is applied to table rows.

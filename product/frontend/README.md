# Frontend (React)

The booking platform SPA, served behind Caddy.

## Features

- Email + code login.
- Booking calendar: create, view, and cancel own bookings.
- iCal export link for the booking calendar.
- User directory (all users can see registered users).
- Account page: change the email connected to the account.
- Super-user tooling: manage users, cancel any booking, block time periods,
  broadcast messages to all basic users.

## Stack

- **React 18** + **TypeScript**
- **Vite** for dev/build
- **React Router** for routing
- **[Chakra UI v2](https://chakra-ui.com/)** for components, layout, and styling

## Chakra UI

[Chakra UI](https://chakra-ui.com/) is the default component/styling library.
Prefer composing Chakra primitives over writing bespoke CSS. Reach for custom
CSS only when a Chakra primitive genuinely cannot express the design
(accessibility, missing capability, or performance); document the reason in the
PR.

## Supplied mockups and visual alignment

When UI mockups or design references are supplied for a flow, treat them as the
visual source of truth for layout, hierarchy, spacing, coloring, typography,
radii, component states, and responsive behavior. Implement them using the fixed
stack (**React 18, TypeScript, Vite, React Router, Chakra UI v2**) and prefer
Chakra primitives, theme tokens, semantic tokens, and component recipes in
`src/theme.ts` over ad-hoc styles.

- **Sauna (normal user) mockups:** `../../projects/sauna/docs/mocks/sauna_booking_website_normal_user_mock_desktop.html`
  and `../../projects/sauna/docs/mocks/sauna_booking_website_normal_user_mock_mobile.html`.
  These bundled reference artifacts show the intended sauna UI direction:
  - **Brand/context:** "Stennäsets byförening" / "Bastubokning", signed-in member
    context (for example Alex Morgan, Member).
  - **Desktop shell:** left drawer with brand, primary "Create booking" action,
    navigation, and member block; top bar with member search and notifications;
    main "Bookings" view with date heading.
  - **Bookings content:** "Quick book" (repeat an existing booking on the same
    day/time in another week, with booking selection, repeat-on choices, action,
    and summary state) and "Upcoming bookings" (member, date/time, per-row
    actions, and view-all affordance).
  - **Mobile:** bookings screen and menu-open state with the same warm visual
    language and core actions.
  - **Visual language:** warm neutral surfaces, accent red (`#9A2F22` / hover
    `#7A241A` / tint `#F6E6E0`), Inter typography, rounded cards/controls, and
    ~44px interactive control heights.

Use these references to guide sauna-facing UI and to inform reusable generic
tokens/recipes in `src/theme.ts` when a pattern is broadly useful. Keep
deployment-specific branding, copy, and assets in `projects/<name>/` rather than
hardcoding them into the generic product. If a mockup is ambiguous or cannot be
fully inspected from a bundled artifact, state what was inferred and confirm
with the relevant deployment docs or reviewer.

### Foundation

- `src/theme.ts`: base theme with generic tokens (colors, spacing, typography,
  radii, component defaults). Deployment-specific branding does NOT live here;
  deployments extend this theme from `projects/<name>/`.
- `src/main.tsx`: wraps the app in `<ChakraProvider theme={theme}>`.

### Design tokens

The base theme encodes the warm design language from the reference mockups in
deployment-agnostic terms. Prefer these tokens over hardcoded hex values.

Brand scale (`theme.colors.brand`, `50`–`900`):

| Token        | Value     | Use                              |
| ------------ | --------- | -------------------------------- |
| `brand.100`  | `#F6E6E0` | Accent tint / selected surfaces  |
| `brand.500`  | `#9A2F22` | Primary accent                   |
| `brand.600`  | `#7A241A` | Accent hover / emphasis          |

Warm neutrals (`theme.colors.warm`): `ink` `#2B1D1A`, `muted` `#5E4B45`,
`placeholder` `#7A6A63`, `line` `#E9DDD5`, `canvas` `#FAF6F1`, `subtle`
`#FBF8F4`, `hover` `#F5EEE8`, `surface` `#FFFFFF`, `avatarBg` `#EFE3D6`,
`avatarFg` `#5B4331`.

Semantic tokens (`theme.semanticTokens.colors`) map the same values to roles so
components and pages can reference intent rather than color: `accent`,
`accentHover`, `accentTint`, `ink`, `muted`, `line`, `bgCanvas`, `bgSubtle`,
`bgHover`, `avatarBg`, `avatarFg`.

Other foundations:

- Fonts: `theme.fonts.heading` and `theme.fonts.body` are
  `"Inter", system-ui, -apple-system, "Segoe UI", sans-serif`.
- Radii: `sm` `10px` (nav items, small badges), `md` `12px` (buttons, inputs,
  selects, chips), `lg`/`card` `16px` (cards).
- Global styles: body uses `bgCanvas` background and `ink` text.

### Component recipes

The theme ships component defaults so pages get the mockup styling without
bespoke CSS:

- **Button**: default `variant="accent"` (solid `accent` with `accentHover`
  hover), `variant="accentOutline"` (accent border, tint on hover), and
  `variant="icon"` (44px square toolbar button). Sizes `md` (44px) and `lg`
  (48px); 12px radius. `colorScheme="brand"` remains available for Chakra's
  built-in variants.
- **Card**: white surface with a `1px` `line` border and `16px` radius.
- **Input**, **Select**, **Textarea**: `44px` control height (`md`), `line`
  border, `accent` focus border with an `accentTint` ring, and muted
  placeholders.
- **Avatar**: `avatarBg` background with `avatarFg` initials.

Adding bespoke component CSS to `src/index.css` is intentionally avoided; use
these recipes or add tokens/variants in `src/theme.ts` instead.

### Using Chakra components

```tsx
import { Box, Button, Heading, VStack } from "@chakra-ui/react";

export default function Example() {
  return (
    <Box>
      <Heading size="md">Title</Heading>
      <VStack spacing={4}>
        <Button>Click me</Button>
      </VStack>
    </Box>
  );
}
```

Common primitives:

- **Layout:** `Box`, `Flex`, `Grid`, `Stack` (`HStack`, `VStack`), `Container`,
  `SimpleGrid`, `Wrap`.
- **Typography:** `Heading`, `Text`, `Code`.
- **Forms:** `FormControl`, `FormLabel`, `Input`, `Select`, `Textarea`,
  `Checkbox`, `Radio`, `Switch`.
- **Feedback:** `Alert`, `Spinner`, `Progress`, `Skeleton`.
- **Overlays:** `Modal`, `Drawer`, `Popover`, `Tooltip`.
- **Navigation:** `Menu`, `Tabs`, `Breadcrumb`, `Link`.
- **Data display:** `Table`, `List`, `Badge`, `Tag`, `Card`.

### Testing

Use the provider-aware render helper in `src/test-utils.tsx` so Chakra context
hooks resolve during tests:

```tsx
import { render, screen } from "../test-utils";
// render() wraps the UI in <ChakraProvider> automatically.
```

### Theming for deployments

Deployments can extend the base theme:

```tsx
import { extendTheme } from "@chakra-ui/react";
import baseTheme from "booking-frontend/theme"; // or import from product/

const saunaTheme = extendTheme({
  colors: { brand: { 500: "#0d6efd" } },
  ...baseTheme,
});
```

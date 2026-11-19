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

### Foundation

- `src/theme.ts` — base theme with generic tokens (colors, spacing, typography,
  radii, component defaults). Deployment-specific branding does NOT live here;
  deployments extend this theme from `projects/<name>/`.
- `src/main.tsx` — wraps the app in `<ChakraProvider theme={theme}>`.

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

- **Button** — default `variant="accent"` (solid `accent` with `accentHover`
  hover), `variant="accentOutline"` (accent border, tint on hover), and
  `variant="icon"` (44px square toolbar button). Sizes `md` (44px) and `lg`
  (48px); 12px radius. `colorScheme="brand"` remains available for Chakra's
  built-in variants.
- **Card** — white surface with a `1px` `line` border and `16px` radius.
- **Input**, **Select**, **Textarea** — `44px` control height (`md`), `line`
  border, `accent` focus border with an `accentTint` ring, and muted
  placeholders.
- **Avatar** — `avatarBg` background with `avatarFg` initials.

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

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

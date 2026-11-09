import { extendTheme, type ThemeConfig } from "@chakra-ui/react";

/**
 * Base theme for the generic booking frontend.
 *
 * Deployment-specific branding (colors, logos, fonts) should NOT live here.
 * Deployments can wrap `ChakraProvider` with their own theme that extends this
 * one from `projects/<name>/`.
 */
const config: ThemeConfig = {
  initialColorMode: "system",
  useSystemColorMode: true,
};

const theme = extendTheme({
  config,
  fonts: {
    heading: `system-ui, -apple-system, "Segoe UI", sans-serif`,
    body: `system-ui, -apple-system, "Segoe UI", sans-serif`,
  },
  radii: {
    base: "0.375rem",
    card: "0.5rem",
  },
  components: {
    Button: {
      defaultProps: { colorScheme: "blue" },
    },
    Alert: {
      defaultProps: { variant: "left-accent" },
    },
  },
});

export default theme;

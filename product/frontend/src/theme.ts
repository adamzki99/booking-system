import { extendTheme, type ThemeConfig } from "@chakra-ui/react";

/**
 * Base theme for the generic booking frontend.
 *
 * The palette and component recipes here encode the warm design language from
 * the reference mockups in generic, deployment-agnostic terms (a `brand` scale
 * plus semantic surface/ink tokens). Deployment-specific branding (organization
 * names, logos, overridden colors) does NOT live here; deployments extend this
 * theme from `projects/<name>/`.
 */

/** Raw hex values shared by the palette and the semantic tokens. */
const palette = {
  accent: "#9A2F22",
  accentHover: "#7A241A",
  accentTint: "#F6E6E0",
  ink: "#2B1D1A",
  muted: "#5E4B45",
  placeholder: "#7A6A63",
  line: "#E9DDD5",
  bgCanvas: "#FAF6F1",
  bgSubtle: "#FBF8F4",
  bgHover: "#F5EEE8",
  surface: "#FFFFFF",
  avatarBg: "#EFE3D6",
  avatarFg: "#5B4331",
} as const;

const fonts = {
  heading: `"Inter", system-ui, -apple-system, "Segoe UI", sans-serif`,
  body: `"Inter", system-ui, -apple-system, "Segoe UI", sans-serif`,
};

/** Focus ring shared by form controls: accent border plus a tint halo. */
const fieldFocusVisible = {
  borderColor: "accent",
  boxShadow: `0 0 0 2px ${palette.accentTint}`,
};

const config: ThemeConfig = {
  initialColorMode: "system",
  useSystemColorMode: true,
};

const theme = extendTheme({
  config,
  colors: {
    brand: {
      50: "#FDF6F4",
      100: palette.accentTint,
      200: "#EDCFC5",
      300: "#DFAF9F",
      400: "#C56F5C",
      500: palette.accent,
      600: palette.accentHover,
      700: "#5E1B14",
      800: "#42130F",
      900: "#2B0C09",
    },
    warm: {
      ink: palette.ink,
      muted: palette.muted,
      placeholder: palette.placeholder,
      line: palette.line,
      canvas: palette.bgCanvas,
      subtle: palette.bgSubtle,
      hover: palette.bgHover,
      surface: palette.surface,
      avatarBg: palette.avatarBg,
      avatarFg: palette.avatarFg,
    },
  },
  semanticTokens: {
    colors: {
      accent: { default: palette.accent },
      accentHover: { default: palette.accentHover },
      accentTint: { default: palette.accentTint },
      ink: { default: palette.ink },
      muted: { default: palette.muted },
      line: { default: palette.line },
      bgCanvas: { default: palette.bgCanvas },
      bgSubtle: { default: palette.bgSubtle },
      bgHover: { default: palette.bgHover },
      avatarBg: { default: palette.avatarBg },
      avatarFg: { default: palette.avatarFg },
    },
  },
  fonts,
  radii: {
    base: "0.375rem",
    // Mockup radii: nav/small badges, controls, cards.
    sm: "10px",
    md: "12px",
    lg: "16px",
    card: "16px",
  },
  styles: {
    global: {
      body: {
        bg: "bgCanvas",
        color: "ink",
        fontFamily: "body",
      },
    },
  },
  components: {
    Button: {
      baseStyle: {
        borderRadius: "md",
        fontWeight: 600,
      },
      sizes: {
        sm: { h: "36px", minW: "36px", px: 3, fontSize: "sm" },
        md: { h: "44px", minW: "44px", px: 4, fontSize: "md" },
        lg: { h: "48px", minW: "48px", px: 6, fontSize: "md" },
      },
      variants: {
        // Primary action: solid accent with a darker hover.
        accent: {
          bg: "accent",
          color: "white",
          _hover: { bg: "accentHover", _disabled: { bg: "accent" } },
          _active: { bg: "accentHover" },
        },
        // Secondary action: outlined accent that tints on hover.
        accentOutline: {
          bg: "white",
          border: "1px solid",
          borderColor: "accent",
          color: "accentHover",
          _hover: { bg: "accentTint" },
          _active: { bg: "accentTint" },
        },
        // Square icon button used for toolbar actions.
        icon: {
          w: "44px",
          minW: "44px",
          p: 0,
          bg: "white",
          border: "1px solid",
          borderColor: "line",
          color: "muted",
          _hover: { bg: "bgHover", color: "ink" },
        },
      },
      defaultProps: { variant: "accent", size: "md", colorScheme: "brand" },
    },
    Card: {
      baseStyle: {
        container: {
          // Drive the surface through Card's own CSS variable so dark-mode
          // aware deployments can still override it.
          "--card-bg": "white",
          borderWidth: "1px",
          borderColor: "line",
          borderRadius: "lg",
          boxShadow: "none",
        },
      },
      defaultProps: { variant: "elevated" },
    },
    Input: {
      sizes: {
        md: { field: { "--input-height": "44px", "--input-padding": "space.3" } },
        lg: { field: { "--input-height": "48px", "--input-padding": "space.4" } },
      },
      variants: {
        outline: {
          field: {
            bg: "white",
            borderColor: "line",
            color: "ink",
            _placeholder: { color: "warm.placeholder" },
            _hover: { borderColor: "line" },
            _focusVisible: fieldFocusVisible,
          },
        },
      },
      defaultProps: { variant: "outline", size: "md" },
    },
    Select: {
      baseStyle: {
        icon: { color: "muted" },
      },
      sizes: {
        md: { field: { "--input-height": "44px", "--input-padding": "space.3" } },
        lg: { field: { "--input-height": "48px", "--input-padding": "space.4" } },
      },
      variants: {
        outline: {
          field: {
            bg: "white",
            borderColor: "line",
            color: "ink",
            _placeholder: { color: "warm.placeholder" },
            _hover: { borderColor: "line" },
            _focusVisible: fieldFocusVisible,
          },
        },
      },
      defaultProps: { variant: "outline", size: "md" },
    },
    Textarea: {
      baseStyle: {
        bg: "white",
        color: "ink",
        height: "auto",
        minHeight: "96px",
        paddingY: 3,
      },
      variants: {
        outline: {
          bg: "white",
          borderColor: "line",
          _placeholder: { color: "warm.placeholder" },
          _hover: { borderColor: "line" },
          _focusVisible: fieldFocusVisible,
        },
      },
      defaultProps: { variant: "outline", size: "md" },
    },
    Avatar: {
      baseStyle: {
        container: { bg: "avatarBg", color: "avatarFg" },
        excessLabel: { bg: "avatarBg", color: "avatarFg" },
        label: { color: "avatarFg", fontWeight: 600 },
      },
      defaultProps: { size: "md" },
    },
    Alert: {
      defaultProps: { variant: "left-accent" },
    },
  },
});

export default theme;

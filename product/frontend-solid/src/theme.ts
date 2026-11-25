/**
 * Base theme tokens for the generic booking frontend (Solid).
 *
 * These values preserve the warm design language in generic,
 * deployment-agnostic terms. CSS custom properties in
 * `styles/tokens.css` expose the same palette for runtime styling; this module
 * provides a typed source of truth for components and tests.
 */

export const palette = {
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

export const brand = {
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
} as const;

export const fonts = {
  heading: `"Inter", system-ui, -apple-system, "Segoe UI", sans-serif`,
  body: `"Inter", system-ui, -apple-system, "Segoe UI", sans-serif`,
} as const;

export const radii = {
  base: "0.375rem",
  sm: "10px",
  md: "12px",
  lg: "16px",
  card: "16px",
} as const;

/** Focus ring shared by form controls: accent border plus a tint halo. */
export const focusRingShadow = `0 0 0 2px ${palette.accentTint}`;

const theme = {
  palette,
  brand,
  fonts,
  radii,
  focusRingShadow,
};

export default theme;

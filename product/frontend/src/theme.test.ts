import {
  Avatar,
  Button,
  Card,
  CardBody,
  Input,
  Select,
  Textarea,
} from "@chakra-ui/react";
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { render, screen } from "./test-utils";
import theme from "./theme";

/**
 * Chakra resolves multi-part variant/multi-style configs to functions when the
 * base theme defines them that way (Input, Select, Textarea, Avatar). Resolve
 * them with a minimal prop bag so tests can assert on concrete style values.
 */
type StyleResolver = (props: {
  theme: typeof theme;
  colorMode: string;
  colorScheme: string;
}) => Record<string, any>;

function resolveVariant(componentName: string, variant: string): Record<string, any> {
  const component = (theme.components as Record<string, any>)[componentName];
  const value = component.variants[variant] as
    | StyleResolver
    | Record<string, any>;
  return typeof value === "function"
    ? value({ theme, colorMode: "light", colorScheme: "gray" })
    : value;
}

function resolveBaseStyle(componentName: string): Record<string, any> {
  const component = (theme.components as Record<string, any>)[componentName];
  return typeof component.baseStyle === "function"
    ? component.baseStyle({ theme, colorMode: "light" })
    : component.baseStyle;
}

const mockupPalette = {
  accent: "#9A2F22",
  accentHover: "#7A241A",
  accentTint: "#F6E6E0",
  ink: "#2B1D1A",
  muted: "#5E4B45",
  line: "#E9DDD5",
  bgCanvas: "#FAF6F1",
  bgSubtle: "#FBF8F4",
  bgHover: "#F5EEE8",
  avatarBg: "#EFE3D6",
  avatarFg: "#5B4331",
};

describe("theme palette", () => {
  it("anchors the brand scale on the mockup accent colors", () => {
    const brand = theme.colors.brand;
    expect(brand[500]).toBe("#9A2F22");
    expect(brand[600]).toBe("#7A241A");
    expect(brand[100]).toBe("#F6E6E0");
  });

  it("exposes the warm neutral palette", () => {
    const warm = theme.colors.warm;
    expect(warm.ink).toBe("#2B1D1A");
    expect(warm.muted).toBe("#5E4B45");
    expect(warm.placeholder).toBe("#7A6A63");
    expect(warm.line).toBe("#E9DDD5");
    expect(warm.canvas).toBe("#FAF6F1");
    expect(warm.subtle).toBe("#FBF8F4");
    expect(warm.hover).toBe("#F5EEE8");
    expect(warm.surface).toBe("#FFFFFF");
    expect(warm.avatarBg).toBe("#EFE3D6");
    expect(warm.avatarFg).toBe("#5B4331");
  });

  it.each(Object.entries(mockupPalette))(
    "defines the '%s' semantic token as %s",
    (name, value) => {
      expect(theme.semanticTokens.colors[name]).toEqual({ default: value });
    },
  );
});

describe("theme foundations", () => {
  it("uses the Inter font stack for headings and body", () => {
    const inter = `"Inter", system-ui, -apple-system, "Segoe UI", sans-serif`;
    expect(theme.fonts.heading).toBe(inter);
    expect(theme.fonts.body).toBe(inter);
  });

  it("defines the mockup border radii", () => {
    expect(theme.radii.sm).toBe("10px");
    expect(theme.radii.md).toBe("12px");
    expect(theme.radii.lg).toBe("16px");
    expect(theme.radii.card).toBe("16px");
  });

  it("applies the warm canvas and ink colors to the global body", () => {
    const body = theme.styles.global.body;
    expect(body.bg).toBe("bgCanvas");
    expect(body.color).toBe("ink");
    expect(body.fontFamily).toBe("body");
  });
});

describe("component recipes", () => {
  it("gives Button an accent primary variant, outline variant, and sizes", () => {
    const button = theme.components.Button;
    expect(button.defaultProps).toMatchObject({
      variant: "accent",
      colorScheme: "brand",
      size: "md",
    });
    expect(button.baseStyle.borderRadius).toBe("md");
    expect(button.baseStyle.fontWeight).toBe(600);
    expect(button.sizes.md.h).toBe("44px");
    expect(button.sizes.lg.h).toBe("48px");

    expect(button.variants.accent).toMatchObject({
      bg: "accent",
      color: "white",
      _hover: { bg: "accentHover" },
    });
    expect(button.variants.accentOutline).toMatchObject({
      borderColor: "accent",
      color: "accentHover",
      _hover: { bg: "accentTint" },
    });
    expect(button.variants.icon).toMatchObject({
      w: "44px",
      borderColor: "line",
      color: "muted",
    });
  });

  it("gives Card a bordered white surface with the card radius", () => {
    const card = theme.components.Card;
    expect(card.defaultProps.variant).toBe("elevated");
    expect(card.baseStyle.container).toMatchObject({
      "--card-bg": "white",
      borderWidth: "1px",
      borderColor: "line",
      borderRadius: "lg",
      boxShadow: "none",
    });
  });

  it("styles Input with the accent focus ring and 44px height", () => {
    const input = theme.components.Input;
    expect(input.defaultProps).toMatchObject({
      variant: "outline",
      size: "md",
    });
    expect(input.sizes.md.field["--input-height"]).toBe("44px");

    const field = resolveVariant("Input", "outline").field;
    expect(field).toMatchObject({
      bg: "white",
      borderColor: "line",
      color: "ink",
      _focusVisible: {
        borderColor: "accent",
        boxShadow: "0 0 0 2px #F6E6E0",
      },
    });
  });

  it("styles Select and Textarea with the shared field treatment", () => {
    const select = theme.components.Select;
    expect(select.defaultProps.variant).toBe("outline");
    expect(select.sizes.md.field["--input-height"]).toBe("44px");

    const selectField = resolveVariant("Select", "outline").field;
    expect(selectField).toMatchObject({
      bg: "white",
      borderColor: "line",
      color: "ink",
      _focusVisible: { borderColor: "accent" },
    });
    expect(resolveBaseStyle("Select").icon.color).toBe("muted");

    const textarea = theme.components.Textarea;
    expect(textarea.defaultProps.variant).toBe("outline");
    expect(textarea.baseStyle.minHeight).toBe("96px");

    const textareaField = resolveVariant("Textarea", "outline");
    expect(textareaField).toMatchObject({
      bg: "white",
      borderColor: "line",
      _focusVisible: { borderColor: "accent" },
    });
  });

  it("styles Avatar with the warm badge colors", () => {
    const avatar = theme.components.Avatar;
    expect(avatar.defaultProps.size).toBe("md");
    const container = resolveBaseStyle("Avatar").container;
    expect(container).toMatchObject({
      bg: "avatarBg",
      color: "avatarFg",
    });
  });
});

describe("component rendering", () => {
  it("renders themed primitives under ChakraProvider", () => {
    render(
      createElement(
        Card,
        null,
        createElement(
          CardBody,
          null,
          createElement(Input, { "aria-label": "Full name", placeholder: "Full name" }),
          createElement(
            Select,
            { "aria-label": "Time slot", defaultValue: "morning" },
            createElement("option", { value: "morning" }, "Morning"),
          ),
          createElement(Textarea, { "aria-label": "Notes", placeholder: "Notes" }),
          createElement(Button, null, "Book"),
          createElement(Avatar, { name: "Ada Lovelace" }),
        ),
      ),
    );

    expect(screen.getByRole("button", { name: "Book" })).toBeInTheDocument();
    expect(screen.getByLabelText("Full name")).toBeInTheDocument();
    expect(screen.getByLabelText("Time slot")).toBeInTheDocument();
    expect(screen.getByLabelText("Notes")).toBeInTheDocument();
    expect(screen.getByText("AL")).toBeInTheDocument();
  });
});

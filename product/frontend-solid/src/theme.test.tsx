import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { render, screen } from "./test-utils";
import Alert from "./ui/Alert";
import Avatar from "./ui/Avatar";
import Button from "./ui/Button";
import Card from "./ui/Card";
import CardBody from "./ui/CardBody";
import Input from "./ui/Input";
import Select from "./ui/Select";
import Textarea from "./ui/Textarea";
import PageHeader from "./components/PageHeader";
import theme, { brand, focusRingShadow, fonts, palette, radii } from "./theme";

const here = dirname(fileURLToPath(import.meta.url));
const tokensCss = readFileSync(resolve(here, "styles/tokens.css"), "utf8");
const globalCss = readFileSync(resolve(here, "styles/global.css"), "utf8");
const uiCss = readFileSync(resolve(here, "ui/ui.css"), "utf8");

describe("theme palette and tokens", () => {
  it("anchors the brand scale on the mockup accent colors", () => {
    expect(brand[500]).toBe("#9A2F22");
    expect(brand[600]).toBe("#7A241A");
    expect(brand[100]).toBe("#F6E6E0");
  });

  it("exposes the warm neutral palette", () => {
    expect(palette.ink).toBe("#2B1D1A");
    expect(palette.muted).toBe("#5E4B45");
    expect(palette.placeholder).toBe("#7A6A63");
    expect(palette.line).toBe("#E9DDD5");
    expect(palette.bgCanvas).toBe("#FAF6F1");
    expect(palette.bgSubtle).toBe("#FBF8F4");
    expect(palette.bgHover).toBe("#F5EEE8");
    expect(palette.surface).toBe("#FFFFFF");
    expect(palette.avatarBg).toBe("#EFE3D6");
    expect(palette.avatarFg).toBe("#5B4331");
  });

  it("defines the focus ring using the accent tint", () => {
    expect(focusRingShadow).toBe("0 0 0 2px #F6E6E0");
  });

  it("exports the theme object as the default", () => {
    expect(theme.palette).toBe(palette);
    expect(theme.brand).toBe(brand);
    expect(theme.fonts).toBe(fonts);
    expect(theme.radii).toBe(radii);
    expect(theme.focusRingShadow).toBe(focusRingShadow);
  });

  it("mirrors palette values as CSS custom properties", () => {
    expect(tokensCss).toContain("--color-accent: #9a2f22;");
    expect(tokensCss).toContain("--color-accent-hover: #7a241a;");
    expect(tokensCss).toContain("--color-accent-tint: #f6e6e0;");
    expect(tokensCss).toContain("--color-ink: #2b1d1a;");
    expect(tokensCss).toContain("--color-muted: #5e4b45;");
    expect(tokensCss).toContain("--color-placeholder: #7a6a63;");
    expect(tokensCss).toContain("--color-line: #e9ddd5;");
    expect(tokensCss).toContain("--color-bg-canvas: #faf6f1;");
    expect(tokensCss).toContain("--color-bg-subtle: #fbf8f4;");
    expect(tokensCss).toContain("--color-bg-hover: #f5eee8;");
    expect(tokensCss).toContain("--color-surface: #ffffff;");
    expect(tokensCss).toContain("--color-avatar-bg: #efe3d6;");
    expect(tokensCss).toContain("--color-avatar-fg: #5b4331;");
    expect(tokensCss).toContain("--focus-ring-shadow: 0 0 0 2px var(--color-accent-tint);");
  });
});

describe("theme foundations", () => {
  it("uses the Inter font stack for headings and body", () => {
    const inter = `"Inter", system-ui, -apple-system, "Segoe UI", sans-serif`;
    expect(fonts.heading).toBe(inter);
    expect(fonts.body).toBe(inter);
    expect(tokensCss).toContain(`--font-heading: ${inter};`);
    expect(tokensCss).toContain(`--font-body: ${inter};`);
  });

  it("defines the mockup border radii", () => {
    expect(radii.base).toBe("0.375rem");
    expect(radii.sm).toBe("10px");
    expect(radii.md).toBe("12px");
    expect(radii.lg).toBe("16px");
    expect(radii.card).toBe("16px");
    expect(tokensCss).toContain("--radius-sm: 10px;");
    expect(tokensCss).toContain("--radius-md: 12px;");
    expect(tokensCss).toContain("--radius-lg: 16px;");
    expect(tokensCss).toContain("--radius-card: 16px;");
  });

  it("applies the warm canvas and ink colors to the global body", () => {
    expect(globalCss).toContain("background-color: var(--color-bg-canvas);");
    expect(globalCss).toContain("color: var(--color-ink);");
    expect(globalCss).toContain("font-family: var(--font-body);");
  });
});

describe("shared component styles", () => {
  it("defines button variants and sizes", () => {
    expect(uiCss).toContain(".ui-button--accent");
    expect(uiCss).toContain("background-color: var(--color-accent);");
    expect(uiCss).toContain(".ui-button--accentOutline");
    expect(uiCss).toContain(".ui-button--icon");
    expect(uiCss).toContain(".ui-button--md");
    expect(uiCss).toContain("height: 44px;");
  });

  it("defines card, field, avatar, and page header styling", () => {
    expect(uiCss).toContain(".ui-card");
    expect(uiCss).toContain("border: 1px solid var(--color-line);");
    expect(uiCss).toContain(".ui-input:focus");
    expect(uiCss).toContain("box-shadow: var(--focus-ring-shadow);");
    expect(uiCss).toContain(".ui-avatar");
    expect(uiCss).toContain("background-color: var(--color-avatar-bg);");
    expect(uiCss).toContain(".page-header__title");
    expect(uiCss).toContain("letter-spacing: -0.01em;");
  });
});

describe("shared component rendering", () => {
  it("renders themed primitives and shared components", () => {
    render(() => (
      <Card>
        <CardBody>
          <PageHeader title="Account" subtitle="Manage your details" />
          <Input aria-label="Full name" placeholder="Full name" />
          <Select aria-label="Time slot">
            <option value="morning">Morning</option>
          </Select>
          <Textarea aria-label="Notes" placeholder="Notes" />
          <Button>Book</Button>
          <Avatar name="Ada Lovelace" />
          <Alert status="success">Saved</Alert>
        </CardBody>
      </Card>
    ));

    expect(screen.getByRole("heading", { name: "Account" })).toBeInTheDocument();
    expect(screen.getByText("Manage your details")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Book" })).toBeInTheDocument();
    expect(screen.getByLabelText("Full name")).toBeInTheDocument();
    expect(screen.getByLabelText("Time slot")).toBeInTheDocument();
    expect(screen.getByLabelText("Notes")).toBeInTheDocument();
    expect(screen.getByText("AL")).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent("Saved");
  });
});

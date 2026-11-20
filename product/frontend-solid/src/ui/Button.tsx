import type { JSX } from "@solidjs/web";

export type ButtonVariant = "accent" | "accentOutline" | "icon";
export type ButtonSize = "sm" | "md" | "lg";

export interface ButtonProps extends JSX.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

export default function Button(props: ButtonProps) {
  const variant = () => props.variant ?? "accent";
  const size = () => props.size ?? "md";

  const classes = () => {
    const base = "ui-button";
    const v = `ui-button--${variant()}`;
    const s = `ui-button--${size()}`;
    const extra = (props as { class?: string }).class ?? "";
    return [base, v, s, extra].filter(Boolean).join(" ");
  };

  return (
    <button
      {...props}
      class={classes()}
      type={(props as { type?: "button" | "submit" | "reset" }).type ?? "button"}
    >
      {(props as { children?: JSX.Element }).children}
    </button>
  );
}

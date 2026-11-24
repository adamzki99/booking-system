import type { JSX } from "@solidjs/web";

export type AvatarSize = "sm" | "md";

export interface AvatarProps {
  name?: string;
  size?: AvatarSize;
  getInitials?: (name: string) => string;
  class?: string;
  "aria-label"?: string;
}

function defaultInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
}

export default function Avatar(props: AvatarProps): JSX.Element {
  const size = () => props.size ?? "md";
  const label = () => {
    const name = props.name ?? "";
    if (props.getInitials) return props.getInitials(name);
    return defaultInitials(name);
  };
  const cls = () => {
    const base = "ui-avatar";
    const s = `ui-avatar--${size()}`;
    const extra = props.class ?? "";
    return [base, s, extra].filter(Boolean).join(" ");
  };
  const ariaLabel = () => props["aria-label"] ?? props.name;

  return (
    <>
      {/* oxlint-disable-next-line jsx-a11y/prefer-tag-over-role -- avatar renders text initials, not an image element */}
      <div class={cls()} role="img" aria-label={ariaLabel()}>
        {label()}
      </div>
    </>
  );
}

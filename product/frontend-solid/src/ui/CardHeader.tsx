import type { JSX } from "@solidjs/web";

export default function CardHeader(props: JSX.HTMLAttributes<HTMLDivElement>): JSX.Element {
  const cls = () =>
    ["ui-card-header", (props as { class?: string }).class ?? ""].filter(Boolean).join(" ");
  return (
    <div {...props} class={cls()}>
      {(props as { children?: JSX.Element }).children}
    </div>
  );
}

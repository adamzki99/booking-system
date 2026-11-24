import type { JSX } from "@solidjs/web";

export default function Card(props: JSX.HTMLAttributes<HTMLDivElement>) {
  const cls = () =>
    ["ui-card", (props as { class?: string }).class ?? ""].filter(Boolean).join(" ");
  return (
    <div {...props} class={cls()}>
      {(props as { children?: JSX.Element }).children}
    </div>
  );
}

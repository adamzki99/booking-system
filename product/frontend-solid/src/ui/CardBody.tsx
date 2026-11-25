import type { JSX } from "@solidjs/web";

export default function CardBody(props: JSX.HTMLAttributes<HTMLDivElement>): JSX.Element {
  const cls = () =>
    ["ui-card-body", (props as { class?: string }).class ?? ""].filter(Boolean).join(" ");
  return (
    <div {...props} class={cls()}>
      {(props as { children?: JSX.Element }).children}
    </div>
  );
}

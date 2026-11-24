import type { JSX } from "@solidjs/web";

export default function Select(props: JSX.SelectHTMLAttributes<HTMLSelectElement>) {
  const cls = () =>
    ["ui-select", (props as { class?: string }).class ?? ""].filter(Boolean).join(" ");
  return (
    <select {...props} class={cls()}>
      {(props as { children?: JSX.Element }).children}
    </select>
  );
}

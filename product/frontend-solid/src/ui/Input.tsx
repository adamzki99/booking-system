import type { JSX } from "@solidjs/web";

export default function Input(props: JSX.InputHTMLAttributes<HTMLInputElement>) {
  const cls = () => ["ui-input", ((props as { class?: string }).class ?? "")].filter(Boolean).join(" ");
  return <input {...props} class={cls()} />;
}

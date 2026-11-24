import type { JSX } from "@solidjs/web";

export default function Textarea(props: JSX.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const cls = () =>
    ["ui-textarea", (props as { class?: string }).class ?? ""].filter(Boolean).join(" ");
  return <textarea {...props} class={cls()} />;
}

import type { JSX } from "@solidjs/web";

export type AlertStatus = "info" | "error" | "success";

export interface AlertProps extends JSX.HTMLAttributes<HTMLDivElement> {
  status?: AlertStatus;
}

export default function Alert(props: AlertProps) {
  const status = () => props.status ?? "info";
  const cls = () => {
    const base = "ui-alert";
    const st = status() === "info" ? "" : `ui-alert--${status()}`;
    const extra = (props as { class?: string }).class ?? "";
    return [base, st, extra].filter(Boolean).join(" ");
  };
  const roleAttr = () => ((props.role as string | undefined) ?? "alert") as any;
  return (
    <div {...props} role={roleAttr()} class={cls()}>
      {(props as { children?: JSX.Element }).children}
    </div>
  );
}

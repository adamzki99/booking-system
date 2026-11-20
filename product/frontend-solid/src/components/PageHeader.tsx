import type { JSX } from "@solidjs/web";

export interface PageHeaderProps {
  title: string;
  subtitle: string;
}

/**
 * Shared page header from the mockups: a bold title with a muted descriptive
 * subtitle. Kept tiny on purpose so pages use one copy.
 */
export default function PageHeader(props: PageHeaderProps): JSX.Element {
  return (
    <header class="page-header">
      <h1 class="page-header__title">{props.title}</h1>
      <p class="page-header__subtitle">{props.subtitle}</p>
    </header>
  );
}

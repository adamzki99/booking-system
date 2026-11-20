import { Show } from "solid-js";
import type { JSX } from "@solidjs/web";
import { useLocation, useNavigate } from "@solidjs/router";
import { useSession } from "./auth/SessionContext";

function RedirectToLogin() {
  const location = useLocation();
  const navigate = useNavigate();

  navigate("/login", {
    replace: true,
    state: {
      from: {
        pathname: location.pathname,
        search: location.search,
        hash: location.hash,
      },
    },
  });

  return null;
}

/**
 * Renders its children only for signed-in users and redirects others to the
 * login page. While a stored token is being validated nothing is rendered, so
 * a reload does not flash the login page.
 */
export function RequireSession(props: { children?: JSX.Element }) {
  const session = useSession();

  return (
    <Show when={!session.loading()}>
      <Show when={session.user()} fallback={<RedirectToLogin />}>
        {props.children}
      </Show>
    </Show>
  );
}

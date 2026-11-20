import { render, screen } from "@solidjs/testing-library";
import { createRouter, memoryHistory } from "@solidjs/router";
import { describe, expect, it } from "vitest";
import { appRoutes } from "./App";
import { SessionProvider } from "./auth/SessionContext";

describe("App routing", () => {
  it("renders the login route", async () => {
    const Router = createRouter({
      routes: appRoutes,
      history: memoryHistory("/login"),
    });

    render(() => (
      <SessionProvider>
        <Router>{(props) => <>{props.children}</>}</Router>
      </SessionProvider>
    ));

    expect(await screen.findByRole("heading", { name: "Log in" })).toBeInTheDocument();
  });

  it("redirects signed-out users from a protected route to login", async () => {
    const Router = createRouter({
      routes: appRoutes,
      history: memoryHistory("/"),
    });

    render(() => (
      <SessionProvider>
        <Router>{(props) => <>{props.children}</>}</Router>
      </SessionProvider>
    ));

    expect(await screen.findByRole("heading", { name: "Log in" })).toBeInTheDocument();
  });
});

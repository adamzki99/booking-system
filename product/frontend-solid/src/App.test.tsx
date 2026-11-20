import { render, screen } from "@solidjs/testing-library";
import { describe, expect, it } from "vitest";
import App from "./App";

describe("App", () => {
  it("renders the smoke component", () => {
    render(() => <App />);

    expect(screen.getByRole("heading", { name: "Booking Solid" })).toBeInTheDocument();
    expect(screen.getByText("Smoke component is running.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Count: 0" })).toBeInTheDocument();
  });
});

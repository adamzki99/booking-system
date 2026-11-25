import { describe, expect, it } from "vitest";
import { ApiError } from "./client";
import { friendlyErrorMessage } from "./errors";

describe("friendlyErrorMessage", () => {
  it("maps a known invalid-email backend error to a helpful message", () => {
    expect(friendlyErrorMessage(new ApiError("auth: invalid email", 400), "fallback")).toBe(
      "Enter a valid email address.",
    );
  });

  it("maps rate limits to a friendly message", () => {
    expect(friendlyErrorMessage(new ApiError("auth: rate limited", 429), "fallback")).toContain(
      "Too many attempts",
    );
  });

  it("hides unknown internal error codes behind the fallback", () => {
    const message = friendlyErrorMessage(
      new ApiError("booking: conflict on interval", 409),
      "Could not add the user. Please try again.",
    );
    expect(message).toBe("Could not add the user. Please try again.");
    expect(message).not.toContain("booking:");
  });

  it("keeps a plain error message and falls back for non-errors", () => {
    expect(friendlyErrorMessage(new Error("boom"), "fallback")).toBe("boom");
    expect(friendlyErrorMessage(null, "fallback")).toBe("fallback");
  });
});

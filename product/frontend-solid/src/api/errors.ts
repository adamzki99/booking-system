import { ApiError } from "./client";

const RATE_LIMIT_MESSAGE = "Too many attempts. Please wait a little while and try again.";
const INVALID_EMAIL_MESSAGE = "Enter a valid email address.";
const INVALID_CODE_MESSAGE = "Enter the 6-character code from your email.";

/**
 * Maps a backend error to a user-facing message. Internal error prefixes such
 * as `auth:` or `booking:` are never shown; unknown failures use the fallback
 * supplied by the caller.
 */
export function friendlyErrorMessage(err: unknown, fallback: string): string {
  const raw = err instanceof Error ? err.message : "";
  const lower = raw.toLowerCase();

  if (err instanceof ApiError && (err.status === 429 || lower.includes("rate limit"))) {
    return RATE_LIMIT_MESSAGE;
  }
  if (lower.includes("invalid email")) return INVALID_EMAIL_MESSAGE;
  if (lower.includes("invalid code")) return INVALID_CODE_MESSAGE;

  // Backend errors carry internal namespace prefixes. Keep those details out
  // of the UI and show the caller's friendly fallback instead.
  if (/^[a-z][a-z0-9_-]*:/i.test(raw)) return fallback;
  return raw || fallback;
}

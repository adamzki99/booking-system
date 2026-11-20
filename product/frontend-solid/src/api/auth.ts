import { get, post } from "./client";

/** A user of the system, as returned by the users read side. */
export interface User {
  id: string;
  email: string;
  role: "basic" | "super" | "admin";
  address: string | null;
  active: boolean;
}

/** A booking interval, as returned by the booking read side. */
export interface Booking {
  id: string;
  /** Owner; normalized (the backend emits both snake_case and camelCase). */
  userId: string;
  start: string;
  end: string;
  status: "active" | "cancelled";
  createdAt?: string;
  cancelledAt?: string;
}

/** Runtime auth configuration exposed by the backend. */
export interface AuthConfig {
  qaMode: boolean;
}

/** Fetches runtime auth configuration. */
export function getAuthConfig(): Promise<AuthConfig> {
  return get<AuthConfig>("/api/auth/config");
}

/** Asks the backend to email a login code to the address. */
export function requestCode(email: string): Promise<void> {
  return post("/api/auth/request-code", { email });
}

/**
 * Verifies an email + 6-character code and returns the new session token.
 */
export function verify(email: string, code: string): Promise<string> {
  return post<{ token: string }>("/api/auth/verify", { email, code }).then(
    (res) => res.token,
  );
}

/** Signs in without a one-time code when QA mode is enabled. */
export function qaLogin(email: string): Promise<string> {
  return post<{ token: string }>("/api/auth/qa-login", { email }).then(
    (res) => res.token,
  );
}

/** Returns the signed-in user. */
export function currentUser(): Promise<User> {
  return get<User>("/api/users/me");
}

/** Alias for currentUser() (plan naming). */
export const getMe = currentUser;

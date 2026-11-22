import { get, patch, post } from "./client";
import type { User } from "./auth";

/** A user as the backend emits it (identity fields share both key styles). */
export interface RawUser {
  id: string;
  email: string;
  role: User["role"];
  address: string | null;
  active: boolean;
}

/** Lists all registered users (basic users can view the directory too). */
export function listUsers(): Promise<User[]> {
  return get<RawUser[]>("/api/users");
}

/** The pending state returned for an unconfirmed email change. */
export interface PendingEmailChange {
  pendingEmail: string;
  expiresAt: string;
}

/**
 * Starts a verified email change: the backend emails a code to the new
 * address; the account's login address is unchanged until the code is
 * confirmed. Requesting again replaces any pending change.
 */
export function requestEmailChange(email: string): Promise<PendingEmailChange> {
  return patch<PendingEmailChange>("/api/users/me/email", { email });
}

/** Returns the current user's pending email change, if any. */
export async function getPendingEmailChange(): Promise<PendingEmailChange | null> {
  const result = await get<PendingEmailChange | null>("/api/users/me/email-change");
  return result ?? null;
}

/** Confirms an email change with the code sent to the new address. */
export function confirmEmailChange(code: string): Promise<User> {
  return post<RawUser>("/api/users/me/email/confirm", { code });
}

/** Sends a new verification code to the current pending email address. */
export function resendEmailChange(): Promise<PendingEmailChange> {
  return post<PendingEmailChange>("/api/users/me/email-change/resend");
}

/** Cancels the current pending email change. */
export function cancelEmailChange(): Promise<void> {
  return post("/api/users/me/email-change/cancel");
}

/** Adds a basic user (super users only). */
export function addUser(input: { email: string; address: string }): Promise<User> {
  return post<RawUser>("/api/users", input);
}

/** Removes (deactivates) a basic user (super users only). */
export function removeUser(id: string): Promise<void> {
  return post(`/api/users/${encodeURIComponent(id)}/remove`);
}

/** Changes a basic user's address (super users only). */
export function changeUserAddress(id: string, address: string): Promise<User> {
  return patch<RawUser>(`/api/users/${encodeURIComponent(id)}/address`, { address });
}

/** Changes a user's role (admin only). */
export function changeUserRole(id: string, role: string): Promise<User> {
  return patch<RawUser>(`/api/users/${encodeURIComponent(id)}/role`, { role });
}

/** Alias matching common naming. */
export const updateUserRole = changeUserRole;
export const setUserRole = changeUserRole;

/** Alias matching the plan's naming. */
export const changeAddress = changeUserAddress;

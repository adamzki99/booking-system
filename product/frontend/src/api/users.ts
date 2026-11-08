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

/** Changes the signed-in user's email. */
export function updateMyEmail(email: string): Promise<User> {
  return patch<RawUser>("/api/users/me/email", { email });
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
export const updateEmail = updateMyEmail;
export const changeAddress = changeUserAddress;

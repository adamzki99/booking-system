import { post } from "./client";

/** Sends a message to all basic users (super users only). */
export function broadcastMessage(input: { subject: string; body: string }): Promise<void> {
  return post<void>("/api/broadcast", input);
}

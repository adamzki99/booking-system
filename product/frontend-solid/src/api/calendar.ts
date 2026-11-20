import { post } from "./client";

/** Regenerates (and returns) the signed-in user's iCal feed URL. */
export function regenerateCalendarUrl(): Promise<string> {
  return post<{ url: string }>("/api/account/calendar-token").then((res) => res.url);
}

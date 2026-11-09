import { get } from "./client";

/** Display info for the authenticated application shell, sourced from the sidecar. */
export interface ChromeInfo {
  header: string;
  footer: string;
  /** Next scheduled redeploy (RFC3339), or empty when no schedule is exposed. */
  nextRedeploy: string;
}

/** Fetches header/footer content from the backend (which proxies the sidecar). */
export function getChrome(): Promise<ChromeInfo> {
  return get<ChromeInfo>("/api/chrome");
}

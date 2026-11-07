const TOKEN_KEY = "booking.session-token";

/** Error returned by the API, carrying the HTTP status. */
export class ApiError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

/** Reads the stored session token, if any. */
export function getToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

/** Stores or clears the session token. */
export function setToken(token: string | null): void {
  try {
    if (token) {
      localStorage.setItem(TOKEN_KEY, token);
    } else {
      localStorage.removeItem(TOKEN_KEY);
    }
  } catch {
    // Storage unavailable (e.g. private mode): the session is just not kept.
  }
}

/** Performs an API request and unwraps the JSON body. */
export async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers);
  const token = getToken();
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  let body: BodyInit | undefined = undefined;
  if (options.body !== undefined) {
    headers.set("Content-Type", "application/json");
    body = typeof options.body === "string" ? options.body : JSON.stringify(options.body);
  }

  const res = await fetch(path, { ...options, headers, body });

  if (!res.ok) {
    let message = res.statusText || "request failed";
    try {
      const problem = (await res.json()) as { error?: string };
      if (problem?.error) {
        message = problem.error;
      }
    } catch {
      // Body was not JSON; keep the fallback message.
    }
    throw new ApiError(message, res.status);
  }

  if (res.status === 204) {
    return undefined as T;
  }
  const text = await res.text();
  if (!text) {
    return undefined as T;
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    return undefined as T;
  }
}

/** Extracts a user-displayable message from a thrown error. */
export function errorMessage(err: unknown, fallback: string): string {
  return err instanceof Error ? err.message : fallback;
}

/** Convenience GET. */
export function get<T>(path: string): Promise<T> {
  return request<T>(path, { method: "GET" });
}

/** Convenience POST with an optional JSON body. */
export function post<T>(path: string, payload?: unknown): Promise<T> {
  // request() serializes non-string bodies to JSON; the cast satisfies the
  // RequestInit["body"] type only.
  const body = payload === undefined ? undefined : (payload as BodyInit);
  return request<T>(path, { method: "POST", body });
}

/** Convenience PATCH with a JSON body. */
export function patch<T>(path: string, payload?: unknown): Promise<T> {
  const body = payload === undefined ? undefined : (payload as BodyInit);
  return request<T>(path, { method: "PATCH", body });
}

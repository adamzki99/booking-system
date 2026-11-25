import { createContext, createSignal, useContext } from "solid-js";
import type { ParentProps } from "solid-js";
import type { User } from "../api/auth";
import { currentUser, qaLogin, verify } from "../api/auth";
import { getToken, setToken } from "../api/client";

export interface Session {
  /** The signed-in user, or null when signed out. */
  user: () => User | null;
  /** True until the stored token (if any) has been validated. */
  loading: () => boolean;
  /** Verifies email + code, stores the token and loads the user. */
  login(email: string, code: string): Promise<void>;
  /** Signs in without a one-time code when QA mode is enabled. */
  loginWithQAMode(email: string): Promise<void>;
  /** Re-reads the signed-in user so the session matches the account. */
  refresh(): Promise<void>;
  /** Clears the session. */
  logout(): void;
}

const SessionContext = createContext<Session | null>(null);

export function SessionProvider(props: ParentProps) {
  const [user, setUser] = createSignal<User | null>(null);
  const [loading, setLoading] = createSignal<boolean>(Boolean(getToken()));

  if (getToken()) {
    void currentUser()
      .then((u) => {
        setUser(u);
        setLoading(false);
      })
      .catch(() => {
        // Token expired or revoked: treat as signed out.
        setToken(null);
        setLoading(false);
      });
  }

  const session: Session = {
    user,
    loading,
    async login(email, code) {
      const token = await verify(email, code);
      setToken(token);
      const u = await currentUser();
      setUser(u);
    },
    async loginWithQAMode(email) {
      const token = await qaLogin(email);
      setToken(token);
      const u = await currentUser();
      setUser(u);
    },
    async refresh() {
      if (!getToken()) {
        return;
      }
      const u = await currentUser();
      setUser(u);
    },
    logout() {
      setToken(null);
      setUser(null);
    },
  };

  return <SessionContext value={session}>{props.children}</SessionContext>;
}

export function useSession(): Session {
  const session = useContext(SessionContext);
  if (!session) {
    throw new Error("useSession must be used within a SessionProvider");
  }
  return session;
}

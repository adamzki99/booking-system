import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import { getToken, setToken } from "../api/client";
import type { User } from "../api/auth";
import { currentUser, verify } from "../api/auth";

interface Session {
  /** The signed-in user, or null when signed out. */
  user: User | null;
  /** True until the stored token (if any) has been validated. */
  loading: boolean;
  /** Verifies email + code, stores the token and loads the user. */
  login(email: string, code: string): Promise<void>;
  /** Clears the session. */
  logout(): void;
}

const SessionContext = createContext<Session | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState<boolean>(Boolean(getToken()));

  useEffect(() => {
    let cancelled = false;
    if (!getToken()) {
      setLoading(false);
      return;
    }
    currentUser()
      .then((u) => {
        if (!cancelled) {
          setUser(u);
          setLoading(false);
        }
      })
      .catch(() => {
        // Token expired or revoked: treat as signed out.
        setToken(null);
        if (!cancelled) {
          setLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const session: Session = {
    user,
    loading,
    async login(email, code) {
      const token = await verify(email, code);
      setToken(token);
      const u = await currentUser();
      setUser(u);
    },
    logout() {
      setToken(null);
      setUser(null);
    },
  };

  return <SessionContext.Provider value={session}>{children}</SessionContext.Provider>;
}

export function useSession(): Session {
  const session = useContext(SessionContext);
  if (!session) {
    throw new Error("useSession must be used within a SessionProvider");
  }
  return session;
}

import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { errorMessage } from "../api/client";
import type { User } from "../api/auth";
import { currentUser } from "../api/auth";
import { updateMyEmail } from "../api/users";
import { regenerateCalendarUrl } from "../api/calendar";
import { useSession } from "../auth/SessionContext";

export default function Account() {
  const { user: sessionUser } = useSession();
  const [me, setMe] = useState<User | null>(sessionUser);
  const [email, setEmail] = useState(sessionUser?.email ?? "");
  const [error, setError] = useState<string | null>(null);
  const [icalUrl, setIcalUrl] = useState<string>("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    currentUser()
      .then((u) => {
        if (!cancelled) {
          setMe(u);
          setEmail(u.email);
        }
      })
      .catch(() => {
        /* keep session user */
      });
    return () => {
      cancelled = true;
    };
  }, []);

  async function onChangeEmail(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const updated = await updateMyEmail(email);
      setMe(updated);
    } catch (err) {
      setError(errorMessage(err, "could not change email"));
    } finally {
      setBusy(false);
    }
  }

  async function onRegenerate() {
    setError(null);
    setBusy(true);
    try {
      const url = await regenerateCalendarUrl();
      setIcalUrl(url);
    } catch (err) {
      setError(errorMessage(err, "could not regenerate calendar url"));
    } finally {
      setBusy(false);
    }
  }

  async function onCopy() {
    if (!icalUrl) return;
    try {
      await navigator.clipboard.writeText(icalUrl);
    } catch {
      /* ignore */
    }
  }

  return (
    <main>
      <h1>Account</h1>
      {error && <p role="alert">{error}</p>}
      <section>
        <h2>Email</h2>
        <p>{me?.email}</p>
        <form onSubmit={onChangeEmail}>
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </label>
          <button type="submit" disabled={busy}>
            Change email
          </button>
        </form>
      </section>
      <section>
        <h2>Calendar</h2>
        {icalUrl && (
          <>
            <p>{icalUrl}</p>
            <button type="button" onClick={() => void onCopy()}>
              Copy
            </button>
          </>
        )}
        <button type="button" onClick={() => void onRegenerate()} disabled={busy}>
          Regenerate
        </button>
      </section>
    </main>
  );
}

import { useState } from "react";
import type { FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { errorMessage } from "../api/client";
import { requestCode } from "../api/auth";
import { useSession } from "../auth/SessionContext";

/**
 * Happy flow steps 1–3: enter email, receive a 6-character code in the mail,
 * enter the code and get signed in.
 */
export default function Login() {
  const navigate = useNavigate();
  const { login } = useSession();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [codeSent, setCodeSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function requestCodeForEmail(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await requestCode(email);
      setCodeSent(true);
    } catch (err) {
      setError(errorMessage(err, "request failed"));
    } finally {
      setBusy(false);
    }
  }

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await login(email, code);
      navigate("/", { replace: true });
    } catch (err) {
      setError(errorMessage(err, "sign-in failed"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main>
      <h1>Booking</h1>
      {codeSent ? (
        <form onSubmit={signIn}>
          <p>A login code was sent to {email}. The code is valid for 10 minutes.</p>
          <label>
            Code
            <input
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              maxLength={6}
              autoFocus
              required
            />
          </label>
          <button type="submit" disabled={busy || code.length !== 6}>
            Sign in
          </button>
          {error && <p role="alert">{error}</p>}
        </form>
      ) : (
        <form onSubmit={requestCodeForEmail}>
          <p>Sign in with your email — we will send you a one-time code.</p>
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
              required
            />
          </label>
          <button type="submit" disabled={busy || !email}>
            Request code
          </button>
          {error && <p role="alert">{error}</p>}
        </form>
      )}
    </main>
  );
}

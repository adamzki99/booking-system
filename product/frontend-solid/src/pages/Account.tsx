import { Show, createSignal } from "solid-js";
import { errorMessage } from "../api/client";
import type { User } from "../api/auth";
import { currentUser } from "../api/auth";
import {
  cancelEmailChange,
  confirmEmailChange,
  getPendingEmailChange,
  requestEmailChange,
  resendEmailChange,
  type PendingEmailChange,
} from "../api/users";
import { regenerateCalendarUrl } from "../api/calendar";
import { useSession } from "../auth/SessionContext";
import PageHeader from "../components/PageHeader";
import Alert from "../ui/Alert";
import Button from "../ui/Button";
import Card from "../ui/Card";
import CardBody from "../ui/CardBody";
import CardHeader from "../ui/CardHeader";
import Input from "../ui/Input";
import { Errored, Loading, createAsyncData, createMutation } from "../data";
import "./Account.css";

interface AccountData {
  me: User | null;
  pending: PendingEmailChange | null;
}

function friendlyAccountError(err: unknown, fallback: string): string {
  const raw = err instanceof Error ? err.message : "";
  if (/invalid email change code/i.test(raw)) {
    return "That verification code is not correct. Check the code and try again, or resend a new code.";
  }
  if (/email change verification expired/i.test(raw)) {
    return "This verification code has expired. Resend a new code or start a new email change.";
  }
  if (/no pending email change/i.test(raw)) {
    return "There is no pending email change. Start a new request if you still want to change your email.";
  }
  if (/duplicate email/i.test(raw)) {
    return "That email address is already in use. Choose a different email address.";
  }
  if (/rate limit/i.test(raw)) {
    return "Too many attempts. Please wait a little while and try again.";
  }
  if (raw && !/^user:/i.test(raw)) {
    return errorMessage(err, fallback);
  }
  if (/^user:/i.test(raw)) {
    return fallback;
  }
  return fallback;
}

function formatExpiry(expiresAt: string): string {
  const date = new Date(expiresAt);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString();
}

async function loadAccountData(fallbackUser: User | null): Promise<AccountData> {
  let me: User | null = fallbackUser;
  let pending: PendingEmailChange | null = null;
  try {
    me = await currentUser();
  } catch {
    /* keep session user */
  }
  try {
    pending = await getPendingEmailChange();
  } catch {
    /* pending state unavailable; keep local state */
  }
  return { me, pending };
}

export default function Account() {
  const session = useSession();
  const initial = createAsyncData(() => loadAccountData(session.user()));

  return (
    <main class="account-page">
      <Errored
        fallback={(err) => (
          <Alert status="error">{errorMessage(err(), "Could not load account.")}</Alert>
        )}
      >
        <Loading fallback={<p>Loading account...</p>}>
          {(() => {
            const seed = initial();
            return <AccountView seed={seed} />;
          })()}
        </Loading>
      </Errored>
    </main>
  );
}

function AccountView(props: { seed: AccountData }) {
  const session = useSession();
  // oxlint-disable-next-line solid/reactivity -- initial prop read; seed is stable after load
  const seed = props.seed;

  const [me, setMe] = createSignal<User | null>(seed.me);
  const [email, setEmail] = createSignal(seed.me?.email ?? "");
  const [code, setCode] = createSignal("");
  const [pending, setPending] = createSignal<PendingEmailChange | null>(seed.pending);
  const [showRequestForm, setShowRequestForm] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);
  const [notice, setNotice] = createSignal<string | null>(null);
  const [icalUrl, setIcalUrl] = createSignal("");
  const [busy, setBusy] = createSignal(false);

  const onRequestEmailChange = createMutation(function* (event: Event) {
    event.preventDefault();
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const requested = (yield requestEmailChange(email())) as PendingEmailChange;
      setPending(requested);
      setCode("");
      setShowRequestForm(false);
      setNotice(`A verification code was sent to ${requested.pendingEmail}.`);
    } catch (err) {
      setError(friendlyAccountError(err, "Could not request the email change. Please try again."));
    } finally {
      setBusy(false);
    }
  });

  const onConfirmEmailChange = createMutation(function* (event: Event) {
    event.preventDefault();
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const updated = (yield confirmEmailChange(code())) as User;
      setMe(updated);
      setEmail(updated.email);
      setPending(null);
      setCode("");
      setShowRequestForm(false);
      setNotice("Your email address has been updated.");
      yield session.refresh();
    } catch (err) {
      setError(friendlyAccountError(err, "Could not confirm the email change. Please try again."));
    } finally {
      setBusy(false);
    }
  });

  const onResend = createMutation(function* () {
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const updated = (yield resendEmailChange()) as PendingEmailChange;
      setPending(updated);
      setCode("");
      setNotice(`A new verification code was sent to ${updated.pendingEmail}.`);
    } catch (err) {
      setError(
        friendlyAccountError(err, "Could not resend the verification code. Please try again."),
      );
    } finally {
      setBusy(false);
    }
  });

  const onCancelPending = createMutation(function* () {
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      yield cancelEmailChange();
      setPending(null);
      setCode("");
      setShowRequestForm(false);
      setNotice("The pending email change was cancelled.");
    } catch (err) {
      setError(
        friendlyAccountError(err, "Could not cancel the pending email change. Please try again."),
      );
    } finally {
      setBusy(false);
    }
  });

  const onRegenerate = createMutation(function* () {
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const url = (yield regenerateCalendarUrl()) as string;
      setIcalUrl(url);
    } catch (err) {
      setError(
        friendlyAccountError(err, "Could not regenerate the calendar URL. Please try again."),
      );
    } finally {
      setBusy(false);
    }
  });

  const onCopy = createMutation(function* () {
    if (!icalUrl()) return;
    try {
      yield navigator.clipboard.writeText(icalUrl());
      setNotice("Calendar URL copied.");
    } catch {
      /* ignore */
    }
  });

  const showPendingPanel = () => Boolean(pending()) && !showRequestForm();
  const showEmailForm = () => !pending() || showRequestForm();

  return (
    <div class="account-stack">
      <PageHeader
        title="Account"
        subtitle="Update your email address and manage your calendar feed."
      />

      <Show when={error()}>{(msg) => <Alert status="error">{msg()}</Alert>}</Show>
      <Show when={notice()}>
        {(msg) => (
          <Alert status="success" role="status">
            {msg()}
          </Alert>
        )}
      </Show>

      <Card>
        <CardHeader>
          <h2 style={{ "font-size": "17px", "font-weight": "700", margin: "0" }}>Email</h2>
        </CardHeader>
        <CardBody>
          <div class="account-section-stack">
            <p data-testid="account-email">{me()?.email}</p>

            <Show when={showPendingPanel() && pending()}>
              {(p) => (
                <div class="account-section-stack" data-testid="pending-email-change">
                  <Alert status="info">
                    <div>
                      <p style={{ "font-weight": "600", margin: "0 0 0.25rem 0" }}>
                        Email change pending
                      </p>
                      <p style={{ margin: "0" }}>
                        A verification code was sent to {p().pendingEmail}. The address changes only
                        after you confirm it; until then this account still signs in with{" "}
                        {me()?.email}.
                      </p>
                      <Show when={formatExpiry(p().expiresAt)}>
                        {(expiry) => (
                          <p class="account-muted" style={{ margin: "0.25rem 0 0 0" }}>
                            Code expires: {expiry()}
                          </p>
                        )}
                      </Show>
                    </div>
                  </Alert>

                  <form onSubmit={(e) => void onConfirmEmailChange(e)}>
                    <div class="account-section-stack">
                      <div class="account-field">
                        <label class="account-label" for="account-code">
                          Verification code
                        </label>
                        <Input
                          id="account-code"
                          type="text"
                          value={code()}
                          onInput={(e) => setCode(e.currentTarget.value.toUpperCase())}
                          maxlength={6}
                          autocomplete="one-time-code"
                        />
                      </div>
                      <div class="account-actions">
                        <Button
                          type="submit"
                          variant="accent"
                          size="lg"
                          disabled={busy() || code().trim().length === 0}
                        >
                          Confirm email change
                        </Button>
                        <Button
                          type="button"
                          variant="accentOutline"
                          size="lg"
                          onClick={() => void onResend()}
                          disabled={busy()}
                        >
                          Resend code
                        </Button>
                      </div>
                    </div>
                  </form>

                  <div class="account-actions">
                    <Button
                      type="button"
                      variant="accentOutline"
                      onClick={() => setShowRequestForm(true)}
                      disabled={busy()}
                    >
                      Use a different email
                    </Button>
                    <Button
                      type="button"
                      variant="accentOutline"
                      onClick={() => void onCancelPending()}
                      disabled={busy()}
                    >
                      Cancel email change
                    </Button>
                  </div>
                </div>
              )}
            </Show>

            <Show when={showEmailForm()}>
              <form onSubmit={(e) => void onRequestEmailChange(e)}>
                <div class="account-section-stack">
                  <Show when={pending() && showRequestForm()}>
                    <Alert status="info">
                      Sending a code to a different email will replace the pending change to{" "}
                      {pending()?.pendingEmail}.
                    </Alert>
                  </Show>
                  <div class="account-field">
                    <label class="account-label" for="account-email">
                      New email
                    </label>
                    <Input
                      id="account-email"
                      type="email"
                      value={email()}
                      onInput={(e) => setEmail(e.currentTarget.value)}
                    />
                  </div>
                  <div class="account-actions">
                    <Button type="submit" variant="accent" size="lg" disabled={busy()}>
                      Send verification code
                    </Button>
                    <Show when={pending() && showRequestForm()}>
                      <Button
                        type="button"
                        variant="accentOutline"
                        size="lg"
                        onClick={() => setShowRequestForm(false)}
                        disabled={busy()}
                      >
                        Back to pending change
                      </Button>
                    </Show>
                  </div>
                </div>
              </form>
            </Show>
          </div>
        </CardBody>
      </Card>

      <Card>
        <CardHeader>
          <h2 style={{ "font-size": "17px", "font-weight": "700", margin: "0" }}>Calendar</h2>
        </CardHeader>
        <CardBody>
          <div class="account-section-stack">
            <Show when={icalUrl()}>
              {(url) => (
                <>
                  <code class="account-code">{url()}</code>
                  <div>
                    <Button type="button" variant="accentOutline" onClick={() => void onCopy()}>
                      Copy
                    </Button>
                  </div>
                </>
              )}
            </Show>
            <div>
              <Button
                type="button"
                variant="accentOutline"
                onClick={() => void onRegenerate()}
                disabled={busy()}
              >
                Regenerate
              </Button>
            </div>
          </div>
        </CardBody>
      </Card>
    </div>
  );
}

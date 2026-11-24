import { Show, Switch, Match, createSignal, onCleanup } from "solid-js";
import { useNavigate } from "@solidjs/router";
import Alert from "../ui/Alert";
import Button from "../ui/Button";
import Card from "../ui/Card";
import CardBody from "../ui/CardBody";
import Input from "../ui/Input";
import { ApiError, errorMessage } from "../api/client";
import { getAuthConfig, requestCode } from "../api/auth";
import { useSession } from "../auth/SessionContext";
import "./Login.css";

const EMAIL_GUIDANCE = "Enter a valid email address, for example name@example.com.";
const CODE_GUIDANCE = "Enter the 6-character code from your email.";

function isValidEmail(value: string): boolean {
  const trimmed = value.trim();
  // Simple check: non-empty local and domain parts with a dot in domain.
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed);
}

function friendlyAuthError(err: unknown, fallback: string): string {
  const raw = err instanceof Error ? err.message : "";
  const lower = raw.toLowerCase();
  if (err instanceof ApiError) {
    if (err.status === 429 || lower.includes("rate limit")) {
      return "Too many attempts. Please wait a little while and try again.";
    }
    if (err.status === 401 || lower.includes("invalid or expired code")) {
      return "That code is invalid or has expired. Request a new code and try again.";
    }
    if (lower.includes("invalid code")) {
      return CODE_GUIDANCE;
    }
    if (lower.includes("invalid email")) {
      return EMAIL_GUIDANCE;
    }
  }
  // Avoid leaking internal "auth: ..." prefixes to users.
  if (raw && !/^auth:/i.test(raw)) {
    return errorMessage(err, fallback);
  }
  return fallback;
}

/**
 * Happy flow steps 1-3: enter email, receive a 6-character code in the mail,
 * enter the code and get signed in. In QA mode the code step is bypassed.
 */
export default function Login() {
  const navigate = useNavigate();
  const session = useSession();
  const [email, setEmail] = createSignal("");
  const [code, setCode] = createSignal("");
  const [codeSent, setCodeSent] = createSignal(false);
  const [qaMode, setQaMode] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);
  const [emailError, setEmailError] = createSignal<string | null>(null);
  const [busy, setBusy] = createSignal(false);
  let emailInputRef: HTMLInputElement | undefined;

  let configCancelled = false;
  void getAuthConfig()
    .then((cfg) => {
      if (!configCancelled) {
        setQaMode(cfg.qaMode);
      }
    })
    .catch(() => {
      if (!configCancelled) {
        setQaMode(false);
      }
    });
  onCleanup(() => {
    configCancelled = true;
  });

  function validateEmail(): boolean {
    const trimmed = email().trim();
    if (!trimmed || !isValidEmail(trimmed)) {
      setEmailError(EMAIL_GUIDANCE);
      emailInputRef?.focus();
      return false;
    }
    setEmailError(null);
    return true;
  }

  async function requestCodeForEmail(event: Event) {
    event.preventDefault();
    setError(null);
    if (!validateEmail()) {
      return;
    }
    setBusy(true);
    try {
      await requestCode(email().trim());
      setCodeSent(true);
      setEmailError(null);
    } catch (err) {
      setError(friendlyAuthError(err, "We could not send a login code. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function signIn(event: Event) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await session.login(email().trim(), code().trim());
      navigate("/", { replace: true });
    } catch (err) {
      setError(friendlyAuthError(err, "We could not sign you in. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function signInWithoutCode(event: Event) {
    event.preventDefault();
    setError(null);
    if (!validateEmail()) {
      return;
    }
    setBusy(true);
    try {
      await session.loginWithQAMode(email().trim());
      navigate("/", { replace: true });
    } catch (err) {
      setError(friendlyAuthError(err, "We could not sign you in. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  const description = () =>
    qaMode()
      ? "Sign in with your email."
      : codeSent()
        ? "Enter the code we sent you to finish signing in."
        : "Sign in with your email, we will send you a one-time code.";

  return (
    <div class="login-page">
      <div class="login-stack">
        <div class="login-header">
          <div class="login-mark" aria-hidden="true">
            B
          </div>
          <h1 class="login-title">Booking</h1>
          <p class="login-description">{description()}</p>
        </div>

        <Card class="login-card">
          <CardBody>
            <div class="login-card-stack">
              <Switch>
                <Match when={qaMode()}>
                  <form
                    class="login-form"
                    onSubmit={(e) => {
                      void signInWithoutCode(e);
                    }}
                    novalidate
                  >
                    <div class={["login-field", { "login-field--invalid": !!emailError() }]}>
                      {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                      <label class="login-label" for="email">
                        Email
                      </label>
                      <Input
                        id="email"
                        ref={(el) => {
                          emailInputRef = el;
                        }}
                        type="email"
                        value={email()}
                        onInput={(e) => {
                          setEmail(e.currentTarget.value);
                          if (emailError()) setEmailError(null);
                        }}
                        autofocus
                        class={emailError() ? "login-input--invalid" : undefined}
                        aria-invalid={emailError() ? "true" : undefined}
                        aria-describedby={emailError() ? "email-error" : undefined}
                      />
                      <Show when={emailError()}>
                        <p id="email-error" class="login-field-error">
                          {emailError()}
                        </p>
                      </Show>
                    </div>
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      class="login-submit"
                      disabled={busy() || !email().trim()}
                    >
                      Sign in
                    </Button>
                  </form>
                </Match>
                <Match when={codeSent()}>
                  <form
                    class="login-form"
                    onSubmit={(e) => {
                      void signIn(e);
                    }}
                    novalidate
                  >
                    <p class="login-code-info">
                      A login code was sent to {email().trim()}. The code is valid for 10 minutes.
                    </p>
                    <div class="login-field">
                      {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                      <label class="login-label" for="code">
                        Code
                      </label>
                      <Input
                        id="code"
                        value={code()}
                        onInput={(e) => setCode(e.currentTarget.value.toUpperCase())}
                        maxlength={6}
                        autocomplete="one-time-code"
                        inputmode="text"
                        autofocus
                      />
                    </div>
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      class="login-submit"
                      disabled={busy() || code().trim().length !== 6}
                    >
                      Sign in
                    </Button>
                  </form>
                </Match>
                <Match when={!qaMode() && !codeSent()}>
                  <form
                    class="login-form"
                    onSubmit={(e) => {
                      void requestCodeForEmail(e);
                    }}
                    novalidate
                  >
                    <div class={["login-field", { "login-field--invalid": !!emailError() }]}>
                      {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                      <label class="login-label" for="email">
                        Email
                      </label>
                      <Input
                        id="email"
                        ref={(el) => {
                          emailInputRef = el;
                        }}
                        type="email"
                        value={email()}
                        onInput={(e) => {
                          setEmail(e.currentTarget.value);
                          if (emailError()) setEmailError(null);
                        }}
                        autofocus
                        class={emailError() ? "login-input--invalid" : undefined}
                        aria-invalid={emailError() ? "true" : undefined}
                        aria-describedby={emailError() ? "email-error" : undefined}
                      />
                      <Show when={emailError()}>
                        <p id="email-error" class="login-field-error">
                          {emailError()}
                        </p>
                      </Show>
                    </div>
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      class="login-submit"
                      disabled={busy() || !email().trim()}
                    >
                      Request code
                    </Button>
                  </form>
                </Match>
              </Switch>
              <Show when={error()}>{(msg) => <Alert status="error">{msg()}</Alert>}</Show>
            </div>
          </CardBody>
        </Card>
      </div>
    </div>
  );
}

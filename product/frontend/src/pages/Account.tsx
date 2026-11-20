import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import {
  Alert,
  AlertIcon,
  Box,
  Button,
  Card,
  CardBody,
  CardHeader,
  Code,
  FormControl,
  FormLabel,
  Heading,
  HStack,
  Input,
  Text,
  VStack,
} from "@chakra-ui/react";
import { errorMessage } from "../api/client";
import type { User } from "../api/auth";
import { currentUser } from "../api/auth";
import {
  cancelEmailChange,
  confirmEmailChange,
  getPendingEmailChange,
  requestEmailChange,
  resendEmailChange,
} from "../api/users";
import type { PendingEmailChange } from "../api/users";
import { regenerateCalendarUrl } from "../api/calendar";
import { useSession } from "../auth/SessionContext";
import PageHeader from "../components/PageHeader";

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
    // Keep non-auth internal prefixes out of the UI where possible.
    return fallback;
  }
  return fallback;
}

function formatExpiry(expiresAt: string): string {
  const date = new Date(expiresAt);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString();
}

export default function Account() {
  const { user: sessionUser, refresh } = useSession();
  const [me, setMe] = useState<User | null>(sessionUser);
  const [email, setEmail] = useState(sessionUser?.email ?? "");
  const [code, setCode] = useState("");
  const [pending, setPending] = useState<PendingEmailChange | null>(null);
  const [showRequestForm, setShowRequestForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [icalUrl, setIcalUrl] = useState<string>("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const u = await currentUser();
        if (cancelled) return;
        setMe(u);
        setEmail(u.email);
      } catch {
        /* keep session user */
      }
      try {
        const p = await getPendingEmailChange();
        if (cancelled) return;
        setPending(p);
        if (p) {
          setShowRequestForm(false);
        }
      } catch {
        /* pending state unavailable; keep local state */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  async function onRequestEmailChange(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const requested = await requestEmailChange(email);
      setPending(requested);
      setCode("");
      setShowRequestForm(false);
      setNotice(`A verification code was sent to ${requested.pendingEmail}.`);
    } catch (err) {
      setError(friendlyAccountError(err, "Could not request the email change. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function onConfirmEmailChange(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const updated = await confirmEmailChange(code);
      setMe(updated);
      setEmail(updated.email);
      setPending(null);
      setCode("");
      setShowRequestForm(false);
      setNotice("Your email address has been updated.");
      // The stored session now resolves to the new identity; keep the
      // session context in agreement with the account.
      await refresh();
    } catch (err) {
      setError(friendlyAccountError(err, "Could not confirm the email change. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function onResend() {
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const updated = await resendEmailChange();
      setPending(updated);
      setCode("");
      setNotice(`A new verification code was sent to ${updated.pendingEmail}.`);
    } catch (err) {
      setError(friendlyAccountError(err, "Could not resend the verification code. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function onCancelPending() {
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      await cancelEmailChange();
      setPending(null);
      setCode("");
      setShowRequestForm(false);
      setNotice("The pending email change was cancelled.");
    } catch (err) {
      setError(friendlyAccountError(err, "Could not cancel the pending email change. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function onRegenerate() {
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      const url = await regenerateCalendarUrl();
      setIcalUrl(url);
    } catch (err) {
      setError(friendlyAccountError(err, "Could not regenerate the calendar URL. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function onCopy() {
    if (!icalUrl) return;
    try {
      await navigator.clipboard.writeText(icalUrl);
      setNotice("Calendar URL copied.");
    } catch {
      /* ignore */
    }
  }

  const showPendingPanel = pending && !showRequestForm;
  const showEmailForm = !pending || showRequestForm;

  return (
    <Box as="main" maxW="1040px" mx="auto" w="full">
      <VStack spacing={6} align="stretch">
        <PageHeader
          title="Account"
          subtitle="Update your email address and manage your calendar feed."
        />

        {error && (
          <Alert status="error" role="alert">
            <AlertIcon />
            {error}
          </Alert>
        )}
        {notice && (
          <Alert status="success" role="status">
            <AlertIcon />
            {notice}
          </Alert>
        )}

        <Card as="section">
          <CardHeader pb={0}>
            <Heading as="h2" fontSize="17px" fontWeight={700}>
              Email
            </Heading>
          </CardHeader>
          <CardBody>
            <VStack spacing={4} align="stretch">
              <Text data-testid="account-email">{me?.email}</Text>

              {showPendingPanel && pending && (
                <VStack spacing={4} align="stretch" data-testid="pending-email-change">
                  <Alert status="info">
                    <AlertIcon />
                    <Box>
                      <Text fontWeight={600}>Email change pending</Text>
                      <Text>
                        A verification code was sent to {pending.pendingEmail}. The
                        address changes only after you confirm it; until then this
                        account still signs in with {me?.email}.
                      </Text>
                      {formatExpiry(pending.expiresAt) && (
                        <Text fontSize="sm" color="muted">
                          Code expires: {formatExpiry(pending.expiresAt)}
                        </Text>
                      )}
                    </Box>
                  </Alert>

                  <Box as="form" onSubmit={onConfirmEmailChange}>
                    <VStack spacing={4} align="stretch">
                      <FormControl>
                        <FormLabel htmlFor="account-code">Verification code</FormLabel>
                        <Input
                          id="account-code"
                          type="text"
                          value={code}
                          onChange={(e) => setCode(e.target.value.toUpperCase())}
                          maxLength={6}
                          autoComplete="one-time-code"
                        />
                      </FormControl>
                      <HStack spacing={3} flexWrap="wrap">
                        <Button
                          type="submit"
                          variant="accent"
                          size="lg"
                          isLoading={busy}
                          isDisabled={code.trim().length === 0}
                        >
                          Confirm email change
                        </Button>
                        <Button
                          type="button"
                          variant="outline"
                          size="lg"
                          onClick={() => void onResend()}
                          isLoading={busy}
                        >
                          Resend code
                        </Button>
                      </HStack>
                    </VStack>
                  </Box>

                  <HStack spacing={3} flexWrap="wrap">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => setShowRequestForm(true)}
                      isDisabled={busy}
                    >
                      Use a different email
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => void onCancelPending()}
                      isLoading={busy}
                    >
                      Cancel email change
                    </Button>
                  </HStack>
                </VStack>
              )}

              {showEmailForm && (
                <Box as="form" onSubmit={onRequestEmailChange}>
                  <VStack spacing={4} align="stretch">
                    {pending && showRequestForm && (
                      <Alert status="info">
                        <AlertIcon />
                        Sending a code to a different email will replace the pending
                        change to {pending.pendingEmail}.
                      </Alert>
                    )}
                    <FormControl>
                      <FormLabel htmlFor="account-email">New email</FormLabel>
                      <Input
                        id="account-email"
                        type="email"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                      />
                    </FormControl>
                    <HStack spacing={3} flexWrap="wrap">
                      <Button
                        type="submit"
                        variant="accent"
                        size="lg"
                        isLoading={busy}
                      >
                        Send verification code
                      </Button>
                      {pending && showRequestForm && (
                        <Button
                          type="button"
                          variant="outline"
                          size="lg"
                          onClick={() => setShowRequestForm(false)}
                          isDisabled={busy}
                        >
                          Back to pending change
                        </Button>
                      )}
                    </HStack>
                  </VStack>
                </Box>
              )}
            </VStack>
          </CardBody>
        </Card>

        <Card as="section">
          <CardHeader pb={0}>
            <Heading as="h2" fontSize="17px" fontWeight={700}>
              Calendar
            </Heading>
          </CardHeader>
          <CardBody>
            <VStack spacing={3} align="stretch">
              {icalUrl && (
                <>
                  <Code p={2} borderRadius="base" wordBreak="break-all">
                    {icalUrl}
                  </Code>
                  <Button
                    variant="outline"
                    alignSelf="flex-start"
                    onClick={() => void onCopy()}
                  >
                    Copy
                  </Button>
                </>
              )}
              <Button
                variant="outline"
                alignSelf="flex-start"
                onClick={() => void onRegenerate()}
                isLoading={busy}
              >
                Regenerate
              </Button>
            </VStack>
          </CardBody>
        </Card>
      </VStack>
    </Box>
  );
}

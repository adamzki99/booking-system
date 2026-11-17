import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import {
  Alert,
  AlertIcon,
  Box,
  Button,
  Code,
  FormControl,
  FormLabel,
  Heading,
  Input,
  Text,
  VStack,
} from "@chakra-ui/react";
import { errorMessage } from "../api/client";
import type { User } from "../api/auth";
import { currentUser } from "../api/auth";
import { confirmEmailChange, requestEmailChange } from "../api/users";
import type { PendingEmailChange } from "../api/users";
import { regenerateCalendarUrl } from "../api/calendar";
import { useSession } from "../auth/SessionContext";

export default function Account() {
  const { user: sessionUser, refresh } = useSession();
  const [me, setMe] = useState<User | null>(sessionUser);
  const [email, setEmail] = useState(sessionUser?.email ?? "");
  const [code, setCode] = useState("");
  const [pending, setPending] = useState<PendingEmailChange | null>(null);
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

  async function onRequestEmailChange(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const requested = await requestEmailChange(email);
      setPending(requested);
      setCode("");
    } catch (err) {
      setError(errorMessage(err, "could not request email change"));
    } finally {
      setBusy(false);
    }
  }

  async function onConfirmEmailChange(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const updated = await confirmEmailChange(code);
      setMe(updated);
      setEmail(updated.email);
      setPending(null);
      setCode("");
      // The stored session now resolves to the new identity; keep the
      // session context in agreement with the account.
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not confirm email change"));
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
    <Box as="main">
      <VStack spacing={6} align="stretch">
        <Heading as="h1" size="lg">
          Account
        </Heading>
        {error && (
          <Alert status="error" role="alert">
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Box as="section">
          <Heading as="h2" size="md" mb={2}>
            Email
          </Heading>
          <Text mb={3} data-testid="account-email">
            {me?.email}
          </Text>
          {!pending ? (
            <Box as="form" onSubmit={onRequestEmailChange}>
              <VStack spacing={4} align="stretch">
                <FormControl>
                  <FormLabel htmlFor="account-email">New email</FormLabel>
                  <Input
                    id="account-email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                  />
                </FormControl>
                <Button type="submit" alignSelf="flex-start" isLoading={busy}>
                  Send verification code
                </Button>
              </VStack>
            </Box>
          ) : (
            <Box as="form" onSubmit={onConfirmEmailChange}>
              <VStack spacing={4} align="stretch">
                <Text mb={3}>
                  A verification code was sent to {pending.pendingEmail}. The
                  address changes only after you confirm; afterwards the old
                  address no longer signs in.
                </Text>
                <FormControl>
                  <FormLabel htmlFor="account-code">Verification code</FormLabel>
                  <Input
                    id="account-code"
                    type="text"
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                  />
                </FormControl>
                <Button type="submit" alignSelf="flex-start" isLoading={busy}>
                  Confirm email change
                </Button>
              </VStack>
            </Box>
          )}
        </Box>
        <Box as="section">
          <Heading as="h2" size="md" mb={2}>
            Calendar
          </Heading>
          <VStack spacing={3} align="stretch">
            {icalUrl && (
              <>
                <Code p={2} borderRadius="base" wordBreak="break-all">
                  {icalUrl}
                </Code>
                <Button size="sm" variant="outline" alignSelf="flex-start" onClick={() => void onCopy()}>
                  Copy
                </Button>
              </>
            )}
            <Button
              size="sm"
              variant="outline"
              alignSelf="flex-start"
              onClick={() => void onRegenerate()}
              isLoading={busy}
            >
              Regenerate
            </Button>
          </VStack>
        </Box>
      </VStack>
    </Box>
  );
}

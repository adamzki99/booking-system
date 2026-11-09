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
          <Text mb={3}>{me?.email}</Text>
          <Box as="form" onSubmit={onChangeEmail}>
            <VStack spacing={4} align="stretch">
              <FormControl>
                <FormLabel htmlFor="account-email">Email</FormLabel>
                <Input
                  id="account-email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </FormControl>
              <Button type="submit" alignSelf="flex-start" isLoading={busy}>
                Change email
              </Button>
            </VStack>
          </Box>
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

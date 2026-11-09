import { useState } from "react";
import type { FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import {
  Alert,
  AlertIcon,
  Box,
  Button,
  FormControl,
  FormLabel,
  Heading,
  Input,
  Text,
  VStack,
} from "@chakra-ui/react";
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
    <Box as="main" maxW="md" mx="auto" py={8} px={4}>
      <VStack spacing={6} align="stretch">
        <Heading as="h1" size="lg">
          Booking
        </Heading>
        {codeSent ? (
          <Box as="form" onSubmit={signIn}>
            <VStack spacing={4} align="stretch">
              <Text>
                A login code was sent to {email}. The code is valid for 10 minutes.
              </Text>
              <FormControl>
                <FormLabel htmlFor="code">Code</FormLabel>
                <Input
                  id="code"
                  value={code}
                  onChange={(e) => setCode(e.target.value.toUpperCase())}
                  maxLength={6}
                  autoFocus
                />
              </FormControl>
              <Button type="submit" isLoading={busy} isDisabled={code.length !== 6}>
                Sign in
              </Button>
              {error && (
                <Alert status="error" role="alert">
                  <AlertIcon />
                  {error}
                </Alert>
              )}
            </VStack>
          </Box>
        ) : (
          <Box as="form" onSubmit={requestCodeForEmail}>
            <VStack spacing={4} align="stretch">
              <Text>Sign in with your email — we will send you a one-time code.</Text>
              <FormControl>
                <FormLabel htmlFor="email">Email</FormLabel>
                <Input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoFocus
                />
              </FormControl>
              <Button type="submit" isLoading={busy} isDisabled={!email}>
                Request code
              </Button>
              {error && (
                <Alert status="error" role="alert">
                  <AlertIcon />
                  {error}
                </Alert>
              )}
            </VStack>
          </Box>
        )}
      </VStack>
    </Box>
  );
}

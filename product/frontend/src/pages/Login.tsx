import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import {
  Alert,
  AlertIcon,
  Box,
  Button,
  Card,
  CardBody,
  Flex,
  FormControl,
  FormErrorMessage,
  FormLabel,
  Heading,
  Input,
  Text,
  VStack,
} from "@chakra-ui/react";
import { ApiError, errorMessage } from "../api/client";
import { getAuthConfig, requestCode } from "../api/auth";
import { useSession } from "../auth/SessionContext";

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
  const { login, loginWithQAMode } = useSession();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [codeSent, setCodeSent] = useState(false);
  const [qaMode, setQaMode] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const emailInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let cancelled = false;
    getAuthConfig()
      .then((cfg) => {
        if (!cancelled) {
          setQaMode(cfg.qaMode);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setQaMode(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  function validateEmail(): boolean {
    const trimmed = email.trim();
    if (!trimmed || !isValidEmail(trimmed)) {
      setEmailError(EMAIL_GUIDANCE);
      emailInputRef.current?.focus();
      return false;
    }
    setEmailError(null);
    return true;
  }

  async function requestCodeForEmail(event: FormEvent) {
    event.preventDefault();
    setError(null);
    if (!validateEmail()) {
      return;
    }
    setBusy(true);
    try {
      await requestCode(email.trim());
      setCodeSent(true);
      setEmailError(null);
    } catch (err) {
      setError(friendlyAuthError(err, "We could not send a login code. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await login(email.trim(), code.trim());
      navigate("/", { replace: true });
    } catch (err) {
      setError(friendlyAuthError(err, "We could not sign you in. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  async function signInWithoutCode(event: FormEvent) {
    event.preventDefault();
    setError(null);
    if (!validateEmail()) {
      return;
    }
    setBusy(true);
    try {
      await loginWithQAMode(email.trim());
      navigate("/", { replace: true });
    } catch (err) {
      setError(friendlyAuthError(err, "We could not sign you in. Please try again."));
    } finally {
      setBusy(false);
    }
  }

  const description = qaMode
    ? "Sign in with your email."
    : codeSent
      ? "Enter the code we sent you to finish signing in."
      : "Sign in with your email, we will send you a one-time code.";

  return (
    <Flex minH="100vh" bg="bgCanvas" align="center" justify="center">
      <VStack
        w="full"
        maxW="420px"
        spacing={6}
        align="stretch"
        p={{ base: "24px 16px", lg: "40px 32px" }}
      >
        <VStack spacing={2} align="center" textAlign="center">
          <Box
            w="56px"
            h="56px"
            borderRadius="full"
            bg="avatarBg"
            color="avatarFg"
            display="grid"
            placeItems="center"
            fontSize="2xl"
            fontWeight={700}
            aria-hidden="true"
          >
            B
          </Box>
          <Heading
            as="h1"
            fontSize={{ base: "24px", lg: "28px" }}
            fontWeight={700}
            letterSpacing="-0.01em"
          >
            Booking
          </Heading>
          <Text fontSize={{ base: "14px", lg: "15px" }} color="muted">
            {description}
          </Text>
        </VStack>

        <Card w="full">
          <CardBody>
            <VStack spacing={4} align="stretch">
              {qaMode ? (
                <Box as="form" onSubmit={signInWithoutCode} noValidate>
                  <VStack spacing={4} align="stretch">
                    <FormControl isInvalid={!!emailError}>
                      <FormLabel htmlFor="email">Email</FormLabel>
                      <Input
                        id="email"
                        ref={emailInputRef}
                        type="email"
                        value={email}
                        onChange={(e) => {
                          setEmail(e.target.value);
                          if (emailError) setEmailError(null);
                        }}
                        autoFocus
                      />
                      {emailError && <FormErrorMessage>{emailError}</FormErrorMessage>}
                    </FormControl>
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      w="full"
                      isLoading={busy}
                    >
                      Sign in
                    </Button>
                  </VStack>
                </Box>
              ) : codeSent ? (
                <Box as="form" onSubmit={signIn} noValidate>
                  <VStack spacing={4} align="stretch">
                    <Text>
                      A login code was sent to {email.trim()}. The code is valid for 10 minutes.
                    </Text>
                    <FormControl>
                      <FormLabel htmlFor="code">Code</FormLabel>
                      <Input
                        id="code"
                        value={code}
                        onChange={(e) => setCode(e.target.value.toUpperCase())}
                        maxLength={6}
                        autoComplete="one-time-code"
                        inputMode="text"
                        autoFocus
                      />
                    </FormControl>
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      w="full"
                      isLoading={busy}
                      isDisabled={code.trim().length !== 6}
                    >
                      Sign in
                    </Button>
                  </VStack>
                </Box>
              ) : (
                <Box as="form" onSubmit={requestCodeForEmail} noValidate>
                  <VStack spacing={4} align="stretch">
                    <FormControl isInvalid={!!emailError}>
                      <FormLabel htmlFor="email">Email</FormLabel>
                      <Input
                        id="email"
                        ref={emailInputRef}
                        type="email"
                        value={email}
                        onChange={(e) => {
                          setEmail(e.target.value);
                          if (emailError) setEmailError(null);
                        }}
                        autoFocus
                      />
                      {emailError && <FormErrorMessage>{emailError}</FormErrorMessage>}
                    </FormControl>
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      w="full"
                      isLoading={busy}
                    >
                      Request code
                    </Button>
                  </VStack>
                </Box>
              )}
              {error && (
                <Alert status="error" role="alert">
                  <AlertIcon />
                  {error}
                </Alert>
              )}
            </VStack>
          </CardBody>
        </Card>
      </VStack>
    </Flex>
  );
}

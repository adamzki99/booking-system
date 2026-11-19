import { useEffect, useState } from "react";
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
  FormLabel,
  Heading,
  Input,
  Text,
  VStack,
} from "@chakra-ui/react";
import { errorMessage } from "../api/client";
import { getAuthConfig, requestCode } from "../api/auth";
import { useSession } from "../auth/SessionContext";

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
  const [busy, setBusy] = useState(false);

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

  async function signInWithoutCode(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await loginWithQAMode(email);
      navigate("/", { replace: true });
    } catch (err) {
      setError(errorMessage(err, "sign-in failed"));
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
                <Box as="form" onSubmit={signInWithoutCode}>
                  <VStack spacing={4} align="stretch">
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
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      w="full"
                      isLoading={busy}
                      isDisabled={!email}
                    >
                      Sign in
                    </Button>
                  </VStack>
                </Box>
              ) : codeSent ? (
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
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      w="full"
                      isLoading={busy}
                      isDisabled={code.length !== 6}
                    >
                      Sign in
                    </Button>
                  </VStack>
                </Box>
              ) : (
                <Box as="form" onSubmit={requestCodeForEmail}>
                  <VStack spacing={4} align="stretch">
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
                    <Button
                      type="submit"
                      variant="accent"
                      size="lg"
                      w="full"
                      isLoading={busy}
                      isDisabled={!email}
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

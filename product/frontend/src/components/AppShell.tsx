import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { Box, Button, Container, Flex, Text } from "@chakra-ui/react";
import { useSession } from "../auth/SessionContext";
import { getChrome, type ChromeInfo } from "../api/chrome";

export interface AppShellProps {
  children: ReactNode;
}

export function AppShell({ children }: AppShellProps) {
  const { logout } = useSession();
  const navigate = useNavigate();
  const [drawerOpen, setDrawerOpen] = useState<boolean>(true);
  const [chrome, setChrome] = useState<ChromeInfo>({ header: "", footer: "" });

  useEffect(() => {
    let cancelled = false;
    getChrome()
      .then((info) => {
        if (!cancelled) setChrome(info);
      })
      .catch(() => {
        // Graceful fallback: keep empty content.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  function handleLogout() {
    logout();
    navigate("/login", { replace: true });
  }

  return (
    <Container maxW="40rem" py={4}>
      <Flex direction="column" gap={4}>
        <Box as="header">
          <Text>{chrome.header}</Text>
        </Box>
        <Button
          size="sm"
          variant="outline"
          onClick={() => setDrawerOpen((open) => !open)}
          aria-label="Toggle drawer"
          alignSelf="flex-start"
        >
          Toggle drawer
        </Button>
        {drawerOpen && (
          <Box as="aside" data-testid="drawer" px={3} py={2} bg="gray.50" borderRadius="base">
            <Text>Navigation</Text>
          </Box>
        )}
        <Box as="main">{children}</Box>
        <Box as="footer">
          <Text>{chrome.footer}</Text>
        </Box>
        <Button colorScheme="red" variant="outline" size="sm" onClick={handleLogout} alignSelf="flex-start">
          Log out
        </Button>
      </Flex>
    </Container>
  );
}

export default AppShell;

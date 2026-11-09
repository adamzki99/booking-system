import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { Box, Button, Container, Flex, Text } from "@chakra-ui/react";
import { useSession } from "../auth/SessionContext";
import { getChrome, type ChromeInfo } from "../api/chrome";

export interface AppShellProps {
  children: ReactNode;
}

const REDEPLOY_TICK_MS = 30_000;

/** Formats the time until the next redeploy, or "" when there is no valid time. */
export function formatRedeployCountdown(nextRedeploy: string, now: number): string {
  const target = Date.parse(nextRedeploy);
  if (Number.isNaN(target)) return "";
  const diff = target - now;
  if (diff <= 0) return "Next redeploy due now";
  const totalMinutes = Math.floor(diff / 60_000);
  if (totalMinutes < 1) return "Next redeploy in <1m";
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  const parts: string[] = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  if (days === 0 && minutes > 0) parts.push(`${minutes}m`);
  return `Next redeploy in ${parts.join(" ")}`;
}

function RedeployIndicator({ nextRedeploy }: { nextRedeploy: string }) {
  const [now, setNow] = useState<number>(() => Date.now());
  useEffect(() => {
    if (!nextRedeploy) return;
    const id = window.setInterval(() => setNow(Date.now()), REDEPLOY_TICK_MS);
    return () => window.clearInterval(id);
  }, [nextRedeploy]);

  const label = formatRedeployCountdown(nextRedeploy, now);
  if (!label) return null;
  const target = Date.parse(nextRedeploy);
  return (
    <Text
      fontSize="sm"
      color="gray.600"
      data-testid="redeploy-indicator"
      title={new Date(target).toLocaleString()}
    >
      {label}
    </Text>
  );
}

export function AppShell({ children }: AppShellProps) {
  const { logout } = useSession();
  const navigate = useNavigate();
  const [drawerOpen, setDrawerOpen] = useState<boolean>(true);
  const [chrome, setChrome] = useState<ChromeInfo>({ header: "", footer: "", nextRedeploy: "" });

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
          <RedeployIndicator nextRedeploy={chrome.nextRedeploy} />
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

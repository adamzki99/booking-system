import { useEffect, useState } from "react";
import type { FormEvent, ReactNode } from "react";
import { NavLink, useLocation, useNavigate } from "react-router-dom";
import {
  Avatar,
  Box,
  Button,
  Drawer,
  DrawerContent,
  DrawerOverlay,
  Flex,
  HStack,
  IconButton,
  Input,
  InputGroup,
  InputLeftElement,
  Link,
  Popover,
  PopoverArrow,
  PopoverBody,
  PopoverCloseButton,
  PopoverContent,
  PopoverHeader,
  PopoverTrigger,
  Text,
  useDisclosure,
} from "@chakra-ui/react";
import { useSession } from "../auth/SessionContext";
import type { User } from "../api/auth";
import { getChrome, type ChromeInfo } from "../api/chrome";

export interface AppShellProps {
  children: ReactNode;
}

const REDEPLOY_TICK_MS = 30_000;
const SIDEBAR_WIDTH = "264px";
const DRAWER_WIDTH = "304px";
const CREATE_BOOKING_HREF = "/?create=1";
// Raw max-width query rather than Chakra's base/lg props: jsdom never evaluates
// media queries, so this keeps desktop chrome in the accessibility tree where
// tests can reach it while still hiding it below `lg` in a real browser.
const DESKTOP_ONLY = { "@media (max-width: 61.99em)": { display: "none" } } as const;
// Scrim colour from the reference mockups (primitives cannot express this alpha).
const SCRIM = "rgba(43,29,26,0.5)";

const ROLE_LABELS: Record<User["role"], string> = {
  basic: "Member",
  super: "Super user",
  admin: "Admin",
};

const NAV_ITEMS = [
  { to: "/", label: "Bookings" },
  { to: "/users", label: "Members" },
  { to: "/account", label: "Account" },
] as const;

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

/** Small inline outline icons keep the shell dependency-free. */
function OutlineIcon({ children, size = 20 }: { children: ReactNode; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

const MenuIcon = () => (
  <OutlineIcon>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </OutlineIcon>
);
const SearchIcon = () => (
  <OutlineIcon>
    <circle cx="11" cy="11" r="7" />
    <path d="m20 20-4-4" />
  </OutlineIcon>
);
const BellIcon = () => (
  <OutlineIcon>
    <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" />
    <path d="M13.7 21a2 2 0 0 1-3.4 0" />
  </OutlineIcon>
);
const CloseIcon = () => (
  <OutlineIcon>
    <path d="M6 6l12 12M18 6 6 18" />
  </OutlineIcon>
);
const PlusIcon = () => (
  <OutlineIcon size={18}>
    <path d="M12 5v14M5 12h14" />
  </OutlineIcon>
);

function initials(user: User | null): string {
  if (!user) return "?";
  const base = user.email.split("@")[0] || user.id;
  const parts = base.split(/[._-]+/).filter(Boolean);
  const value = parts.length >= 2 ? `${parts[0][0]}${parts[1][0]}` : base.slice(0, 2);
  return value.toUpperCase() || "?";
}

function BrandLockup({ header, footer, compact = false }: { header: string; footer: string; compact?: boolean }) {
  return (
    <HStack spacing={3} minW={0}>
      <Box
        w="36px"
        h="36px"
        minW="36px"
        borderRadius="sm"
        bg="accent"
        color="white"
        display="grid"
        placeItems="center"
        fontSize="lg"
        fontWeight={700}
        aria-hidden="true"
      >
        {(header || "B").charAt(0).toUpperCase()}
      </Box>
      <Box minW={0}>
        <Text fontSize={compact ? "sm" : "md"} fontWeight={700} color="ink" noOfLines={1}>
          {header || "Bookings"}
        </Text>
        <Text fontSize="xs" color="muted" noOfLines={1}>
          {footer || "Booking system"}
        </Text>
      </Box>
    </HStack>
  );
}

function CreateBookingButton({ onClick }: { onClick: () => void }) {
  return (
    <Button
      leftIcon={<PlusIcon />}
      onClick={onClick}
      variant="accent"
      size="lg"
      minH="48px"
      borderRadius="md"
      w="full"
    >
      Create booking
    </Button>
  );
}

function PagesNav({ onNavigate }: { onNavigate?: () => void }) {
  const location = useLocation();
  const active = (to: string) =>
    to === "/"
      ? location.pathname === "/"
      : location.pathname === to || location.pathname.startsWith(`${to}/`);

  return (
    <Flex as="nav" aria-label="Pages" direction="column" gap={1}>
      {NAV_ITEMS.map((item) => {
        const isActive = active(item.to);
        return (
          <Link
            key={item.to}
            as={NavLink}
            to={item.to}
            onClick={onNavigate}
            aria-current={isActive ? "page" : undefined}
            display="flex"
            alignItems="center"
            minH="44px"
            px={3}
            borderRadius="sm"
            bg={isActive ? "accentTint" : "transparent"}
            color={isActive ? "accentHover" : "ink"}
            fontWeight={isActive ? 600 : 500}
            _hover={{ bg: isActive ? "accentTint" : "bgHover", textDecoration: "none" }}
          >
            {item.label}
          </Link>
        );
      })}
    </Flex>
  );
}

function MemberFooter({ user, onLogout }: { user: User | null; onLogout: () => void }) {
  return (
    <Box mt="auto" borderTop="1px solid" borderColor="line" pt={4}>
      <HStack spacing={3} mb={3}>
        <Avatar name={initials(user)} size="md" />
        <Box minW={0}>
          <Text fontSize="sm" fontWeight={600} color="ink" noOfLines={1}>
            {user?.email ?? "Not signed in"}
          </Text>
          <Text fontSize="xs" color="muted">
            {user ? ROLE_LABELS[user.role] : "Signed out"}
          </Text>
        </Box>
      </HStack>
      <Button variant="accentOutline" size="sm" w="full" onClick={onLogout}>
        Log out
      </Button>
    </Box>
  );
}

export function AppShell({ children }: AppShellProps) {
  const { user, logout } = useSession();
  const navigate = useNavigate();
  const location = useLocation();
  const { isOpen, onOpen, onClose } = useDisclosure();
  const [chrome, setChrome] = useState<ChromeInfo>({ header: "", footer: "", nextRedeploy: "" });
  const [search, setSearch] = useState("");

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

  const onBookingsPage = location.pathname === "/";
  const onMembersPage =
    location.pathname === "/users" || location.pathname.startsWith("/users/");
  const showShellCreate = !onBookingsPage;
  const showGlobalSearch = !onMembersPage;

  function handleLogout() {
    logout();
    navigate("/login", { replace: true });
  }

  function handleCreateBooking() {
    onClose();
    navigate(CREATE_BOOKING_HREF);
  }

  function usersLink(query: string) {
    const trimmed = query.trim();
    return trimmed ? `/users?q=${encodeURIComponent(trimmed)}` : "/users";
  }

  function handleSearchSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    navigate(usersLink(search));
  }

  return (
    <Flex minH="100vh" bg="bgCanvas" direction="column">
      <Flex direction="row" flex="1" minH={0}>
        {/* Persistent desktop sidebar */}
        <Box
          as="aside"
          display="flex"
          sx={DESKTOP_ONLY}
          w={SIDEBAR_WIDTH}
          minW={SIDEBAR_WIDTH}
          bg="surface"
          borderRight="1px solid"
          borderColor="line"
          p="20px 16px"
          flexDirection="column"
        >
          <BrandLockup header={chrome.header} footer={chrome.footer} />
          {showShellCreate && (
            <Box mt={6}>
              <CreateBookingButton onClick={handleCreateBooking} />
            </Box>
          )}
          <Box mt={showShellCreate ? 6 : 8}>
            <PagesNav />
          </Box>
          <MemberFooter user={user} onLogout={handleLogout} />
        </Box>

        {/* Main column: shared responsive top bar + page content */}
        <Flex direction="column" flex="1" minW={0}>
          <Flex
            as="header"
            h={{ base: "64px", lg: "72px" }}
            px={{ base: 2, lg: 8 }}
            bg="surface"
            borderBottom="1px solid"
            borderColor="line"
            align="center"
            justify="space-between"
            gap={3}
          >
            <HStack spacing={2} minW={0}>
              <IconButton
                aria-label="Open menu"
                icon={<MenuIcon />}
                variant="icon"
                onClick={onOpen}
                display={{ base: "inline-flex", lg: "none" }}
              />
              <Box display={{ base: "block", lg: "none" }} minW={0}>
                <BrandLockup header={chrome.header} footer={chrome.footer} compact />
              </Box>
              {showGlobalSearch && (
                <Box
                  as="form"
                  onSubmit={handleSearchSubmit}
                  sx={DESKTOP_ONLY}
                  w="420px"
                  maxW="420px"
                >
                  <InputGroup>
                    <InputLeftElement pointerEvents="none">
                      <SearchIcon />
                    </InputLeftElement>
                    <Input
                      aria-label="Search members"
                      placeholder="Search members"
                      value={search}
                      onChange={(event) => setSearch(event.target.value)}
                      bg="bgSubtle"
                      borderRadius="md"
                      minH="44px"
                    />
                  </InputGroup>
                </Box>
              )}
            </HStack>
            <HStack spacing={2}>
              <RedeployIndicator nextRedeploy={chrome.nextRedeploy} />
              {showGlobalSearch && (
                <IconButton
                  aria-label="Search members"
                  icon={<SearchIcon />}
                  variant="icon"
                  onClick={() => navigate(usersLink(search))}
                  display={{ base: "inline-flex", lg: "none" }}
                />
              )}
              <Popover placement="bottom-end">
                <PopoverTrigger>
                  <IconButton aria-label="Notifications" icon={<BellIcon />} variant="icon" />
                </PopoverTrigger>
                <PopoverContent w="280px">
                  <PopoverArrow />
                  <PopoverCloseButton />
                  <PopoverHeader fontWeight={600}>Notifications</PopoverHeader>
                  <PopoverBody>
                    <Text fontSize="sm" color="muted">
                      No notifications yet.
                    </Text>
                  </PopoverBody>
                </PopoverContent>
              </Popover>
              <Avatar name={initials(user)} size="sm" sx={DESKTOP_ONLY} />
            </HStack>
          </Flex>

          <Box
            as="main"
            flex="1"
            px={{ base: 4, lg: 8 }}
            py={{ base: 4, lg: 6 }}
            pb={{ base: showShellCreate ? "96px" : 6, lg: 6 }}
          >
            {children}
          </Box>
        </Flex>
      </Flex>

      {/* Mobile bottom CTA dock */}
      {showShellCreate && (
        <Box
          display={{ base: "flex", lg: "none" }}
          position="fixed"
          bottom={0}
          left={0}
          right={0}
          bg="surface"
          borderTop="1px solid"
          borderColor="line"
          px={4}
          pt={3}
          pb={4}
          zIndex="docked"
        >
          <CreateBookingButton onClick={handleCreateBooking} />
        </Box>
      )}

      {/* Mobile slide-over menu */}
      <Drawer isOpen={isOpen} onClose={onClose} placement="left">
        <DrawerOverlay bg={SCRIM} />
        <DrawerContent data-testid="drawer" w={DRAWER_WIDTH} maxW={DRAWER_WIDTH} bg="surface" overflow="visible">
          <IconButton
            aria-label="Close menu"
            icon={<CloseIcon />}
            variant="icon"
            borderRadius="full"
            position="absolute"
            left="316px"
            top="12px"
            zIndex={2}
            bg="surface"
            onClick={onClose}
          />
          <Flex direction="column" h="100%" p="20px 16px">
            <BrandLockup header={chrome.header} footer={chrome.footer} />
            {showShellCreate && (
              <Box mt={6}>
                <CreateBookingButton onClick={handleCreateBooking} />
              </Box>
            )}
            <Box mt={showShellCreate ? 6 : 8}>
              <PagesNav onNavigate={onClose} />
            </Box>
            <MemberFooter user={user} onLogout={handleLogout} />
          </Flex>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}

export default AppShell;

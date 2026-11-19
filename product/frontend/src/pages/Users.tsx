import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Alert,
  AlertIcon,
  Avatar,
  Badge,
  Box,
  Button,
  Card,
  CardBody,
  CardHeader,
  FormControl,
  FormLabel,
  Heading,
  Input,
  Select,
  SimpleGrid,
  Table,
  Tbody,
  Textarea,
  Th,
  Thead,
  Tr,
  Td,
  VStack,
} from "@chakra-ui/react";
import { errorMessage } from "../api/client";
import type { User } from "../api/auth";
import { listUsers, addUser, removeUser, changeUserAddress, changeUserRole } from "../api/users";
import { blockTimePeriod } from "../api/bookings";
import { broadcastMessage } from "../api/broadcast";
import { useSession } from "../auth/SessionContext";
import PageHeader from "../components/PageHeader";

function isSuper(user: User | null): boolean {
  return user?.role === "super" || user?.role === "admin";
}

function isAdmin(user: User | null): boolean {
  return user?.role === "admin";
}

/** Initials for the member avatar badge, derived from the email local part. */
function initials(email: string): string {
  const local = email.split("@")[0] || email;
  const parts = local.split(/[._-]+/).filter(Boolean);
  const value = parts.length >= 2 ? `${parts[0][0]}${parts[1][0]}` : local.slice(0, 2);
  return value.toUpperCase() || "?";
}

export default function Users() {
  const { user } = useSession();
  const [users, setUsers] = useState<User[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [searchParams, setSearchParams] = useSearchParams();
  const query = searchParams.get("q") ?? "";

  // add user form
  const [newEmail, setNewEmail] = useState("");
  const [newAddress, setNewAddress] = useState("");

  // change address
  const [addressUserId, setAddressUserId] = useState("");
  const [addressValue, setAddressValue] = useState("");

  // change role (admin only)
  const [roleUserId, setRoleUserId] = useState("");
  const [roleValue, setRoleValue] = useState("basic");

  // block period
  const [blockStart, setBlockStart] = useState("");
  const [blockEnd, setBlockEnd] = useState("");

  // broadcast
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");

  const superUser = isSuper(user);
  const adminUser = isAdmin(user);

  // Only the directory rows are filtered. Management selects keep using the
  // complete `users` list so their options stay usable during a search.
  const searchTerm = query.trim().toLowerCase();
  const visibleUsers = searchTerm
    ? users.filter((u) =>
        [u.email, u.address ?? "", u.role].some((value) =>
          value.toLowerCase().includes(searchTerm),
        ),
      )
    : users;

  function updateQuery(value: string) {
    const params = new URLSearchParams(searchParams);
    const trimmed = value.trim();
    if (trimmed) params.set("q", trimmed);
    else params.delete("q");
    setSearchParams(params, { replace: true });
  }

  async function refresh() {
    try {
      setUsers(await listUsers());
      setError(null);
    } catch (err) {
      setError(errorMessage(err, "could not load users"));
    }
  }

  useEffect(() => {
    void refresh();
  }, []);

  async function onAddUser(event: FormEvent) {
    event.preventDefault();
    try {
      await addUser({ email: newEmail, address: newAddress });
      setNewEmail("");
      setNewAddress("");
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not add user"));
    }
  }

  async function onRemove(id: string) {
    try {
      await removeUser(id);
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not remove user"));
    }
  }

  async function onChangeAddress(event: FormEvent) {
    event.preventDefault();
    try {
      await changeUserAddress(addressUserId, addressValue);
      setAddressUserId("");
      setAddressValue("");
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not change address"));
    }
  }

  async function onChangeRole(event: FormEvent) {
    event.preventDefault();
    try {
      await changeUserRole(roleUserId, roleValue);
      setRoleUserId("");
      setRoleValue("basic");
      await refresh();
    } catch (err) {
      setError(errorMessage(err, "could not change role"));
    }
  }

  async function onBlock(event: FormEvent) {
    event.preventDefault();
    try {
      await blockTimePeriod({
        start: new Date(blockStart).toISOString(),
        end: new Date(blockEnd).toISOString(),
      });
      setBlockStart("");
      setBlockEnd("");
    } catch (err) {
      setError(errorMessage(err, "could not block period"));
    }
  }

  async function onBroadcast(event: FormEvent) {
    event.preventDefault();
    try {
      await broadcastMessage({ subject, body });
      setSubject("");
      setBody("");
    } catch (err) {
      setError(errorMessage(err, "could not broadcast"));
    }
  }

  return (
    <Box as="main" maxW="1040px" mx="auto" w="full">
      <VStack spacing={6} align="stretch">
        <PageHeader
          title="User directory"
          subtitle="Search, review and manage the members of your booking system."
        />

        {error && (
          <Alert status="error" role="alert">
            <AlertIcon />
            {error}
          </Alert>
        )}

        <FormControl maxW="420px">
          <FormLabel htmlFor="member-search">Search members</FormLabel>
          <Input
            id="member-search"
            value={query}
            onChange={(event) => updateQuery(event.target.value)}
            placeholder="Search members"
          />
        </FormControl>

        <Card>
          <CardHeader pb={0}>
            <Heading as="h2" fontSize="17px" fontWeight={700}>
              Members
            </Heading>
          </CardHeader>
          <CardBody px={0} pb={0}>
            <Box overflowX="auto">
              <Table size="sm" variant="simple">
                <Thead>
                  <Tr>
                    <Th>Member</Th>
                    <Th>Email</Th>
                    <Th>Role</Th>
                    <Th>Address</Th>
                    <Th>Active</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {visibleUsers.map((u) => (
                    <Tr key={u.id}>
                      <Td>
                        <Box aria-hidden="true">
                          <Avatar
                            name={u.email}
                            getInitials={() => initials(u.email)}
                            size="sm"
                            boxSize="40px"
                          />
                        </Box>
                      </Td>
                      <Td fontSize="15px" fontWeight={600}>
                        {u.email}
                      </Td>
                      <Td>
                        <Badge colorScheme="brand">{u.role}</Badge>
                      </Td>
                      <Td fontSize="13px" color="muted">
                        {u.address}
                      </Td>
                      <Td>{String(u.active)}</Td>
                      {superUser && (u.role === "basic" || (adminUser && u.role === "super")) && (
                        <Td>
                          <Button
                            size="xs"
                            colorScheme="red"
                            variant="outline"
                            onClick={() => void onRemove(u.id)}
                          >
                            Remove
                          </Button>
                        </Td>
                      )}
                    </Tr>
                  ))}
                </Tbody>
              </Table>
            </Box>
          </CardBody>
        </Card>

        {superUser && (
          <SimpleGrid as="section" columns={{ base: 1, lg: 2 }} spacing={6}>
            <Card as="form" onSubmit={onAddUser}>
              <CardHeader pb={0}>
                <Heading as="h2" fontSize="17px" fontWeight={700}>
                  Add user
                </Heading>
              </CardHeader>
              <CardBody>
                <VStack spacing={4} align="stretch">
                  <FormControl>
                    <FormLabel htmlFor="new-email">Email</FormLabel>
                    <Input
                      id="new-email"
                      value={newEmail}
                      onChange={(e) => setNewEmail(e.target.value)}
                    />
                  </FormControl>
                  <FormControl>
                    <FormLabel htmlFor="new-address">Address</FormLabel>
                    <Input
                      id="new-address"
                      value={newAddress}
                      onChange={(e) => setNewAddress(e.target.value)}
                    />
                  </FormControl>
                  <Button type="submit" variant="accent" size="lg" alignSelf="flex-start">
                    Add user
                  </Button>
                </VStack>
              </CardBody>
            </Card>

            <Card as="form" onSubmit={onChangeAddress}>
              <CardHeader pb={0}>
                <Heading as="h2" fontSize="17px" fontWeight={700}>
                  Change address
                </Heading>
              </CardHeader>
              <CardBody>
                <VStack spacing={4} align="stretch">
                  <FormControl>
                    <FormLabel htmlFor="address-user-id">User id</FormLabel>
                    <Select
                      id="address-user-id"
                      aria-label="User"
                      value={addressUserId}
                      onChange={(e) => setAddressUserId(e.target.value)}
                    >
                      {users
                        .filter((u) => u.role === "basic")
                        .map((u) => (
                          <option key={u.id} value={u.id}>
                            {u.email}
                          </option>
                        ))}
                    </Select>
                  </FormControl>
                  <FormControl>
                    <FormLabel htmlFor="address-value">Address</FormLabel>
                    <Input
                      id="address-value"
                      value={addressValue}
                      onChange={(e) => setAddressValue(e.target.value)}
                    />
                  </FormControl>
                  <Button type="submit" variant="accent" size="lg" alignSelf="flex-start">
                    Change address
                  </Button>
                </VStack>
              </CardBody>
            </Card>

            {adminUser && (
              <Card as="form" onSubmit={onChangeRole}>
                <CardHeader pb={0}>
                  <Heading as="h2" fontSize="17px" fontWeight={700}>
                    Change role (admin)
                  </Heading>
                </CardHeader>
                <CardBody>
                  <VStack spacing={4} align="stretch">
                    <FormControl>
                      <FormLabel htmlFor="role-user-id">User id</FormLabel>
                      <Select
                        id="role-user-id"
                        aria-label="User"
                        value={roleUserId}
                        onChange={(e) => setRoleUserId(e.target.value)}
                      >
                        {users
                          .filter((u) => u.id !== user?.id)
                          .map((u) => (
                            <option key={u.id} value={u.id}>
                              {u.email}
                            </option>
                          ))}
                      </Select>
                    </FormControl>
                    <FormControl>
                      <FormLabel htmlFor="role-value">Role</FormLabel>
                      <Select
                        id="role-value"
                        value={roleValue}
                        onChange={(e) => setRoleValue(e.target.value)}
                      >
                        <option value="basic">basic</option>
                        <option value="super">super</option>
                        <option value="admin">admin</option>
                      </Select>
                    </FormControl>
                    <Button type="submit" variant="accent" size="lg" alignSelf="flex-start">
                      Change role
                    </Button>
                  </VStack>
                </CardBody>
              </Card>
            )}

            <Card as="form" onSubmit={onBlock}>
              <CardHeader pb={0}>
                <Heading as="h2" fontSize="17px" fontWeight={700}>
                  Block time period
                </Heading>
              </CardHeader>
              <CardBody>
                <VStack spacing={4} align="stretch">
                  <FormControl>
                    <FormLabel htmlFor="block-start">Start</FormLabel>
                    <Input
                      id="block-start"
                      type="datetime-local"
                      value={blockStart}
                      onChange={(e) => setBlockStart(e.target.value)}
                    />
                  </FormControl>
                  <FormControl>
                    <FormLabel htmlFor="block-end">End</FormLabel>
                    <Input
                      id="block-end"
                      type="datetime-local"
                      value={blockEnd}
                      onChange={(e) => setBlockEnd(e.target.value)}
                    />
                  </FormControl>
                  <Button type="submit" variant="accent" size="lg" alignSelf="flex-start">
                    Block
                  </Button>
                </VStack>
              </CardBody>
            </Card>

            <Card as="form" onSubmit={onBroadcast}>
              <CardHeader pb={0}>
                <Heading as="h2" fontSize="17px" fontWeight={700}>
                  Broadcast message
                </Heading>
              </CardHeader>
              <CardBody>
                <VStack spacing={4} align="stretch">
                  <FormControl>
                    <FormLabel htmlFor="broadcast-subject">Subject</FormLabel>
                    <Input
                      id="broadcast-subject"
                      value={subject}
                      onChange={(e) => setSubject(e.target.value)}
                    />
                  </FormControl>
                  <FormControl>
                    <FormLabel htmlFor="broadcast-body">Body</FormLabel>
                    <Textarea
                      id="broadcast-body"
                      value={body}
                      onChange={(e) => setBody(e.target.value)}
                    />
                  </FormControl>
                  <Button type="submit" variant="accent" size="lg" alignSelf="flex-start">
                    Broadcast
                  </Button>
                </VStack>
              </CardBody>
            </Card>
          </SimpleGrid>
        )}
      </VStack>
    </Box>
  );
}

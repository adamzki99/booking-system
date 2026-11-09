import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import {
  Alert,
  AlertIcon,
  Box,
  Button,
  FormControl,
  FormLabel,
  Heading,
  Input,
  Select,
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

function isSuper(user: User | null): boolean {
  return user?.role === "super" || user?.role === "admin";
}

function isAdmin(user: User | null): boolean {
  return user?.role === "admin";
}

export default function Users() {
  const { user } = useSession();
  const [users, setUsers] = useState<User[]>([]);
  const [error, setError] = useState<string | null>(null);

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
    <Box as="main">
      <VStack spacing={6} align="stretch">
        <Heading as="h1" size="lg">
          User directory
        </Heading>
        {error && (
          <Alert status="error" role="alert">
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Box overflowX="auto">
          <Table size="sm" variant="simple">
            <Thead>
              <Tr>
                <Th>Email</Th>
                <Th>Role</Th>
                <Th>Address</Th>
                <Th>Active</Th>
              </Tr>
            </Thead>
            <Tbody>
              {users.map((u) => (
                <Tr key={u.id}>
                  <Td>{u.email}</Td>
                  <Td>{u.role}</Td>
                  <Td>{u.address}</Td>
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

        {superUser && (
          <VStack as="section" spacing={6} align="stretch">
            <Box as="form" onSubmit={onAddUser}>
              <VStack spacing={4} align="stretch">
                <Heading as="h2" size="md">
                  Add user
                </Heading>
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
                <Button type="submit" alignSelf="flex-start">
                  Add user
                </Button>
              </VStack>
            </Box>

            <Box as="form" onSubmit={onChangeAddress}>
              <VStack spacing={4} align="stretch">
                <Heading as="h2" size="md">
                  Change address
                </Heading>
                <FormControl>
                  <FormLabel htmlFor="address-user-id">User id</FormLabel>
                  <Input
                    id="address-user-id"
                    value={addressUserId}
                    onChange={(e) => setAddressUserId(e.target.value)}
                  />
                </FormControl>
                <FormControl>
                  <FormLabel htmlFor="address-value">Address</FormLabel>
                  <Input
                    id="address-value"
                    value={addressValue}
                    onChange={(e) => setAddressValue(e.target.value)}
                  />
                </FormControl>
                <Button type="submit" alignSelf="flex-start">
                  Change address
                </Button>
              </VStack>
            </Box>

            {adminUser && (
              <Box as="form" onSubmit={onChangeRole}>
                <VStack spacing={4} align="stretch">
                  <Heading as="h2" size="md">
                    Change role (admin)
                  </Heading>
                  <FormControl>
                    <FormLabel htmlFor="role-user-id">User id</FormLabel>
                    <Input
                      id="role-user-id"
                      value={roleUserId}
                      onChange={(e) => setRoleUserId(e.target.value)}
                    />
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
                  <Button type="submit" alignSelf="flex-start">
                    Change role
                  </Button>
                </VStack>
              </Box>
            )}

            <Box as="form" onSubmit={onBlock}>
              <VStack spacing={4} align="stretch">
                <Heading as="h2" size="md">
                  Block time period
                </Heading>
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
                <Button type="submit" alignSelf="flex-start">
                  Block
                </Button>
              </VStack>
            </Box>

            <Box as="form" onSubmit={onBroadcast}>
              <VStack spacing={4} align="stretch">
                <Heading as="h2" size="md">
                  Broadcast message
                </Heading>
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
                <Button type="submit" alignSelf="flex-start">
                  Broadcast
                </Button>
              </VStack>
            </Box>
          </VStack>
        )}
      </VStack>
    </Box>
  );
}

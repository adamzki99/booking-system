import { useEffect, useState } from "react";
import type { FormEvent } from "react";
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
    <main>
      <h1>User directory</h1>
      {error && <p role="alert">{error}</p>}
      <table>
        <thead>
          <tr>
            <th>Email</th>
            <th>Role</th>
            <th>Address</th>
            <th>Active</th>
          </tr>
        </thead>
        <tbody>
          {users.map((u) => (
            <tr key={u.id}>
              <td>{u.email}</td>
              <td>{u.role}</td>
              <td>{u.address}</td>
              <td>{String(u.active)}</td>
              {superUser && (u.role === "basic" || (adminUser && u.role === "super")) && (
                <td>
                  <button type="button" onClick={() => void onRemove(u.id)}>
                    Remove
                  </button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>

      {superUser && (
        <section>
          <h2>Add user</h2>
          <form onSubmit={onAddUser}>
            <label>
              Email
              <input value={newEmail} onChange={(e) => setNewEmail(e.target.value)} required />
            </label>
            <label>
              Address
              <input value={newAddress} onChange={(e) => setNewAddress(e.target.value)} required />
            </label>
            <button type="submit">Add user</button>
          </form>

          <h2>Change address</h2>
          <form onSubmit={onChangeAddress}>
            <label>
              User id
              <input value={addressUserId} onChange={(e) => setAddressUserId(e.target.value)} required />
            </label>
            <label>
              Address
              <input value={addressValue} onChange={(e) => setAddressValue(e.target.value)} required />
            </label>
            <button type="submit">Change address</button>
          </form>

          {adminUser && (
            <>
              <h2>Change role (admin)</h2>
              <form onSubmit={onChangeRole}>
                <label>
                  User id
                  <input value={roleUserId} onChange={(e) => setRoleUserId(e.target.value)} required />
                </label>
                <label>
                  Role
                  <select value={roleValue} onChange={(e) => setRoleValue(e.target.value)}>
                    <option value="basic">basic</option>
                    <option value="super">super</option>
                    <option value="admin">admin</option>
                  </select>
                </label>
                <button type="submit">Change role</button>
              </form>
            </>
          )}

          <h2>Block time period</h2>
          <form onSubmit={onBlock}>
            <label>
              Start
              <input type="datetime-local" value={blockStart} onChange={(e) => setBlockStart(e.target.value)} required />
            </label>
            <label>
              End
              <input type="datetime-local" value={blockEnd} onChange={(e) => setBlockEnd(e.target.value)} required />
            </label>
            <button type="submit">Block</button>
          </form>

          <h2>Broadcast message</h2>
          <form onSubmit={onBroadcast}>
            <label>
              Subject
              <input value={subject} onChange={(e) => setSubject(e.target.value)} required />
            </label>
            <label>
              Body
              <textarea value={body} onChange={(e) => setBody(e.target.value)} required />
            </label>
            <button type="submit">Broadcast</button>
          </form>
        </section>
      )}
    </main>
  );
}

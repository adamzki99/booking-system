import { For, Show, createSignal } from "solid-js";
import { useSearchParams } from "@solidjs/router";
import { Errored, Loading, action, createAsyncData, refresh } from "../data";
import type { User } from "../api/auth";
import { addUser, changeUserAddress, changeUserRole, listUsers, removeUser } from "../api/users";
import { blockTimePeriod } from "../api/bookings";
import { broadcastMessage } from "../api/broadcast";
import { errorMessage } from "../api/client";
import { useSession } from "../auth/SessionContext";
import PageHeader from "../components/PageHeader";
import Alert from "../ui/Alert";
import Avatar from "../ui/Avatar";
import Button from "../ui/Button";
import Card from "../ui/Card";
import CardBody from "../ui/CardBody";
import CardHeader from "../ui/CardHeader";
import Input from "../ui/Input";
import Select from "../ui/Select";
import Textarea from "../ui/Textarea";
import "./Users.css";

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
  const session = useSession();
  const [searchParams, setSearchParams] = useSearchParams();

  const [mutationError, setMutationError] = createSignal<string | null>(null);

  // add user form
  const [newEmail, setNewEmail] = createSignal("");
  const [newAddress, setNewAddress] = createSignal("");

  // change address
  const [addressUserId, setAddressUserId] = createSignal("");
  const [addressValue, setAddressValue] = createSignal("");

  // change role (admin only)
  const [roleUserId, setRoleUserId] = createSignal("");
  const [roleValue, setRoleValue] = createSignal("basic");

  // block period
  const [blockStart, setBlockStart] = createSignal("");
  const [blockEnd, setBlockEnd] = createSignal("");

  // broadcast
  const [subject, setSubject] = createSignal("");
  const [body, setBody] = createSignal("");

  const usersData = createAsyncData<User[]>(() => listUsers());

  const superUser = () => isSuper(session.user());
  const adminUser = () => isAdmin(session.user());

  const query = () => (typeof searchParams.q === "string" ? searchParams.q : "");

  // Only the directory rows are filtered. Management selects keep using the
  // complete `users` list so their options stay usable during a search.
  const visibleUsers = () => {
    const users = (usersData() as User[] | undefined) ?? [];
    const searchTerm = query().trim().toLowerCase();
    if (!searchTerm) return users;
    return users.filter((u) =>
      [u.email, u.address ?? "", u.role].some((value) => value.toLowerCase().includes(searchTerm)),
    );
  };

  const allUsers = () => (usersData() as User[] | undefined) ?? [];

  function updateQuery(value: string) {
    const trimmed = value.trim();
    setSearchParams({ q: trimmed || undefined }, { replace: true });
  }

  // oxlint-disable-next-line solid/reactivity -- action handler reads signals only on user invocation
  const onAddUser = action(function* (event: Event) {
    event.preventDefault();
    try {
      yield addUser({ email: newEmail(), address: newAddress() });
      setNewEmail("");
      setNewAddress("");
      setMutationError(null);
      yield refresh(usersData);
    } catch (err) {
      setMutationError(errorMessage(err, "could not add user"));
    }
  });

  const onRemove = action(function* (id: string) {
    try {
      yield removeUser(id);
      setMutationError(null);
      yield refresh(usersData);
    } catch (err) {
      setMutationError(errorMessage(err, "could not remove user"));
    }
  });

  // oxlint-disable-next-line solid/reactivity -- action handler reads signals only on user invocation
  const onChangeAddress = action(function* (event: Event) {
    event.preventDefault();
    try {
      yield changeUserAddress(addressUserId(), addressValue());
      setAddressUserId("");
      setAddressValue("");
      setMutationError(null);
      yield refresh(usersData);
    } catch (err) {
      setMutationError(errorMessage(err, "could not change address"));
    }
  });

  // oxlint-disable-next-line solid/reactivity -- action handler reads signals only on user invocation
  const onChangeRole = action(function* (event: Event) {
    event.preventDefault();
    try {
      yield changeUserRole(roleUserId(), roleValue());
      setRoleUserId("");
      setRoleValue("basic");
      setMutationError(null);
      yield refresh(usersData);
    } catch (err) {
      setMutationError(errorMessage(err, "could not change role"));
    }
  });

  // oxlint-disable-next-line solid/reactivity -- action handler reads signals only on user invocation
  const onBlock = action(function* (event: Event) {
    event.preventDefault();
    try {
      yield blockTimePeriod({
        start: new Date(blockStart()).toISOString(),
        end: new Date(blockEnd()).toISOString(),
      });
      setBlockStart("");
      setBlockEnd("");
      setMutationError(null);
    } catch (err) {
      setMutationError(errorMessage(err, "could not block period"));
    }
  });

  // oxlint-disable-next-line solid/reactivity -- action handler reads signals only on user invocation
  const onBroadcast = action(function* (event: Event) {
    event.preventDefault();
    try {
      yield broadcastMessage({ subject: subject(), body: body() });
      setSubject("");
      setBody("");
      setMutationError(null);
    } catch (err) {
      setMutationError(errorMessage(err, "could not broadcast"));
    }
  });

  return (
    <div class="users-page">
      <div class="users-stack">
        <PageHeader
          title="User directory"
          subtitle="Search, review and manage the members of your booking system."
        />

        <Loading fallback={<p class="users-loading">Loading users...</p>}>
          <Errored
            fallback={(err, reset) => (
              <Alert status="error">
                <div class="users-error-fallback">
                  <span>{errorMessage(err, "could not load users")}</span>
                  <Button variant="accentOutline" size="sm" onClick={() => reset()}>
                    Retry
                  </Button>
                </div>
              </Alert>
            )}
          >
            <Show when={mutationError()}>{(msg) => <Alert status="error">{msg()}</Alert>}</Show>

            <div class="users-field users-search">
              {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
              <label class="users-label" for="member-search">
                Search members
              </label>
              <Input
                id="member-search"
                value={query()}
                onInput={(e) => updateQuery(e.currentTarget.value)}
                placeholder="Search members"
              />
            </div>

            <Card>
              <CardHeader class="users-card-header">
                <h2 class="users-section-title">Members</h2>
              </CardHeader>
              <CardBody class="users-table-card-body">
                <div class="users-table-wrap">
                  <table class="users-table">
                    <thead>
                      <tr>
                        <th>Member</th>
                        <th>Email</th>
                        <th>Role</th>
                        <th>Address</th>
                        <th>Active</th>
                        <Show when={superUser()}>
                          <th>
                            <span class="users-visually-hidden">Actions</span>
                          </th>
                        </Show>
                      </tr>
                    </thead>
                    <tbody>
                      <For each={visibleUsers()} keyed={(u) => u.id}>
                        {(u) => (
                          <tr>
                            <td>
                              <div aria-hidden="true">
                                <Avatar
                                  name={u().email}
                                  getInitials={() => initials(u().email)}
                                  size="sm"
                                />
                              </div>
                            </td>
                            <td class="users-email">{u().email}</td>
                            <td>
                              <span class="users-badge">{u().role}</span>
                            </td>
                            <td class="users-muted">{u().address}</td>
                            <td>{String(u().active)}</td>
                            <Show when={superUser()}>
                              {/* oxlint-disable-next-line jsx-a11y/control-has-associated-label -- false positive on td element */}
                              <td>
                                <Show
                                  when={
                                    u().role === "basic" || (adminUser() && u().role === "super")
                                  }
                                >
                                  <Button
                                    size="sm"
                                    variant="accentOutline"
                                    class="users-remove-btn"
                                    onClick={() => void onRemove(u().id)}
                                  >
                                    Remove
                                  </Button>
                                </Show>
                              </td>
                            </Show>
                          </tr>
                        )}
                      </For>
                    </tbody>
                  </table>
                </div>
              </CardBody>
            </Card>

            <Show when={superUser()}>
              <section class="users-management-grid">
                <Card>
                  <form onSubmit={onAddUser}>
                    <CardHeader class="users-card-header">
                      <h2 class="users-section-title">Add user</h2>
                    </CardHeader>
                    <CardBody>
                      <div class="users-form-stack">
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="new-email">
                            Email
                          </label>
                          <Input
                            id="new-email"
                            value={newEmail()}
                            onInput={(e) => setNewEmail(e.currentTarget.value)}
                          />
                        </div>
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="new-address">
                            Address
                          </label>
                          <Input
                            id="new-address"
                            value={newAddress()}
                            onInput={(e) => setNewAddress(e.currentTarget.value)}
                          />
                        </div>
                        <Button type="submit" variant="accent" size="lg" class="users-submit">
                          Add user
                        </Button>
                      </div>
                    </CardBody>
                  </form>
                </Card>

                <Card>
                  <form onSubmit={onChangeAddress}>
                    <CardHeader class="users-card-header">
                      <h2 class="users-section-title">Change address</h2>
                    </CardHeader>
                    <CardBody>
                      <div class="users-form-stack">
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="address-user-id">
                            User id
                          </label>
                          <Select
                            id="address-user-id"
                            aria-label="User"
                            value={addressUserId()}
                            onInput={(e) => setAddressUserId(e.currentTarget.value)}
                          >
                            <For
                              each={allUsers().filter((u) => u.role === "basic")}
                              keyed={(u) => u.id}
                            >
                              {(u) => <option value={u().id}>{u().email}</option>}
                            </For>
                          </Select>
                        </div>
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="address-value">
                            Address
                          </label>
                          <Input
                            id="address-value"
                            value={addressValue()}
                            onInput={(e) => setAddressValue(e.currentTarget.value)}
                          />
                        </div>
                        <Button type="submit" variant="accent" size="lg" class="users-submit">
                          Change address
                        </Button>
                      </div>
                    </CardBody>
                  </form>
                </Card>

                <Show when={adminUser()}>
                  <Card>
                    <form onSubmit={onChangeRole}>
                      <CardHeader class="users-card-header">
                        <h2 class="users-section-title">Change role (admin)</h2>
                      </CardHeader>
                      <CardBody>
                        <div class="users-form-stack">
                          <div class="users-field">
                            {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                            <label class="users-label" for="role-user-id">
                              User id
                            </label>
                            <Select
                              id="role-user-id"
                              aria-label="User"
                              value={roleUserId()}
                              onInput={(e) => setRoleUserId(e.currentTarget.value)}
                            >
                              <For
                                each={allUsers().filter((u) => u.id !== session.user()?.id)}
                                keyed={(u) => u.id}
                              >
                                {(u) => <option value={u().id}>{u().email}</option>}
                              </For>
                            </Select>
                          </div>
                          <div class="users-field">
                            {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                            <label class="users-label" for="role-value">
                              Role
                            </label>
                            <Select
                              id="role-value"
                              value={roleValue()}
                              onInput={(e) => setRoleValue(e.currentTarget.value)}
                            >
                              <option value="basic">basic</option>
                              <option value="super">super</option>
                              <option value="admin">admin</option>
                            </Select>
                          </div>
                          <Button type="submit" variant="accent" size="lg" class="users-submit">
                            Change role
                          </Button>
                        </div>
                      </CardBody>
                    </form>
                  </Card>
                </Show>

                <Card>
                  <form onSubmit={onBlock}>
                    <CardHeader class="users-card-header">
                      <h2 class="users-section-title">Block time period</h2>
                    </CardHeader>
                    <CardBody>
                      <div class="users-form-stack">
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="block-start">
                            Start
                          </label>
                          <Input
                            id="block-start"
                            type="datetime-local"
                            value={blockStart()}
                            onInput={(e) => setBlockStart(e.currentTarget.value)}
                          />
                        </div>
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="block-end">
                            End
                          </label>
                          <Input
                            id="block-end"
                            type="datetime-local"
                            value={blockEnd()}
                            onInput={(e) => setBlockEnd(e.currentTarget.value)}
                          />
                        </div>
                        <Button type="submit" variant="accent" size="lg" class="users-submit">
                          Block
                        </Button>
                      </div>
                    </CardBody>
                  </form>
                </Card>

                <Card>
                  <form onSubmit={onBroadcast}>
                    <CardHeader class="users-card-header">
                      <h2 class="users-section-title">Broadcast message</h2>
                    </CardHeader>
                    <CardBody>
                      <div class="users-form-stack">
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="broadcast-subject">
                            Subject
                          </label>
                          <Input
                            id="broadcast-subject"
                            value={subject()}
                            onInput={(e) => setSubject(e.currentTarget.value)}
                          />
                        </div>
                        <div class="users-field">
                          {/* oxlint-disable-next-line jsx-a11y/label-has-associated-control -- custom Input/Select/Textarea association verified by for/id */}
                          <label class="users-label" for="broadcast-body">
                            Body
                          </label>
                          <Textarea
                            id="broadcast-body"
                            value={body()}
                            onInput={(e) => setBody(e.currentTarget.value)}
                          />
                        </div>
                        <Button type="submit" variant="accent" size="lg" class="users-submit">
                          Broadcast
                        </Button>
                      </div>
                    </CardBody>
                  </form>
                </Card>
              </section>
            </Show>
          </Errored>
        </Loading>
      </div>
    </div>
  );
}

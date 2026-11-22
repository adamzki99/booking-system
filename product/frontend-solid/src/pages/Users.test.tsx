import { fireEvent, screen, waitFor } from "@solidjs/testing-library";
import { createRouter, memoryHistory, useLocation } from "@solidjs/router";
import { flush } from "solid-js";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "../test-utils";
import type { User } from "../api/auth";
import { addUser, changeUserAddress, changeUserRole, listUsers, removeUser } from "../api/users";
import { useSession } from "../auth/SessionContext";
import Users from "./Users";

vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));
vi.mock("../api/users", () => ({
  listUsers: vi.fn(),
  addUser: vi.fn(),
  removeUser: vi.fn(),
  changeUserAddress: vi.fn(),
  changeUserRole: vi.fn(),
}));
vi.mock("../api/bookings", () => ({
  blockTimePeriod: vi.fn(),
}));
vi.mock("../api/broadcast", () => ({
  broadcastMessage: vi.fn(),
}));

const useSessionMock = vi.mocked(useSession);
const listUsersMock = vi.mocked(listUsers);
const addUserMock = vi.mocked(addUser);
const removeUserMock = vi.mocked(removeUser);
const changeUserAddressMock = vi.mocked(changeUserAddress);
const changeUserRoleMock = vi.mocked(changeUserRole);

const basicUser = { id: "b1", email: "basic@example.com", role: "basic" as const, address: "A", active: true };
const superUser = { id: "s1", email: "super@example.com", role: "super" as const, address: null, active: true };
const adminUser = { id: "a1", email: "admin@example.com", role: "admin" as const, address: null, active: true };

function stubSession(user: User) {
  useSessionMock.mockReturnValue({
    user: () => user,
    loading: () => false,
    login: vi.fn(),
    loginWithQAMode: vi.fn(),
    refresh: vi.fn(),
    logout: vi.fn(),
  } as any);
}

/** Exposes the current query string so tests can assert the ?q= contract. */
function LocationProbe() {
  const location = useLocation();
  return <span data-testid="location-search">{location.search}</span>;
}

function renderUsers(entry = "/users") {
  const Router = createRouter({
    routes: [
      {
        path: "/users",
        component: () => (
          <>
            <Users />
            <LocationProbe />
          </>
        ),
      },
    ],
    history: memoryHistory(entry),
  });
  return render(() => <Router>{(props) => <>{props.children}</>}</Router>);
}

function setInput(element: HTMLElement, value: string) {
  const input = element as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
  input.value = value;
  fireEvent.input(input);
  flush();
}

function setSelect(element: HTMLElement, value: string) {
  const select = element as HTMLSelectElement;
  select.value = value;
  fireEvent.input(select);
  fireEvent.change(select);
  flush();
}

describe("Users page", () => {
  beforeEach(() => {
    useSessionMock.mockReset();
    listUsersMock.mockReset();
    addUserMock.mockReset();
    removeUserMock.mockReset();
    changeUserAddressMock.mockReset();
    changeUserRoleMock.mockReset();
  });

  it("shows directory table for basic users without management controls", async () => {
    stubSession(basicUser);
    listUsersMock.mockResolvedValue([basicUser]);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    expect(screen.queryByText("Change address")).not.toBeInTheDocument();
    expect(screen.queryByText("Change role (admin)")).not.toBeInTheDocument();
  });

  it("lets a super user choose a basic user and change address", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    changeUserAddressMock.mockResolvedValue(basicUser);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });

    const select = screen.getByLabelText("User") as HTMLSelectElement;
    // options include basic user by email
    expect(Array.from(select.options).map((o) => o.text)).toContain("basic@example.com");

    setSelect(select, "b1");
    setInput(document.getElementById("address-value") as HTMLElement, "New addr");
    fireEvent.click(screen.getByRole("button", { name: "Change address" }));

    await waitFor(() => expect(changeUserAddressMock).toHaveBeenCalledWith("b1", "New addr"));
  });

  it("removes a directory user from the row action", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser]);
    removeUserMock.mockResolvedValue(undefined as never);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    fireEvent.click(screen.getByRole("button", { name: "Remove" }));
    await waitFor(() => expect(removeUserMock).toHaveBeenCalledWith("b1"));
  });

  it("shows role controls only for admins and excludes the signed-in user", async () => {
    stubSession(adminUser);
    listUsersMock.mockResolvedValue([basicUser, adminUser]);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    expect(screen.getByText("Change role (admin)")).toBeInTheDocument();
    const selects = screen.getAllByLabelText("User");
    const roleSelect = selects[selects.length - 1] as HTMLSelectElement;
    const optionValues = Array.from(roleSelect.options).map((o) => o.value);
    expect(optionValues).toContain("b1");
    expect(optionValues).not.toContain("a1");
  });

  it("lets an admin change a user's role", async () => {
    stubSession(adminUser);
    listUsersMock.mockResolvedValue([basicUser]);
    changeUserRoleMock.mockResolvedValue(basicUser);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    const selects = screen.getAllByLabelText("User");
    const roleSelect = selects[selects.length - 1];
    setSelect(roleSelect, "b1");
    setSelect(screen.getByLabelText("Role"), "super");
    fireEvent.click(screen.getByRole("button", { name: "Change role" }));
    await waitFor(() => expect(changeUserRoleMock).toHaveBeenCalledWith("b1", "super"));
  });

  it("hides role controls for super users who are not admins", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser]);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    expect(screen.queryByText("Change role (admin)")).not.toBeInTheDocument();
  });

  it("excludes ineligible (non-basic) targets from the address select", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    const selects = screen.getAllByLabelText("User");
    const addressSelect = selects[0] as HTMLSelectElement;
    const optionValues = Array.from(addressSelect.options).map((o) => o.value);
    expect(optionValues).toEqual(["b1"]);
  });

  it("surfaces an error alert when an API call rejects", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser]);
    changeUserAddressMock.mockRejectedValue(new Error("boom"));
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    const select = screen.getByLabelText("User");
    setSelect(select, "b1");
    setInput(document.getElementById("address-value") as HTMLElement, "New addr");
    fireEvent.click(screen.getByRole("button", { name: "Change address" }));
    await screen.findByRole("alert");
  });

  it("renders an initials avatar for each directory member", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });
    expect(screen.getByText("BA")).toBeInTheDocument();
    expect(screen.getByText("SU")).toBeInTheDocument();
  });

  it("hides non-matching directory rows when ?q= is provided", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    renderUsers("/users?q=super");
    await screen.findByRole("cell", { name: "super@example.com" });
    expect(
      screen.queryByRole("cell", { name: "basic@example.com" }),
    ).not.toBeInTheDocument();
  });

  it("filters rows and writes the query parameter as the user types", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    renderUsers();
    await screen.findByRole("cell", { name: "basic@example.com" });

    setInput(screen.getByLabelText("Search members"), "super");

    expect(
      screen.queryByRole("cell", { name: "basic@example.com" }),
    ).not.toBeInTheDocument();
    expect(screen.getByRole("cell", { name: "super@example.com" })).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByTestId("location-search").textContent).toContain("q=super"),
    );
  });

  it("keeps management select options complete while a search filters rows", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    renderUsers("/users?q=super");
    await screen.findByRole("cell", { name: "super@example.com" });
    expect(
      screen.queryByRole("cell", { name: "basic@example.com" }),
    ).not.toBeInTheDocument();

    const addressSelect = screen.getByLabelText("User") as HTMLSelectElement;
    expect(Array.from(addressSelect.options).map((o) => o.text)).toContain(
      "basic@example.com",
    );
  });
});

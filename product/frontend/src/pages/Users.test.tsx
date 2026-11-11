import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { render } from "../test-utils";
import { useSession } from "../auth/SessionContext";
import * as usersApi from "../api/users";
import Users from "./Users";

vi.mock("../auth/SessionContext", () => ({ useSession: vi.fn() }));
vi.mock("../api/users", () => ({
  listUsers: vi.fn(),
  addUser: vi.fn(),
  removeUser: vi.fn(),
  changeUserAddress: vi.fn(),
  changeUserRole: vi.fn(),
}));

const useSessionMock = vi.mocked(useSession);
const listUsersMock = vi.mocked(usersApi.listUsers);
const removeUserMock = vi.mocked(usersApi.removeUser);
const changeUserAddressMock = vi.mocked(usersApi.changeUserAddress);
const changeUserRoleMock = vi.mocked(usersApi.changeUserRole);

const basicUser = { id: "b1", email: "basic@example.com", role: "basic" as const, address: "A", active: true };
const superUser = { id: "s1", email: "super@example.com", role: "super" as const, address: null, active: true };
const adminUser = { id: "a1", email: "admin@example.com", role: "admin" as const, address: null, active: true };

function stubSession(user: typeof basicUser) {
  useSessionMock.mockReturnValue({
    user,
    loading: false,
    login: vi.fn(),
    logout: vi.fn(),
  });
}

describe("Users page", () => {
  beforeEach(() => {
    useSessionMock.mockReset();
    listUsersMock.mockReset();
    removeUserMock.mockReset();
    changeUserAddressMock.mockReset();
    changeUserRoleMock.mockReset();
  });

  it("shows directory table for basic users without management controls", async () => {
    stubSession(basicUser);
    listUsersMock.mockResolvedValue([basicUser]);
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });
    expect(screen.queryByText("Change address")).not.toBeInTheDocument();
    expect(screen.queryByText("Change role (admin)")).not.toBeInTheDocument();
  });

  it("lets a super user choose a basic user and change address", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    changeUserAddressMock.mockResolvedValue(basicUser);
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });

    const select = screen.getByLabelText("User") as HTMLSelectElement;
    // options include basic user by email
    expect(Array.from(select.options).map((o) => o.text)).toContain("basic@example.com");

    const user = userEvent.setup();
    await user.selectOptions(select, "b1");
    await user.type(document.getElementById("address-value") as HTMLElement, "New addr");
    await user.click(screen.getByRole("button", { name: "Change address" }));

    await waitFor(() => expect(changeUserAddressMock).toHaveBeenCalledWith("b1", "New addr"));
  });

  it("removes a directory user from the row action", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser]);
    removeUserMock.mockResolvedValue(undefined as never);
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "Remove" }));
    await waitFor(() => expect(removeUserMock).toHaveBeenCalledWith("b1"));
  });

  it("shows role controls only for admins and excludes the signed-in user", async () => {
    stubSession(adminUser);
    listUsersMock.mockResolvedValue([basicUser, adminUser]);
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });
    expect(screen.getByText("Change role (admin)")).toBeInTheDocument();
    const selects = screen.getAllByLabelText("User");
    const roleSelect = selects[selects.length - 1];
    const optionValues = Array.from(roleSelect.options).map((o) => o.value);
    expect(optionValues).toContain("b1");
    expect(optionValues).not.toContain("a1");
  });

  it("lets an admin change a user's role", async () => {
    stubSession(adminUser);
    listUsersMock.mockResolvedValue([basicUser]);
    changeUserRoleMock.mockResolvedValue(basicUser);
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });
    const user = userEvent.setup();
    const selects = screen.getAllByLabelText("User");
    const roleSelect = selects[selects.length - 1];
    await user.selectOptions(roleSelect, "b1");
    await user.selectOptions(screen.getByLabelText("Role"), "super");
    await user.click(screen.getByRole("button", { name: "Change role" }));
    await waitFor(() => expect(changeUserRoleMock).toHaveBeenCalledWith("b1", "super"));
  });

  it("hides role controls for super users who are not admins", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser]);
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });
    expect(screen.queryByText("Change role (admin)")).not.toBeInTheDocument();
  });

  it("excludes ineligible (non-basic) targets from the address select", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser, superUser]);
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });
    const selects = screen.getAllByLabelText("User");
    const addressSelect = selects[0];
    const optionValues = Array.from(addressSelect.options).map((o) => o.value);
    expect(optionValues).toEqual(["b1"]);
  });

  it("surfaces an error alert when an API call rejects", async () => {
    stubSession(superUser);
    listUsersMock.mockResolvedValue([basicUser]);
    changeUserAddressMock.mockRejectedValue(new Error("boom"));
    render(<Users />);
    await screen.findByRole("cell", { name: "basic@example.com" });
    const user = userEvent.setup();
    const select = screen.getByLabelText("User");
    await user.selectOptions(select, "b1");
    await user.type(document.getElementById("address-value") as HTMLElement, "New addr");
    await user.click(screen.getByRole("button", { name: "Change address" }));
    await screen.findByRole("alert");
  });
});

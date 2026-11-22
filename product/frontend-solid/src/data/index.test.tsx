import { cleanup, render, screen, waitFor } from "@solidjs/testing-library";
import { For, createSignal } from "solid-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { listBookings } from "../api/bookings";
import {
  Errored,
  Loading,
  createAsyncData,
  createMutation,
  createOptimisticData,
  flush,
  refresh,
} from "./index";

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe("data conventions", () => {
  afterEach(() => {
    cleanup();
  });
  it("reads async data via createAsyncData/createMemo under Loading", async () => {
    const pending = deferred<string>();

    function App() {
      const data = createAsyncData(() => pending.promise);
      return (
        <Loading fallback={<div>loading</div>}>
          <div data-testid="value">{data()}</div>
        </Loading>
      );
    }

    render(() => <App />);
    expect(screen.getByText("loading")).toBeInTheDocument();

    pending.resolve("ready");
    await waitFor(() => {
      expect(screen.getByTestId("value")).toHaveTextContent("ready");
    });
  });

  it("surfaces async read errors via Errored", async () => {
    const pending = deferred<string>();

    function App() {
      const data = createAsyncData(() => pending.promise);
      return (
        <Errored
          fallback={(err) => <div data-testid="error">{String(err())}</div>}
        >
          <Loading fallback={<div>loading</div>}>
            <div>{data()}</div>
          </Loading>
        </Errored>
      );
    }

    render(() => <App />);
    expect(screen.getByText("loading")).toBeInTheDocument();

    pending.reject(new Error("boom"));
    await waitFor(() => {
      expect(screen.getByTestId("error")).toHaveTextContent("boom");
    });
  });

  it("runs mutations with action/yield and refreshes async reads", async () => {
    let version = 0;
    const fetchValue = vi.fn(async () => {
      version += 1;
      return `v${version}`;
    });

    function App() {
      const data = createAsyncData(() => fetchValue());
      const reload = createMutation(function* () {
        yield Promise.resolve();
        yield refresh(data);
      });

      return (
        <div>
          <Loading fallback={<div>loading</div>}>
            <div data-testid="value">{data()}</div>
          </Loading>
          <button type="button" onClick={() => void reload()}>
            reload
          </button>
        </div>
      );
    }

    render(() => <App />);
    await waitFor(() => {
      expect(screen.getByTestId("value")).toHaveTextContent("v1");
    });
    expect(fetchValue).toHaveBeenCalledTimes(1);

    screen.getByRole("button", { name: "reload" }).click();
    await waitFor(() => {
      expect(screen.getByTestId("value")).toHaveTextContent("v2");
    });
    expect(fetchValue).toHaveBeenCalledTimes(2);
  });

  it("supports optimistic store updates in actions with refresh", async () => {
    const gate = deferred<void>();
    let serverItems = [{ id: "1", text: "A" }];
    const fetchItems = vi.fn(async () => serverItems.map((item) => ({ ...item })));

    function App() {
      const [items, setItems] = createOptimisticData(
        () => fetchItems(),
        [] as Array<{ id: string; text: string }>,
      );

      const add = createMutation(function* () {
        setItems((draft) => {
          draft.push({ id: "2", text: "B" });
        });
        yield gate.promise;
        serverItems = [...serverItems, { id: "2", text: "B" }];
        yield refresh(items);
      });

      return (
        <div>
          <Loading fallback={<div>loading</div>}>
            <ul data-testid="list">
              <For each={items}>{(item) => <li>{`${item.id}:${item.text}`}</li>}</For>
            </ul>
          </Loading>
          <button type="button" onClick={() => void add()}>
            add
          </button>
        </div>
      );
    }

    render(() => <App />);
    await waitFor(() => {
      expect(screen.getByTestId("list")).toHaveTextContent("1:A");
      expect(screen.getByTestId("list")).not.toHaveTextContent("2:B");
    });

    screen.getByRole("button", { name: "add" }).click();
    await waitFor(() => {
      expect(screen.getByTestId("list")).toHaveTextContent("2:B");
    });

    gate.resolve();
    await waitFor(() => {
      expect(screen.getByTestId("list")).toHaveTextContent("1:A");
      expect(screen.getByTestId("list")).toHaveTextContent("2:B");
    });
    expect(fetchItems.mock.calls.length).toBeGreaterThanOrEqual(2);
  });

  it("requires flush() to observe staged writes synchronously in tests", () => {
    const [value, setValue] = createSignal("before");

    setValue("after");
    // oxlint-disable-next-line solid/reactivity -- intentional untracked read before flush
    expect(value()).toBe("before");

    flush();
    // oxlint-disable-next-line solid/reactivity -- intentional untracked read after flush
    expect(value()).toBe("after");
  });

  describe("integration with src/api modules", () => {
    const fetchMock = vi.fn();

    beforeEach(() => {
      localStorage.clear();
      fetchMock.mockReset();
      vi.stubGlobal("fetch", fetchMock);
    });

    afterEach(() => {
      vi.unstubAllGlobals();
    });

    it("reads framework-independent API data via createAsyncData under Loading", async () => {
      fetchMock.mockResolvedValueOnce(
        new Response(
          JSON.stringify([
            {
              id: "b1",
              user_id: "u1",
              start: "2026-12-01T10:00:00Z",
              end: "2026-12-01T11:00:00Z",
              status: "active",
            },
          ]),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );

      function App() {
        const bookings = createAsyncData(() => listBookings());
        return (
          <Loading fallback={<div>loading</div>}>
            <div data-testid="count">{bookings().length}</div>
            <div data-testid="owner">{bookings()[0]?.userId}</div>
          </Loading>
        );
      }

      render(() => <App />);
      await waitFor(() => {
        expect(screen.getByTestId("count")).toHaveTextContent("1");
        expect(screen.getByTestId("owner")).toHaveTextContent("u1");
      });
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/bookings",
        expect.objectContaining({ method: "GET" }),
      );
    });
  });
});

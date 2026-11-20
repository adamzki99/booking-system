/**
 * Shared Solid 2 data conventions for async reads, loading/error boundaries,
 * and mutations.
 *
 * Async reads:
 * - Create reads with `createAsyncData(() => apiCall(...))` (a `createMemo`
 *   source that may return a Promise).
 * - Read the value under `<Loading fallback={...}>` so pending reads suspend
 *   to the boundary fallback.
 *
 * Errors:
 * - Wrap read/mutation surfaces with `<Errored fallback={...}>` to handle
 *   thrown errors. The fallback can render `(err, reset)` for retry.
 *
 * Mutations:
 * - Define mutations with `action(function* (...) { ...; yield apiCall(...);
 *   refresh(source); })` (or `createMutation(...)` below). Use `yield`, not
 *   `await`.
 * - `refresh(source)` reconciles a refreshable read (e.g. async memo/store
 *   source) after a server write. Call from actions/effects/handlers.
 *
 * Optimistic updates:
 * - Current React page behavior: not found. Page flows load data and, after
 *   mutations, await the server call and re-fetch/refresh; no immediate
 *   optimistic list updates before server acknowledgement were identified.
 * - Pattern support is provided via `createOptimisticStore` /
 *   `createOptimisticData` for future parity where optimistic UI is needed.
 *
 * Staged writes:
 * - Writes are staged. After a setter runs, reads can still return the
 *   previous committed value until flush. In tests call `flush()` after writes
 *   and before asserting when immediate observation is required.
 *
 * Integration:
 * - Designed to compose with framework-independent API modules in `src/api/**`
 *   (e.g. `createAsyncData(() => listBookings())`, `yield createBooking(...)`).
 */

import {
  Errored,
  Loading,
  action,
  affects,
  createMemo,
  createOptimisticStore,
  flush,
  isPending,
  latest,
  refresh,
  type SourceAccessor,
} from "solid-js";

export {
  Errored,
  Loading,
  action,
  affects,
  createMemo,
  createOptimisticStore,
  flush,
  isPending,
  latest,
  refresh,
};

/** Standard async read: a refreshable memo whose source may be asynchronous. Read under `<Loading>`. */
export function createAsyncData<T>(source: () => T | Promise<T>): SourceAccessor<T> {
  // Solid 2 async memos suspend/pending when their value is not yet ready.
  return createMemo(source as () => T) as SourceAccessor<T>;
}

/**
 * Standard mutation helper using the Solid 2 generator action pattern.
 * Example:
 *   const save = createMutation(function* (id: string) {
 *     yield api.update(id);
 *     refresh(items);
 *   });
 */
export function createMutation<T extends (...args: any[]) => Generator<unknown, unknown, unknown>>(
  fn: T,
): T {
  return action(fn) as unknown as T;
}

/**
 * Optimistic data pattern helper.
 * Returns a derived optimistic store `[store, setStore]` backed by `source`.
 * Writes via `setStore` inside an `action` are tentative and reconcile when the
 * transition settles; call `refresh(store)` after the server write as needed.
 */
export function createOptimisticData<T extends object>(
  source: () => T | Promise<T>,
  seed: T,
): ReturnType<typeof createOptimisticStore<T>> {
  return createOptimisticStore(source as any, seed as any) as ReturnType<
    typeof createOptimisticStore<T>
  >;
}

import { createSignal } from "solid-js";

export default function App() {
  const [count, setCount] = createSignal(0);

  return (
    <main>
      <h1>Booking Solid</h1>
      <p>Smoke component is running.</p>
      <button type="button" onClick={() => setCount((value) => value + 1)}>
        Count: {count()}
      </button>
    </main>
  );
}

import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// The SPA always talks to `/api/...`. In development the dev server proxies to
// the Go backend running on :8080, stripping the `/api` prefix the same way
// Caddy does in production (handle_path /api/*).
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:8080",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ""),
      },
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "src/tests.setup.ts",
  },
});

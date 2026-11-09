import { ChakraProvider } from "@chakra-ui/react";
import { render, type RenderOptions } from "@testing-library/react";
import type { ReactElement, ReactNode } from "react";
import theme from "./theme";

/**
 * Provider-aware render helper.
 *
 * Wraps the UI under test in `ChakraProvider` so Chakra context hooks
 * (useTheme, useToast, etc.) work in tests.
 */
function AllProviders({ children }: { children: ReactNode }) {
  return <ChakraProvider theme={theme}>{children}</ChakraProvider>;
}

function customRender(ui: ReactElement, options?: Omit<RenderOptions, "wrapper">) {
  return render(ui, { wrapper: AllProviders, ...options });
}

// Re-export everything from @testing-library/react so tests can import
// { render, screen, waitFor, ... } from "../test-utils" and still override
// render with the provider-aware version.
export * from "@testing-library/react";
export { customRender as render };

import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// A config of its own, not `vite.config.ts`: that one loads the Cloudflare plugin, which builds and serves the
// Worker. This suite imports the Worker's modules directly and needs no runtime around them.
export default defineConfig({
  // `@/` is app/src/, as in vite.config.ts.
  // `cloudflare:workers` exists only in the Workers runtime: the AI connector's tests get a stand-in.
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)),
    "cloudflare:workers": fileURLToPath(new URL("./tests/cloudflare-workers.ts", import.meta.url)) } },
  test: {
    include: ["worker/**/*.test.ts", "src/**/*.test.{ts,tsx}"],
    environment: "node",
    // The OAuth library imports `cloudflare:workers` too, so it goes through the alias rather than Node's loader.
    server: { deps: { inline: ["@cloudflare/workers-oauth-provider"] } },
    // What the ready-made parts ask of a browser that the test DOM lacks.
    setupFiles: ["src/dom.test.setup.ts"],
    coverage: {
      provider: "v8",
      include: ["worker/**/*.ts", "src/**/*.ts", "src/**/*.tsx"],
      exclude: [
        "src/main.tsx",
        "**/*.test.*",
        "**/*.d.ts",
        "src/**/*.css",
        "src/assets/**",
        // The ready-made parts are copied as their makers wrote them and are
        // exercised through the screens that use them. Every other file stays at 100%.
        "src/components/ui/**",
      ],
      thresholds: {
        lines: 100,
        functions: 100,
        branches: 100,
        statements: 100,
      },
    },
  },
});

import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  // Relative base: the bundle is loaded from app resources, not a server root.
  base: "./",
  plugins: [vue()],
  build: {
    // Mermaid and Markdown stay bundled offline; Mermaid is lazy-loaded.
    chunkSizeWarningLimit: 700,
  },
  test: {
    environment: "jsdom",
  },
});

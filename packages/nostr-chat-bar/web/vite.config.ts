import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  // Relative base: the bundle is loaded from app resources, not a server root.
  base: "./",
  plugins: [vue()],
  test: {
    environment: "jsdom",
  },
});

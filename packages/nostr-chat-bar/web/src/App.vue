<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import { installNativeAPI } from "./bridge";
import { createMessageStore } from "./model";
import MessageList from "./components/MessageList.vue";

const store = createMessageStore();
const now = ref(Date.now());
let ticker: ReturnType<typeof setInterval> | undefined;

onMounted(() => {
  // Install after mount: once `ready` is posted Swift may call into
  // window.nostrChat immediately.
  installNativeAPI(store);
  // Relative timestamps ("now" → "1m") only need a coarse tick; the
  // tick patches bubble chrome, never rendered bodies.
  ticker = setInterval(() => {
    now.value = Date.now();
  }, 30_000);
});

onUnmounted(() => clearInterval(ticker));
</script>

<template>
  <main class="history" data-renderer="nostr-chat-bar-web">
    <MessageList :store="store" :now="now" />
  </main>
</template>

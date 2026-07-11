<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import { installNativeAPI } from "./bridge";
import { createMessageStore } from "./model";
import { insertBehavior, isNearBottom, scrollToBottom } from "./scroll";
import MessageList from "./components/MessageList.vue";

const store = createMessageStore();
const now = ref(Date.now());
const unseen = ref(0);
let ticker: ReturnType<typeof setInterval> | undefined;

function clearUnseen(): void {
  unseen.value = 0;
  void scrollToBottom();
}

onMounted(() => {
  // Install after mount: once `ready` is posted Swift may call into
  // window.nostrChat immediately.
  installNativeAPI(store, {
    measureNearBottom: isNearBottom,
    onUpsert: (message, { isNew, wasNearBottom }) => {
      if (!isNew) return;
      if (insertBehavior(message.mine, wasNearBottom) === "stick") {
        unseen.value = 0;
        void scrollToBottom();
      } else {
        unseen.value += 1;
      }
    },
    // Snapshots only arrive on a fresh or recovered page; starting at
    // the newest message is the expected position, not a jump.
    onReplace: () => {
      unseen.value = 0;
      void scrollToBottom();
    },
  });
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
    <button v-if="unseen > 0" class="unseen-indicator" @click="clearUnseen">
      {{ unseen }} new ↓
    </button>
  </main>
</template>

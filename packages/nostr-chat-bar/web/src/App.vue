<script setup lang="ts">
import { onMounted, ref } from "vue";
import { installNativeAPI } from "./bridge";
import { createMessageStore } from "./model";
import MessageList from "./components/MessageList.vue";

const store = createMessageStore();
const now = ref(Date.now());

onMounted(() => {
  // Install after mount: once `ready` is posted Swift may call into
  // window.nostrChat immediately.
  installNativeAPI(store);
});
</script>

<template>
  <main class="history" data-renderer="nostr-chat-bar-web">
    <MessageList :store="store" :now="now" />
  </main>
</template>

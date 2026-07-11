<script setup lang="ts">
import type { MessageStore } from "../model";
import MessageBubble from "./MessageBubble.vue";

defineProps<{ store: MessageStore; now: number }>();
</script>

<template>
  <!-- Message IDs are the stable keys: patches update a bubble in
       place instead of tearing down its rendered body. -->
  <section class="message-list">
    <MessageBubble
      v-for="message in store.messages"
      :key="message.id"
      :message="message"
      :reply-preview="store.replyPreview(message.replyTo)"
      :now="now"
    />
  </section>
</template>

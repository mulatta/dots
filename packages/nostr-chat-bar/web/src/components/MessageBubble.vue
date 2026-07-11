<script setup lang="ts">
import { computed } from "vue";
import type { Message } from "../model";
import { relativeTime } from "../time";
import MessageBody from "./MessageBody.vue";

const props = defineProps<{
  message: Message;
  replyPreview: string | null;
  now: number;
}>();

const meta = computed(() => {
  const parts = [relativeTime(props.message.timestamp, props.now)];
  if (props.message.mine) {
    if (props.message.tries > 0) parts.push("⚠");
    else if (props.message.state === "pending") parts.push("…");
    else if (props.message.ack) parts.push(props.message.ack);
  }
  return parts.join("  ");
});
</script>

<template>
  <article
    class="bubble-row"
    :class="message.mine ? 'mine' : 'theirs'"
    :data-message-id="message.id"
  >
    <div class="bubble">
      <div v-if="message.replyTo" class="reply-quote">↳ {{ replyPreview }}</div>
      <MessageBody :text="message.text" />
      <div class="meta">{{ meta }}</div>
    </div>
  </article>
</template>

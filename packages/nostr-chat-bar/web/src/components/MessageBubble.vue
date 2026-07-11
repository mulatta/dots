<script setup lang="ts">
import { computed } from "vue";
import { postAction } from "../bridge";
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

// Undelivered own messages expose the native retry/cancel commands.
const undelivered = computed(
  () => props.message.mine && (props.message.state === "pending" || props.message.tries > 0),
);

function act(type: "reply" | "copy" | "retry" | "cancel"): void {
  postAction({ type, messageId: props.message.id });
}
</script>

<template>
  <article
    class="bubble-row"
    :class="message.mine ? 'mine' : 'theirs'"
    :data-message-id="message.id"
  >
    <!-- Hover-reveal gutter actions, same UX as the AppKit cells. -->
    <div class="gutter" :class="message.mine ? 'left' : 'right'">
      <button class="action reply" title="reply" @click="act('reply')">
        {{ message.mine ? "↪" : "↩" }}
      </button>
      <button class="action copy" title="copy" @click="act('copy')">⧉</button>
    </div>
    <div class="bubble">
      <div v-if="message.replyTo" class="reply-quote">↳ {{ replyPreview }}</div>
      <MessageBody :text="message.text" />
      <div class="meta">
        {{ meta }}
        <template v-if="undelivered">
          <button class="action retry" title="retry now" @click="act('retry')">retry</button>
          <button class="action cancel" title="cancel send" @click="act('cancel')">cancel</button>
        </template>
      </div>
    </div>
  </article>
</template>

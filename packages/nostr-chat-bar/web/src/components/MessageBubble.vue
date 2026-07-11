<script setup lang="ts">
import { computed, ref } from "vue";
import { postAction } from "../bridge";
import type { Message } from "../model";
import { relativeTime } from "../time";
import MessageBody from "./MessageBody.vue";

const props = defineProps<{
  message: Message;
  replyPreview: string | null;
  now: number;
  searchHit: boolean;
  searchCurrent: boolean;
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

// The attachment URL carries only the message ID; the native scheme
// handler resolves and authorizes the actual file.
const mediaURL = computed(() => `nostr-chat-media://message/${props.message.id}`);
const imageFailed = ref(false);

function act(type: "reply" | "copy" | "retry" | "cancel" | "open-image"): void {
  postAction({ type, messageId: props.message.id });
}
</script>

<template>
  <article
    class="bubble-row"
    :class="[
      message.mine ? 'mine' : 'theirs',
      { 'search-hit': searchHit, 'search-current': searchCurrent },
    ]"
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
      <figure v-if="message.hasImage" class="attachment">
        <img
          v-if="!imageFailed"
          :src="mediaURL"
          alt="attachment"
          @error="imageFailed = true"
          @click="act('open-image')"
        />
        <figcaption v-else class="attachment-missing">attachment unavailable</figcaption>
      </figure>
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

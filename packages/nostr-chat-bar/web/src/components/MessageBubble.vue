<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { postAction } from "../bridge";
import type { Message } from "../model";
import { scrollToMessage } from "../scroll";
import { relativeTime } from "../time";
import MessageBody from "./MessageBody.vue";

const props = defineProps<{
  message: Message;
  replyPreview: string | null;
  now: number;
  searchHit: boolean;
  searchCurrent: boolean;
}>();

const time = computed(() => relativeTime(props.message.timestamp, props.now));

// Delivery ladder, matching the upstream QML bubble:
// ⚠ retrying → 🕓 pending → ✓ sent (no ack yet) → ✓✓ read, with any
// other ack (emoji reaction) shown verbatim.
const deliveryMark = computed(() => {
  if (!props.message.mine) return "";
  const m = props.message;
  if (m.tries > 0) return "⚠";
  if (m.state === "pending") return "🕓";
  if (m.ack === "") return "✓";
  return m.ack === "+" || m.ack === "✓" ? "✓✓" : m.ack;
});

const failed = computed(() => props.message.mine && props.message.tries > 0);
const pending = computed(
  () => props.message.mine && props.message.state === "pending",
);

// Undelivered own messages expose the native retry/cancel commands.
const undelivered = computed(
  () => props.message.mine && (props.message.state === "pending" || props.message.tries > 0),
);

// The attachment URL carries only the message ID; the native scheme
// handler resolves and authorizes the actual file.
const mediaURL = computed(() => `nostr-chat-media://message/${props.message.id}`);
const imageFailed = ref(false);
watch([() => props.message.id, () => props.message.hasImage], () => {
  imageFailed.value = false;
});

function act(type: "reply" | "copy" | "retry" | "cancel" | "open-image"): void {
  postAction({ type, messageId: props.message.id });
}

// Clicking the quote jumps to the original bubble, like the upstream
// panel; a target outside maxHistory is simply not found.
function jumpToQuote(): void {
  if (props.message.replyTo) scrollToMessage(props.message.replyTo);
}
</script>

<template>
  <article
    class="bubble-row"
    :class="[
      message.mine ? 'mine' : 'theirs',
      { 'search-hit': searchHit, 'search-current': searchCurrent, pending },
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
      <div v-if="message.replyTo" class="reply-quote" @click="jumpToQuote">
        ↳ {{ replyPreview }}
      </div>
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
        {{ time }}
        <span
          v-if="deliveryMark"
          class="delivery"
          :class="{ failed }"
          :title="failed ? message.error || undefined : undefined"
          >{{ deliveryMark }}</span
        >
        <template v-if="undelivered">
          <button class="action retry" title="retry now" @click="act('retry')">retry</button>
          <button class="action cancel" title="cancel send" @click="act('cancel')">cancel</button>
        </template>
      </div>
    </div>
  </article>
</template>

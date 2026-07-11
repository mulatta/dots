<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from "vue";
import { renderMarkdown } from "../markdown";
import { renderMermaidBlocks, type Appearance } from "../mermaid";

// Body rendering depends on the text alone: metadata patches touch the
// bubble around this component and must never re-enter the pipeline.
const props = defineProps<{ text: string }>();

const host = ref<HTMLElement | null>(null);
const html = computed(() => renderMarkdown(props.text));

function appearance(): Appearance {
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

async function paintDiagrams(): Promise<void> {
  if (host.value) await renderMermaidBlocks(host.value, appearance());
}

onMounted(paintDiagrams);
watch(html, async () => {
  // v-html has replaced the subtree by the next tick; repaint from the
  // fresh placeholders.
  await nextTick();
  await paintDiagrams();
});
</script>

<template>
  <div ref="host" class="message-body" v-html="html"></div>
</template>

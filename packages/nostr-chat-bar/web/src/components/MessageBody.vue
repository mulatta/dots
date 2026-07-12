<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { postAction } from "../bridge";
import { renderMarkdown } from "../markdown";
import { renderMermaidBlocks, type Appearance } from "../mermaid";

// Body rendering depends on the text alone: metadata patches touch the
// bubble around this component and must never re-enter the pipeline.
const props = defineProps<{ text: string }>();

const host = ref<HTMLElement | null>(null);
const html = computed(() => renderMarkdown(props.text));
const appearance = ref<Appearance>(
  window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light",
);
let appearanceQuery: MediaQueryList | undefined;

async function paintDiagrams(): Promise<void> {
  if (host.value) await renderMermaidBlocks(host.value, appearance.value);
}

function updateAppearance(): void {
  appearance.value = appearanceQuery?.matches ? "dark" : "light";
}

onMounted(() => {
  appearanceQuery = window.matchMedia?.("(prefers-color-scheme: dark)");
  appearanceQuery?.addEventListener("change", updateAppearance);
  updateAppearance();
  void paintDiagrams();
});
onUnmounted(() => appearanceQuery?.removeEventListener("change", updateAppearance));
watch([html, appearance], async () => {
  await nextTick();
  await paintDiagrams();
});

// Links never navigate the history page; they surface as bridge
// actions that Swift validates and opens externally.
function onClick(event: MouseEvent): void {
  const target = event.target as HTMLElement | null;
  const anchor = target?.closest?.("a[href]");
  if (!anchor) return;
  event.preventDefault();
  const url = anchor.getAttribute("href");
  if (url) postAction({ type: "open-link", url });
}
</script>

<template>
  <div
    :key="appearance"
    ref="host"
    class="message-body"
    v-html="html"
    @click="onClick"
  ></div>
</template>

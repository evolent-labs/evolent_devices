<script lang="ts">
  import { brand } from '$lib/brand.svelte';
  import { tinted, tintedNow } from '$lib/tint';

  let { src, cls = '', accent = '', onfail }: { src: string; cls?: string; accent?: string; onfail?: () => void } = $props();

  let shown = $state('');

  $effect(() => {
    const source = src;
    const shade = accent || brand.accent;
    const now = tintedNow(source, shade);

    if (now !== null) {
      shown = now;
      return;
    }

    let live = true;

    tinted(source, shade).then((url) => {
      if (live) shown = url;
    });

    return () => {
      live = false;
    };
  });
</script>

{#if shown}<img class={cls} src={shown} alt="" onerror={() => onfail?.()} />{/if}

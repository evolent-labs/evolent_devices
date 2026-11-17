<script lang="ts">
  import { brand, idlePicture } from '$lib/brand.svelte';
  import { t } from '$lib/state.svelte';
  import { IDLE_PREVIEWS, isIdleKind, SCREEN_SIZES } from '$lib/walls';
  import Tinted from './Tinted.svelte';

  let { kind }: { kind: string } = $props();

  const own = $derived(brand.walls.find((entry) => entry.id === idlePicture(kind)));

  let failed = $state('');
</script>

{#if IDLE_PREVIEWS[kind]}
  <span class="idle-preview">
    {#if own && isIdleKind(kind) && failed !== own.src}
      <img class="idle-preview-own" src={own.src} alt="" style:aspect-ratio={`${SCREEN_SIZES[kind].width} / ${SCREEN_SIZES[kind].height}`} onerror={() => (failed = own.src)} />
    {:else}
      <Tinted src={IDLE_PREVIEWS[kind]} />
    {/if}
    <small>{t('ui_idle_caption')}</small>
  </span>
{/if}

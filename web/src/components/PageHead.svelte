<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon from './Icon.svelte';
  import { closePanel } from '$lib/panel';
  import { t } from '$lib/state.svelte';

  let {
    title,
    back,
    actions,
    tabs,
  }: { title: string; back?: () => void; actions?: Snippet; tabs?: Snippet } = $props();
</script>

<header class={'top' + (tabs ? ' with-tabs' : '')}>
  <div class="head-text">
    {#if back}<button class="icon-button back-button" aria-label={t('ui_back')} onclick={back}><Icon name="back" /></button>{/if}
    <h1>{title}</h1>
  </div>
  <div class="header-actions">
    {#if actions}{@render actions()}{/if}
    <button class="icon-button" aria-label={t('ui_close')} onclick={() => closePanel()}><Icon name="x" /></button>
  </div>
  {#if tabs}{@render tabs()}{/if}
</header>

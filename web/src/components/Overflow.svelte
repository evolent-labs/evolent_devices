<script lang="ts">
  import { untrack } from 'svelte';
  import Icon from './Icon.svelte';
  import { app, t } from '$lib/state.svelte';

  export interface OverflowItem {
    label: string;
    icon: string;
    danger?: boolean;
    disabled?: boolean;
    run: () => void;
  }

  let { items, label, icon = 'plus', disabled = false }: { items: OverflowItem[]; label?: string; icon?: string; disabled?: boolean } = $props();
  let open = $state(false);
  const close = () => (open = false);

  $effect(() => {
    if (!open) return;

    const previous = untrack(() => app.popoverClose);

    if (previous && previous !== close) {
      previous();
    }

    app.popoverClose = close;

    return () => {
      if (untrack(() => app.popoverClose) === close) {
        app.popoverClose = null;
      }
    };
  });

  function choose(item: OverflowItem) {
    open = false;
    item.run();
  }
</script>

{#if items.length}
  <span class={'overflow' + (label ? ' labelled' : '')}>
    {#if label}
      <button class="button small" {disabled} aria-expanded={open} onclick={() => (open = !open)}><Icon name={icon} />{label}</button>
    {:else}
      <button class="icon-button" {disabled} aria-label={t('ui_more_actions')} aria-expanded={open} onclick={() => (open = !open)}><Icon name="more" /></button>
    {/if}
    {#if open}
      <div class="overflow-backdrop" role="presentation" onclick={close}></div>
      <ul class="overflow-menu" role="menu">
        {#each items as item (item.label)}
          <li><button role="menuitem" class={item.danger ? 'danger' : ''} disabled={item.disabled} onclick={() => choose(item)}><Icon name={item.icon} />{item.label}</button></li>
        {/each}
      </ul>
    {/if}
  </span>
{/if}

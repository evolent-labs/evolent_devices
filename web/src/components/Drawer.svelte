<script lang="ts">
  import { untrack } from 'svelte';
  import type { Snippet } from 'svelte';
  import Icon from './Icon.svelte';
  import { app, t } from '$lib/state.svelte';

  let {
    open,
    title,
    sub,
    wide = false,
    onclose,
    top,
    children,
    footer,
  }: {
    open: boolean;
    title: string;
    sub?: string;
    wide?: boolean;
    onclose: () => void;
    top?: Snippet;
    children: Snippet;
    footer?: Snippet;
  } = $props();

  let panel = $state<HTMLElement | null>(null);
  const close = () => onclose();

  $effect(() => {
    if (!open) return;

    const previous = untrack(() => app.drawerClose);

    if (previous && previous !== close) {
      previous();
    }

    app.drawerClose = close;

    queueMicrotask(() => {
      const field = panel?.querySelector<HTMLElement>('input:not([type=hidden]):not([type=checkbox]):not([type=range]):not([disabled]), textarea:not([disabled])');

      field?.focus();
    });

    return () => {
      if (untrack(() => app.drawerClose) === close) {
        app.drawerClose = null;
      }
    };
  });
</script>

{#if open}
  <div class="drawer-backdrop" role="presentation" onclick={close}></div>
  <div class={'drawer' + (wide ? ' wide' : '')} role="dialog" aria-modal="true" aria-label={title} tabindex="-1" bind:this={panel}>
    <header>
      <div class="drawer-title">
        <h2 class:with-sub={!!sub}>{title}</h2>
        {#if sub}<p class="drawer-sub">{sub}</p>{/if}
        {#if top}{@render top()}{/if}
      </div>
      <button class="icon-button" aria-label={t('ui_close')} onclick={close}><Icon name="x" /></button>
    </header>
    <div class="drawer-body">{@render children()}</div>
    {#if footer}<footer class="drawer-foot">{@render footer()}</footer>{/if}
  </div>
{/if}

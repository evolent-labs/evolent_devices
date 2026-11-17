<script lang="ts">
  import type { StoreApp } from '$lib/appstore';
  import StoreTile from './StoreTile.svelte';

  let { app, src = '', bar = 20, cls = '' }: { app: StoreApp; src?: string; bar?: number; cls?: string } = $props();

  let broken = $state('');

  const shown = $derived(!!src && broken !== src);
  const tile = $derived(Math.round(bar * 0.62));
  const mark = $derived(Math.round(bar * 0.36));
</script>

<figure class={'ss ' + cls} style:--bar="{bar}px" style:--mark="{mark}px">
  <figcaption class="ss-bar" aria-hidden="true">
    <StoreTile {app} size={tile} />
    <span class="ss-name">{app.label}</span>
    <span class="ss-ctl">
      <svg viewBox="0 0 24 24"><path d="M6 12h12"></path></svg>
      <svg viewBox="0 0 24 24"><path d="M6.5 6.5h11v11h-11z"></path></svg>
      <svg viewBox="0 0 24 24"><path d="M6.5 6.5l11 11M17.5 6.5l-11 11"></path></svg>
    </span>
  </figcaption>
  <div class="ss-view">
    {#if shown}
      <img {src} alt="" draggable="false" onerror={() => (broken = src)} />
    {:else}
      <span class="ss-blank"><StoreTile {app} size={Math.round(bar * 2.6)} /></span>
    {/if}
  </div>
</figure>

<style>
  .ss {
    position: relative;
    display: flex;
    flex-direction: column;
    margin: 0;
    overflow: hidden;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: calc(var(--bar) * 0.5);
    background: #0b0b10;
    box-shadow:
      0 calc(var(--bar) * 1.1) calc(var(--bar) * 2.2) calc(var(--bar) * -0.5) rgba(0, 0, 0, 0.7),
      0 2px 6px rgba(0, 0, 0, 0.35);
  }
  .ss-bar {
    display: flex;
    align-items: center;
    gap: calc(var(--bar) * 0.32);
    height: var(--bar);
    flex-shrink: 0;
    padding: 0 calc(var(--bar) * 0.36);
    border-bottom: 1px solid #1f1f27;
    background: #111117;
    color: #e4e4e7;
  }
  .ss-name {
    overflow: hidden;
    margin-bottom: -0.18em;
    padding-bottom: 0.18em;
    font-size: calc(var(--bar) * 0.4);
    font-weight: 600;
    line-height: 1;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .ss-ctl {
    display: inline-flex;
    gap: calc(var(--bar) * 0.42);
    margin-left: auto;
    padding-right: calc(var(--bar) * 0.1);
    color: #71717a;
  }
  .ss-ctl svg {
    display: block;
    width: var(--mark);
    height: var(--mark);
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
  }
  .ss-view {
    position: relative;
    overflow: hidden;
    background: #0a0a0f;
  }
  img {
    display: block;
    width: 100%;
    height: auto;
    user-select: none;
  }
  .ss-blank {
    aspect-ratio: 16 / 10;
    display: grid;
    place-items: center;
    background:
      repeating-linear-gradient(135deg, rgba(var(--tone-rgb, var(--accent-rgb)), 0.05) 0 1px, transparent 1px 12px),
      #0d0d12;
  }
</style>

<script lang="ts">
  import { rgbOf, type StoreApp } from '$lib/appstore';

  let { app, size = 48 }: { app: StoreApp; size?: number } = $props();

  const tint = $derived(rgbOf(app.icon?.color) || null);
  const letter = $derived(Array.from(app.label)[0]?.toUpperCase() ?? '?');
</script>

<span class="as-tile" style:width="{size}px" style:height="{size}px" style:border-radius="{Math.round(size * 0.27)}px" style:--tint-rgb={tint}>
  {#if app.icon}
    <svg viewBox="0 0 24 24" width={Math.round(size * 0.54)} height={Math.round(size * 0.54)} aria-hidden="true"><path d={app.icon.path}></path></svg>
  {:else}
    <b style:font-size="{Math.round(size * 0.42)}px">{letter}</b>
  {/if}
</span>

<style>
  .as-tile {
    position: relative;
    display: inline-grid;
    place-items: center;
    flex-shrink: 0;
    background: linear-gradient(rgba(var(--tint-rgb), 0.09), rgba(var(--tint-rgb), 0.09)), #111117;
    border: 1px solid rgba(var(--tint-rgb), 0.22);
    color: rgb(var(--tint-rgb));
  }
  svg {
    display: block;
  }
  path {
    fill: currentColor;
    fill-rule: evenodd;
  }
  b {
    font-weight: 600;
    line-height: 1;
  }
</style>

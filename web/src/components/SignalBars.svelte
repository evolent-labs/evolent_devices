<script lang="ts" module>
  let masks = 0;
</script>

<script lang="ts">
  let { bars, wired = false, off = false, size = 24 }: { bars: number; wired?: boolean; off?: boolean; size?: number } = $props();

  const BARS = [
    { x: 2.4, y: 15, height: 6 },
    { x: 7.6, y: 11, height: 10 },
    { x: 12.8, y: 7, height: 14 },
    { x: 18, y: 3, height: 18 },
  ];

  const mask = `signal-cut-${++masks}`;
  const level = $derived(off ? 0 : Math.max(0, Math.min(4, Math.round(bars))));
  const crossed = $derived(level === 0);
</script>

<svg class="sig" class:crossed={!wired && crossed} viewBox="0 0 24 24" style:width="{size}px" style:height="{size}px" aria-hidden="true" data-bars={wired ? 'wired' : level} data-off={!wired && crossed ? (off ? 'wifi' : 'none') : undefined}>
  {#if wired}
    <rect class="lit" x="7.7" y="2.5" width="2.8" height="6.5" rx="1.4"></rect>
    <rect class="lit" x="13.5" y="2.5" width="2.8" height="6.5" rx="1.4"></rect>
    <path class="lit" d="M6.6 8.2h10.8a1 1 0 0 1 1 1v2.3a6.4 6.4 0 0 1-12.8 0V9.2a1 1 0 0 1 1-1z"></path>
    <rect class="lit" x="10.6" y="16.4" width="2.8" height="5.1" rx="1.4"></rect>
  {:else}
    {#if crossed}
      <mask id={mask} maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">
        <rect class="keep" x="0" y="0" width="24" height="24"></rect>
        <path class="gap" d="M3.5 3.5l17 17"></path>
      </mask>
    {/if}
    <g mask={crossed ? `url(#${mask})` : undefined}>
      {#each BARS as bar, index (index)}
        <rect x={bar.x} y={bar.y} width="3.6" height={bar.height} rx="1.8" class:lit={index < level}></rect>
      {/each}
    </g>
    {#if crossed}<path class="slash" class:none={!off} d="M3.5 3.5l17 17"></path>{/if}
  {/if}
</svg>

<style>
  .sig {
    flex-shrink: 0;
    display: block;
  }
  rect,
  path {
    fill: currentColor;
  }
  rect {
    opacity: 0.22;
  }
  rect.lit {
    opacity: 1;
  }
  .crossed rect {
    opacity: 0.34;
  }
  .crossed .keep {
    opacity: 1;
    fill: #fff;
  }
  .gap {
    fill: none;
    stroke: #000;
    stroke-width: 5;
    stroke-linecap: round;
  }
  .slash {
    fill: none;
    stroke: currentColor;
    stroke-width: 2.2;
    stroke-linecap: round;
  }
  .slash.none {
    stroke: #f82834;
  }
</style>

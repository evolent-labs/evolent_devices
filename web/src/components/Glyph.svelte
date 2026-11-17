<script lang="ts">
  let { d, size = 24, stroke = 1.75, fill = false, color = '' }: { d: string; size?: number; stroke?: number; fill?: boolean; color?: string } = $props();
</script>

{#if fill}
  <svg viewBox="0 0 24 24" style={`width:${size}px;height:${size}px`} class="filled" aria-hidden="true"><path {d}></path></svg>
{:else}
  <svg viewBox="0 0 24 24" style={`width:${size}px;height:${size}px;stroke-width:${stroke}` + (color ? `;stroke:${color}` : '')} class="line" aria-hidden="true"><path {d}></path></svg>
{/if}

<style>
  svg {
    flex-shrink: 0;
  }
  .filled {
    fill: currentColor;
    fill-rule: evenodd;
  }
  .line {
    fill: none;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-linejoin: round;
  }
</style>

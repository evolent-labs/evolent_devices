<script lang="ts">
  let { icon, label, size = 28 }: { icon?: { path: string; color: string }; label: string; size?: number } = $props();
</script>

{#if icon}
  <svg class="app-glyph" width={size} height={size} viewBox="0 0 24 24" aria-hidden="true"><path d={icon.path} fill={icon.color} fill-rule="evenodd" clip-rule="evenodd"></path></svg>
{:else}
  <span class="app-glyph letter" style:width="{size}px" style:height="{size}px" style:font-size="{Math.round(size * 0.46)}px">{label.charAt(0).toUpperCase()}</span>
{/if}

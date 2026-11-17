<script lang="ts">
  import Glyph from '$components/Glyph.svelte';

  let { icon, label, size }: { icon?: { path: string; color: string }; label: string; size: number } = $props();
</script>

{#if icon}
  <span class="glyph" style:color={icon.color}><Glyph d={icon.path} {size} fill /></span>
{:else}
  <span class="letter" style:width="{size}px" style:height="{size}px" style:font-size="{Math.round(size * 0.46)}px">{Array.from(label)[0]?.toUpperCase() ?? '?'}</span>
{/if}

<style>
  .glyph {
    display: contents;
  }
  .letter {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    border: 2px solid #a1a1aa;
    border-radius: 28%;
    color: #a1a1aa;
    font-weight: 600;
    line-height: 1;
  }
</style>

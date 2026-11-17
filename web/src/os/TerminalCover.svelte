<script lang="ts">
  import { t } from '$lib/state.svelte';
  import AppIcon from './AppIcon.svelte';
  import BrandMark from '$components/BrandMark.svelte';
  import Wallpaper from '$components/Wallpaper.svelte';
  import { brand, osName } from '$lib/brand.svelte';

  let { cover }: { cover: { label: string; icon?: { path: string; color: string } } | null } = $props();
</script>

<div class="terminal">
  <Wallpaper wall={brand.wallpaper} cls="cover-wall" />
  <div class="shade"></div>
  <div class="card">
    {#if cover}
      <AppIcon icon={cover.icon} label={cover.label} size={88} />
      <p class="what">{t('os_cover_in_use', cover.label)}</p>
    {:else}
      <BrandMark cls="cover-mark" />
      <p class="what">{osName()}</p>
    {/if}
  </div>
</div>

<style>
  .terminal {
    position: fixed;
    inset: 0;
    overflow: hidden;
  }
  .shade {
    position: absolute;
    inset: 0;
    background: rgba(5, 5, 8, 0.72);
  }
  .card {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 22px;
    color: #e4e4e7;
    font-family: Poppins, system-ui, sans-serif;
  }
  .what {
    margin: 0;
    font-size: 34px;
    font-weight: 600;
    letter-spacing: -0.02em;
  }
  .terminal :global(.cover-wall) {
    position: absolute;
    inset: 0;
  }
  .card :global(.cover-mark) {
    width: 88px;
    height: 88px;
    color: var(--accent);
    object-fit: contain;
  }
</style>

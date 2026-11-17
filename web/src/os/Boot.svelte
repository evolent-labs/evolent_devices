<script lang="ts">
  import { t } from '$lib/state.svelte';
  import BrandMark from '$components/BrandMark.svelte';
  import { osName } from '$lib/brand.svelte';

  let { waiting = false }: { waiting?: boolean } = $props();
</script>

<div class="boot">
  {#if !waiting}
    <BrandMark cls="boot-mark" />
    <p class="name">{osName()}</p>
    <div class="bar"><i></i></div>
    <p class="caption">{t('os_starting')}</p>
  {/if}
</div>

<style>
  .boot {
    position: absolute;
    inset: 0;
    z-index: 100;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 22px;
    background: #050508;
  }
  .boot :global(.boot-mark) {
    color: var(--accent);
    width: 84px;
    height: 84px;
    object-fit: contain;
    animation: eos-logo 0.6s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }
  .name {
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.02em;
  }
  .bar {
    width: 240px;
    height: 3px;
    margin-top: 10px;
    background: #1f1f27;
    border-radius: 3px;
    overflow: hidden;
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--accent);
    border-radius: 3px;
    animation: eos-boot 1.7s ease-out forwards;
  }
  .caption {
    font-size: 13px;
    font-weight: 500;
    color: #8b8b95;
  }
</style>

<script lang="ts">
  import { t } from '$lib/state.svelte';
  import BrandMark from '$components/BrandMark.svelte';
  import { osName } from '$lib/brand.svelte';
</script>

<div class="t-boot">
  <BrandMark cls="t-boot-mark" />
  <p class="t-name">{osName()}</p>
  <div class="t-track"><div class="t-bar"></div></div>
  <p class="t-caption">{t('os_starting')}</p>
</div>

<style>
  .t-boot {
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
  .t-boot :global(.t-boot-mark) {
    color: var(--accent);
    width: 84px;
    height: 84px;
    object-fit: contain;
    animation: eot-logo 0.6s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }
  .t-name {
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.02em;
  }
  .t-track {
    width: 240px;
    height: 3px;
    margin-top: 10px;
    background: #1f1f27;
    border-radius: 3px;
    overflow: hidden;
  }
  .t-bar {
    height: 100%;
    background: var(--accent);
    border-radius: 3px;
    animation: eot-boot 1.7s ease-out forwards;
  }
  .t-caption {
    font-size: 13px;
    font-weight: 500;
    color: #8b8b95;
  }
</style>

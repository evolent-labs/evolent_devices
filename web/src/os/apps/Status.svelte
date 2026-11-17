<script lang="ts">
  import { reasonText, t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';

  let {
    icon,
    title,
    text = '',
    reason = '',
    loading = false,
    retry,
  }: { icon: string; title: string; text?: string; reason?: string; loading?: boolean; retry?: () => void } = $props();
</script>

<div class="status">
  <span class="mark" class:pulse={loading}><Glyph d={icon} size={28} stroke={1.5} /></span>
  <p class="title">{title}</p>
  {#if text || reason}<p class="text">{reason ? reasonText({ reason }) : text}</p>{/if}
  {#if reason && retry}<button type="button" class="retry" onclick={retry}>{t('os_app_retry')}</button>{/if}
</div>

<style>
  .status {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
    padding: 24px;
    text-align: center;
    color: #52525b;
  }
  .mark {
    display: grid;
    place-items: center;
  }
  .pulse {
    animation: eos-pulse 1.4s ease-in-out infinite;
  }
  .title {
    font-size: 14px;
    font-weight: 600;
    color: #a1a1aa;
  }
  .text {
    max-width: 420px;
    font-size: 13px;
    color: #71717a;
  }
  .title + .text {
    margin-top: calc(var(--sub-pull) - 10px);
    line-height: var(--sub-lh);
  }
  .retry {
    height: 36px;
    margin-top: 6px;
    padding: 0 14px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 8px;
    color: var(--accent);
    font: 600 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .retry:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
</style>

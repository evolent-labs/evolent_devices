<script lang="ts">
  import { plural, t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { watching } from './params';
  import { os } from './store.svelte';
  import { clockText, dateLong } from './text';

  let { onunlock }: { onunlock: () => void } = $props();

  const count = $derived(watching ? os.remote.notices : os.notices.length);
</script>

<div class="lock" role="button" tabindex="-1" onclick={onunlock}>
  {#if os.lockName}<p class="owner">{os.lockName}</p>{/if}
  <p class="clock">{clockText(os.wall, os.prefs.clock24, os.prefs.seconds)}</p>
  <p class="date">{dateLong(os.wall, os.prefs.dateFormat)}</p>
  {#if count > 0}
    <div class="pill"><span class="bell"><Glyph d={IC.bell} size={16} /></span><span>{plural('os_notifications_count', count)}</span></div>
  {/if}
  <p class="hint">{t('os_unlock_hint')}</p>
</div>

<style>
  .lock {
    position: absolute;
    inset: 0;
    z-index: 100;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: rgba(5, 5, 8, 0.45);
    cursor: pointer;
    animation: eos-fade 0.3s;
  }
  .owner {
    margin-bottom: 22px;
    max-width: 80%;
    overflow: hidden;
    font: 600 18px/1.2 'JetBrains Mono', monospace;
    letter-spacing: 3px;
    text-transform: uppercase;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--accent);
    animation: eos-up 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }
  .clock {
    font-size: 136px;
    font-weight: 600;
    line-height: 1;
    letter-spacing: -0.05em;
    font-variant-numeric: tabular-nums;
    animation: eos-up 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }
  .date {
    margin-top: var(--sub-pull);
    font-size: 22px;
    font-weight: 500;
    line-height: var(--sub-lh);
    animation: eos-up 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) 0.08s both;
  }
  .pill {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 44px;
    padding: 10px 16px;
    background: rgba(15, 15, 21, 0.7);
    border: 1px solid #2a2a35;
    border-radius: 12px;
    backdrop-filter: blur(16px);
    font-size: 13px;
    font-weight: 500;
  }
  .bell {
    display: flex;
    color: var(--accent);
  }
  .hint {
    position: absolute;
    bottom: 56px;
    font-size: 14px;
    font-weight: 500;
    color: #a1a1aa;
  }
</style>

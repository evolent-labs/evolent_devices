<script lang="ts">
  import { t } from '$lib/state.svelte';
  import AppIcon from './AppIcon.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { watching } from './params';
  import { actOnNotice, appOf, clearNotices, dismissNotice, onDevice, originOf, os } from './store.svelte';
  import { agoText } from './text';
  import type { OsNotice } from './shell';

  const bones = $derived(Array.from({ length: Math.min(os.remote.notices, 6) }, (_, index) => index));
  const empty = $derived(watching ? os.remote.notices === 0 : os.notices.length === 0);

  function act(event: MouseEvent, notice: OsNotice) {
    actOnNotice(notice, originOf(event.currentTarget as Element));
  }
</script>

<aside class="centre" class:out={os.notifOut} data-pop="n" onmousedown={(event) => event.stopPropagation()}>
  <div class="head">
    <p>{t('os_notifications')}</p>
    {#if !empty}<button type="button" onclick={clearNotices}>{t('os_clear_all')}</button>{/if}
  </div>
  <div class="list">
    {#if watching}
      {#each bones as index (index)}
        <div class="note"><span class="glyph"><i class="bone dot"></i></span><div class="body"><i class="bone title-bone"></i><i class="bone text-bone"></i></div></div>
      {/each}
    {:else}
      {#each os.notices as notice (notice.id)}
        {@const app = appOf(notice.app)}
        <div class="note">
          <span class="glyph"><AppIcon icon={app?.icon ?? notice.icon} label={app?.label ?? (notice.label || notice.app)} size={30} /></span>
          <div class="body">
            <div class="top"><span class="title">{notice.title}</span><span class="time mono">{agoText(notice.at, Date.now())}</span></div>
            {#if notice.body}<p class="text">{notice.body}</p>{/if}
            {#if notice.action && onDevice(notice.app)}<button type="button" class="action" onclick={(event) => act(event, notice)}>{notice.action}</button>{/if}
          </div>
          <button type="button" class="dismiss" aria-label={t('os_dismiss')} onclick={() => dismissNotice(notice.id)}><Glyph d={IC.x} size={12} stroke={2} /></button>
        </div>
      {/each}
    {/if}
    {#if empty}
      <div class="caught-up"><Glyph d={IC.bell} size={28} stroke={1.5} /><p>{t('os_caught_up')}</p></div>
    {/if}
  </div>
</aside>

<style>
  .centre {
    position: absolute;
    right: 12px;
    bottom: 92px;
    z-index: 70;
    display: flex;
    flex-direction: column;
    width: 460px;
    max-height: calc(100% - 104px);
    background: rgba(12, 12, 17, 0.94);
    border: 1px solid #2a2a35;
    border-radius: 18px;
    backdrop-filter: blur(24px);
    overflow: hidden;
    animation: eos-slide 0.24s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .centre.out {
    animation: eos-slide-out 0.15s ease-in forwards;
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 44px;
    padding: 14px 18px 4px;
  }
  .head p {
    font-size: 16px;
    font-weight: 600;
  }
  .head button {
    padding: 0;
    background: transparent;
    border: 0;
    color: #a1a1aa;
    font: 500 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .head button:hover {
    color: #e4e4e7;
  }
  .list {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 4px 8px 12px;
  }
  .note {
    display: flex;
    align-items: flex-start;
    gap: 14px;
    padding: 14px 12px;
    border-radius: 12px;
  }
  .note:hover {
    background: #13131a;
  }
  .glyph {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    flex-shrink: 0;
  }
  .body {
    flex: 1;
    min-width: 0;
  }
  .top {
    display: flex;
    justify-content: space-between;
    gap: 10px;
  }
  .title {
    font-size: 14px;
    font-weight: 600;
  }
  .time {
    font-size: 11px;
    line-height: 1.4;
    color: #8b8b95;
    white-space: nowrap;
  }
  .text {
    margin-top: var(--sub-pull);
    font-size: 13px;
    line-height: var(--sub-lh);
    color: #a1a1aa;
  }
  .action {
    height: 30px;
    margin-top: 8px;
    padding: 0 12px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 7px;
    color: var(--accent);
    font: 600 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .action:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .dismiss {
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    flex-shrink: 0;
    padding: 0;
    background: transparent;
    border: 0;
    border-radius: 6px;
    color: #8b8b95;
    cursor: pointer;
  }
  .dismiss:hover {
    color: #e4e4e7;
    background: #1f1f27;
  }
  .bone {
    display: block;
    background: rgba(255, 255, 255, 0.08);
    border-radius: 6px;
  }
  .bone.dot {
    width: 30px;
    height: 30px;
    border-radius: 9px;
  }
  .title-bone {
    width: 180px;
    height: 14px;
    margin-top: 3px;
  }
  .text-bone {
    width: 280px;
    height: 11px;
    margin-top: 10px;
  }
  .caught-up {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 60px 0;
    color: #8b8b95;
  }
  .caught-up p {
    font-size: 13px;
  }
</style>

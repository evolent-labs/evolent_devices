<script lang="ts">
  import { t } from '$lib/state.svelte';
  import { IC } from '$lib/tablet/icons';
  import { agoText, appOf, clearNotices, dismissNotice, noticeAction, tablet } from '$lib/tablet/store.svelte';
  import Glyph from '$components/Glyph.svelte';
</script>

<aside class="t-shade" class:t-out={tablet.popOut} data-pop="n">
  <div class="t-head">
    <p class="t-title">{t('os_notifications')}</p>
    {#if tablet.notices.length}<button type="button" class="t-clear" onclick={clearNotices}>{t('os_clear_all')}</button>{/if}
  </div>
  <div class="t-list">
    {#each tablet.notices as notice (notice.id)}
      {@const entry = appOf(notice.app)}
      {@const icon = entry?.icon ?? notice.icon}
      <div class="t-item">
        <span class="t-glyph" style:color={icon?.color ?? '#a1a1aa'}>{#if icon}<svg viewBox="0 0 24 24" class="fill" aria-hidden="true"><path d={icon.path}></path></svg>{/if}</span>
        <div class="t-text">
          <div class="t-row"><span class="t-name">{notice.title}</span><span class="t-time mono">{agoText(notice.at)}</span></div>
          <p class="t-body">{notice.body}</p>
          {#if notice.action && entry}<button type="button" class="t-act" onclick={() => noticeAction(notice)}>{notice.action}</button>{/if}
        </div>
        <button type="button" class="t-dismiss" aria-label={t('os_dismiss')} onclick={() => dismissNotice(notice.id)}><Glyph d={IC.x} size={12} stroke={2} /></button>
      </div>
    {:else}
      <div class="t-empty"><Glyph d={IC.bell} size={28} stroke={1.5} /><p>{t('os_caught_up')}</p></div>
    {/each}
  </div>
</aside>

<style>
  .t-shade {
    position: absolute;
    top: 52px;
    left: 16px;
    z-index: 72;
    display: flex;
    flex-direction: column;
    width: 460px;
    max-height: 770px;
    background: rgba(12, 12, 17, 0.94);
    border: 1px solid #2a2a35;
    border-radius: 18px;
    backdrop-filter: blur(24px);
    overflow: hidden;
    animation: eot-drop 0.22s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .t-shade.t-out {
    animation: eot-drop-out 0.15s ease-in forwards;
  }
  .t-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 54px;
    padding: 16px 18px 6px;
  }
  .t-title {
    font-size: 16px;
    font-weight: 600;
  }
  .t-clear {
    height: 32px;
    padding: 0 10px;
    background: transparent;
    border: 0;
    border-radius: 8px;
    color: #a1a1aa;
    font: 500 12px/1 'Poppins', system-ui, sans-serif;
    cursor: pointer;
  }
  .t-clear:hover {
    color: #e4e4e7;
  }
  .t-list {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 4px 8px 12px;
  }
  .t-item {
    display: flex;
    align-items: flex-start;
    gap: 14px;
    padding: 14px 12px;
    border-radius: 12px;
  }
  .t-item:hover {
    background: #13131a;
  }
  .t-glyph {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    flex-shrink: 0;
  }
  .t-glyph svg {
    width: 30px;
    height: 30px;
  }
  .t-text {
    flex: 1;
    min-width: 0;
  }
  .t-row {
    display: flex;
    justify-content: space-between;
    gap: 10px;
  }
  .t-name {
    font-size: 14px;
    font-weight: 600;
  }
  .t-time {
    font: 500 11px/1.4 'JetBrains Mono', monospace;
    color: #8b8b95;
    white-space: nowrap;
  }
  .t-body {
    margin-top: var(--sub-pull);
    font-size: 13px;
    line-height: var(--sub-lh);
    color: #a1a1aa;
  }
  .t-act {
    height: 34px;
    margin-top: 8px;
    padding: 0 12px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 8px;
    color: var(--accent);
    font: 600 12px/1 'Poppins', system-ui, sans-serif;
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .t-act:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .t-dismiss {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    flex-shrink: 0;
    padding: 1px 6px;
    background: transparent;
    border: 0;
    border-radius: 7px;
    color: #8b8b95;
    cursor: pointer;
  }
  .t-dismiss:hover {
    color: #e4e4e7;
    background: #1f1f27;
  }
  .t-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 60px 0;
    color: #8b8b95;
  }
  .t-empty p {
    font-size: 13px;
  }
</style>

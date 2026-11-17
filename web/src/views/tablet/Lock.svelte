<script lang="ts">
  import { t } from '$lib/state.svelte';
  import { agoText, appOf, tablet, toLogin } from '$lib/tablet/store.svelte';

  let { clock, date }: { clock: string; date: string } = $props();

  const shown = $derived(tablet.notices.slice(0, 3));
  const more = $derived(Math.max(0, tablet.notices.length - 3));
</script>

<div class="t-lock" onclick={toLogin}>
  <p class="t-clock">{clock}</p>
  <p class="t-date">{date}</p>
  <div class="t-cards">
    {#each shown as notice (notice.id)}
      {@const entry = appOf(notice.app)}
      {@const icon = entry?.icon ?? notice.icon}
      <div class="t-card">
        <span class="t-glyph" style:color={icon?.color ?? '#a1a1aa'}>{#if icon}<svg viewBox="0 0 24 24" class="fill" aria-hidden="true"><path d={icon.path}></path></svg>{/if}</span>
        <div class="t-text">
          <div class="t-row"><span class="t-name">{notice.title}</span><span class="t-time mono">{agoText(notice.at)}</span></div>
          <p class="t-body">{notice.body}</p>
        </div>
      </div>
    {/each}
    {#if more > 0}<p class="t-more">{t('os_more_notices', more)}</p>{/if}
  </div>
  <p class="t-hint">{t('os_tap_to_unlock')}</p>
</div>

<style>
  .t-lock {
    position: absolute;
    inset: 0;
    z-index: 100;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-top: 104px;
    background: rgba(5, 5, 8, 0.45);
    cursor: pointer;
    animation: eot-fade 0.3s;
  }
  .t-clock {
    font-size: 128px;
    font-weight: 600;
    line-height: 1;
    letter-spacing: -0.05em;
    font-variant-numeric: tabular-nums;
    animation: eot-up 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }
  .t-date {
    margin-top: var(--sub-pull);
    font-size: 22px;
    font-weight: 500;
    line-height: var(--sub-lh);
    animation: eot-up 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) 0.08s both;
  }
  .t-cards {
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: 540px;
    margin-top: 40px;
    animation: eot-up 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) 0.16s both;
  }
  .t-card {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 16px;
    background: rgba(15, 15, 21, 0.72);
    border: 1px solid #2a2a35;
    border-radius: 16px;
    backdrop-filter: blur(16px);
  }
  .t-glyph {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
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
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .t-more {
    margin-top: 4px;
    text-align: center;
    font-size: 12px;
    font-weight: 500;
    color: #a1a1aa;
  }
  .t-hint {
    position: absolute;
    bottom: 40px;
    font-size: 14px;
    font-weight: 500;
    color: #a1a1aa;
  }
</style>

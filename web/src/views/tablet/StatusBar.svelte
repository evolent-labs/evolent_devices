<script lang="ts">
  import SignalBars from '$components/SignalBars.svelte';
  import { t } from '$lib/state.svelte';
  import BrandMark from '$components/BrandMark.svelte';
  import { IC } from '$lib/tablet/icons';
  import { tablet, togglePop } from '$lib/tablet/store.svelte';
  import Glyph from '$components/Glyph.svelte';

  let { clock, date }: { clock: string; date: string } = $props();

  const count = $derived(tablet.notices.length);

  const signalLabel = $derived(
    tablet.signal.wired
      ? t('os_signal_wired')
      : !tablet.set.wifi
        ? t('os_wifi_off')
        : tablet.signal.bars === 0 ? t('os_signal_none') : t('os_signal_bars', tablet.signal.bars),
  );
</script>

<header class="t-bar">
  <div class="t-side">
    {#if tablet.cur !== null}<button type="button" class="t-pill t-mark" class:t-held={tablet.pop === 'ov'} data-pop="o" aria-label={t('os_open_apps_button')} onclick={() => togglePop('ov')}><BrandMark cls="t-mark-glyph" /></button>{/if}
    <button type="button" class="t-pill" class:t-held={tablet.pop === 'notif'} data-pop="n" aria-label={t('os_notifications')} onclick={() => togglePop('notif')}>
      <Glyph d={IC.bell} size={20} stroke={2} />
      {#if count > 0}<span class="t-badge mono">{count}</span>{/if}
    </button>
  </div>
  <div class="t-time"><span class="t-clock mono">{clock}</span><span class="t-date">{date}</span></div>
  <div class="t-side t-end">
    <button type="button" class="t-pill t-cc" class:t-held={tablet.pop === 'cc'} data-pop="c" aria-label={t('os_control_center')} onclick={() => togglePop('cc')}>
      {#if tablet.set.dnd}<Glyph d={IC.moon} size={18} stroke={2} color="var(--accent)" />{/if}
      <span class="t-signal" title={signalLabel} data-signal={tablet.signal.wired ? 'wired' : tablet.signal.bars}><SignalBars bars={tablet.signal.bars} wired={tablet.signal.wired} off={!tablet.set.wifi} size={20} /></span>
      <Glyph d={tablet.set.sound ? IC.volume : IC.volumeOff} size={20} stroke={2} color={tablet.set.sound ? '#e4e4e7' : '#a1a1aa'} />
      <span class="t-power">
        <span class="t-battery-label mono">{tablet.battery}%</span>
        <svg class="t-battery" class:t-low={tablet.battery <= 20} viewBox="0 0 28 24" aria-hidden="true">
          <rect class="t-body" x="2" y="6.5" width="21" height="11" rx="3"></rect>
          <path class="t-cap" d="M25.5 10.25v3.5"></path>
          {#if tablet.battery > 0}<rect class="t-level" x="4.5" y="9" width={Math.max(1.5, (16 * tablet.battery) / 100)} height="6" rx="1.25"></rect>{/if}
        </svg>
      </span>
    </button>
  </div>
</header>

<style>
  .t-bar {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    z-index: 60;
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    height: 44px;
    padding: 0 14px;
    background: rgba(10, 10, 15, 0.82);
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    backdrop-filter: blur(24px);
    color: #e4e4e7;
  }
  .t-side {
    display: flex;
    justify-content: flex-start;
  }
  .t-side.t-end {
    justify-content: flex-end;
  }
  .t-pill {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 12px;
    background: transparent;
    border: 0;
    border-radius: 10px;
    color: #e4e4e7;
    cursor: pointer;
  }
  .t-pill.t-cc {
    gap: 12px;
  }
  .t-pill.t-mark {
    padding: 0 10px;
  }
  .t-mark :global(.t-mark-glyph) {
    color: var(--accent);
    width: 22px;
    height: 22px;
    object-fit: contain;
  }
  .t-pill:focus-visible {
    outline: 0;
  }
  .t-pill:hover {
    background: rgba(255, 255, 255, 0.1);
  }
  .t-pill.t-held {
    background: rgba(255, 255, 255, 0.12);
  }
  .t-badge {
    min-width: 20px;
    height: 20px;
    padding: 0 6px;
    background: var(--accent);
    border-radius: 10px;
    color: var(--accent-content);
    font: 600 12px/20px 'JetBrains Mono', monospace;
    text-align: center;
  }
  .t-time {
    display: flex;
    align-items: baseline;
    gap: 10px;
  }
  .t-clock {
    font: 600 17px/1 'JetBrains Mono', monospace;
    font-variant-numeric: tabular-nums;
  }
  .t-date {
    font-size: 14px;
    font-weight: 500;
    color: #d4d4d8;
  }
  .t-signal {
    display: flex;
    color: #e4e4e7;
  }
  .t-power {
    display: flex;
    align-items: center;
    gap: 5px;
  }
  .t-battery-label {
    font: 500 14px/1 'JetBrains Mono', monospace;
    font-variant-numeric: tabular-nums;
  }
  .t-battery {
    flex-shrink: 0;
    width: 23px;
    height: 20px;
    color: #e4e4e7;
  }
  .t-body,
  .t-cap {
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
  }
  .t-body {
    opacity: 0.85;
  }
  .t-level {
    fill: currentColor;
  }
  .t-low .t-level {
    fill: #f82834;
  }
</style>

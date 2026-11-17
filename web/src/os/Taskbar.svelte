<script lang="ts">
  import SignalBars from '$components/SignalBars.svelte';
  import { t } from '$lib/state.svelte';
  import AppIcon from './AppIcon.svelte';
  import Glyph from '$components/Glyph.svelte';
  import BrandMark from '$components/BrandMark.svelte';
  import { IC } from './icons';
  import { watching } from './params';
  import {
    appOf,
    closePopovers,
    focusWindow,
    layout,
    minimizeWindow,
    originOf,
    os,
    restoreWindow,
    toggleLauncher,
    toggleNotifications,
    toggleWifi,
    topWindow,
  } from './store.svelte';
  import { clockText, dateShort } from './text';

  const count = $derived(watching ? os.remote.notices : os.notices.length);
  const top = $derived(topWindow());
  const pills = $derived(os.wins.filter((win) => !win.closing));

  const signalLabel = $derived(
    os.signal.wired
      ? t('os_signal_wired')
      : !os.toggles.wifi
        ? t('os_wifi_off')
        : os.signal.bars === 0 ? t('os_signal_none') : t('os_signal_bars', os.signal.bars),
  );

  function toggleSound(event: MouseEvent) {
    if (watching) return;

    if (os.soundPop) {
      closePopovers();

      return;
    }

    const spot = originOf(event.currentTarget as Element);

    closePopovers(() => (os.soundPop = { x: spot?.x ?? layout.width - 260 }));
  }

  function task(event: MouseEvent, id: string) {
    const win = os.wins.find((entry) => entry.id === id);

    if (!win || win.closing) return;

    if (win.min) restoreWindow(id, originOf(event.currentTarget as Element));
    else if (top !== id) focusWindow(id);
    else minimizeWindow(id);
  }
</script>

<nav class="taskbar">
  <div class="start">
    <button type="button" class="launcher" class:open={os.launcher} data-pop="l" aria-label={t('os_launcher')} onclick={toggleLauncher}><BrandMark cls="launch-mark" /></button>
    <span class="divider"></span>
    {#each pills as win (win.id)}
      {@const app = appOf(win.id)}
      <button type="button" class="pill" class:focused={top === win.id} class:min={win.min} data-task={win.id} title={app?.label ?? win.id} onclick={(event) => task(event, win.id)}>
        <span class="glyph"><AppIcon icon={app?.icon} label={app?.label ?? win.id} size={26} /></span>{app?.label ?? win.id}
      </button>
    {/each}
  </div>
  <div class="status">
    <button type="button" class="quick signal" class:off={!os.signal.wired && (!os.toggles.wifi || os.signal.bars === 0)} title={signalLabel} aria-label={signalLabel} data-signal={os.signal.wired ? 'wired' : os.signal.bars} onclick={toggleWifi}>
      <SignalBars bars={os.signal.bars} wired={os.signal.wired} off={!os.toggles.wifi} size={24} />
    </button>
    <button type="button" class="quick" class:off={!os.toggles.sound} class:open={os.soundPop !== null} data-pop="s" aria-label={t('os_sound')} title={t('os_sound_level', os.prefs.volume)} onclick={toggleSound}><Glyph d={os.toggles.sound ? IC.volume : IC.volumeOff} size={24} stroke={2} /></button>
    {#if os.toggles.dnd}<span class="moon"><Glyph d={IC.moon} size={24} stroke={2} /></span>{/if}
    <span class="divider wide"></span>
    <button type="button" class="clock" class:open={os.notif} data-pop="n" aria-label={t('os_notifications')} onclick={toggleNotifications}>
      <span class="time"><span class="hm mono">{clockText(os.wall, os.prefs.clock24, os.prefs.seconds)}</span><span class="day">{dateShort(os.wall, os.prefs.dateFormat)}</span></span>
      <span class="bell"><Glyph d={IC.bell} size={24} stroke={2} />{#if count > 0}<i></i>{/if}</span>
    </button>
  </div>
</nav>

<style>
  .taskbar {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 60;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    height: 80px;
    padding: 0 14px;
    background: rgba(10, 10, 15, 0.82);
    border-top: 1px solid rgba(255, 255, 255, 0.08);
  }
  .start {
    display: flex;
    align-items: stretch;
    align-self: stretch;
    gap: 6px;
    min-width: 0;
  }
  .launcher {
    display: grid;
    place-items: center;
    align-self: center;
    width: 56px;
    height: 56px;
    margin-right: 8px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 12px;
    cursor: pointer;
    transition: transform 0.15s;
  }
  .launcher.open {
    background: #17171f;
    border-color: var(--accent);
  }
  .launcher:hover {
    transform: translateY(-4px);
  }
  .launcher :global(.launch-mark) {
    color: var(--accent);
    width: 28px;
    height: 28px;
    object-fit: contain;
  }
  .divider {
    align-self: center;
    width: 1px;
    height: 36px;
    margin: 0 8px 0 0;
    background: rgba(255, 255, 255, 0.1);
  }
  .divider.wide {
    margin: 0 6px;
  }
  .pill {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 2px 16px 0;
    background: transparent;
    border: 0;
    border-bottom: 2px solid transparent;
    color: #a1a1aa;
    font: 500 14px/1 Poppins, system-ui, sans-serif;
    white-space: nowrap;
    cursor: pointer;
  }
  .pill.focused {
    border-bottom-color: var(--accent);
    color: #e4e4e7;
  }
  .pill.min {
    color: #71717a;
  }
  .pill:hover {
    color: #e4e4e7;
  }
  .glyph {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
  }
  .pill.min .glyph {
    opacity: 0.55;
  }
  .status {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 4px;
  }
  .quick {
    display: grid;
    place-items: center;
    width: 46px;
    height: 46px;
    background: transparent;
    border: 0;
    border-radius: 12px;
    color: #e4e4e7;
    cursor: pointer;
  }
  .quick.off {
    color: #a1a1aa;
  }
  .quick:hover,
  .quick.open,
  .clock:hover,
  .clock.open {
    background: rgba(255, 255, 255, 0.08);
  }
  .moon {
    display: grid;
    place-items: center;
    width: 46px;
    height: 46px;
    color: var(--accent);
  }
  .clock {
    display: flex;
    align-items: center;
    gap: 14px;
    height: 56px;
    padding: 0 12px 0 14px;
    background: transparent;
    border: 0;
    border-radius: 14px;
    color: #e4e4e7;
    text-align: left;
    cursor: pointer;
  }
  .time {
    display: flex;
    flex-direction: column;
  }
  .hm {
    font: 600 17px/1 'JetBrains Mono', monospace;
    font-variant-numeric: tabular-nums;
  }
  .day {
    font-size: 12px;
    line-height: 1.2;
    color: #a1a1aa;
  }
  .bell {
    position: relative;
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
  }
  .bell i {
    position: absolute;
    top: 0;
    right: 0;
    width: 10px;
    height: 10px;
    background: var(--accent);
    border: 2px solid #15151c;
    border-radius: 50%;
  }
</style>

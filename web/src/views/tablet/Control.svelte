<script lang="ts">
  import SignalBars from '$components/SignalBars.svelte';
  import { t } from '$lib/state.svelte';
  import { initials } from '$lib/tablet/clock';
  import { COLOURS } from '$lib/tablet/frame';
  import { IC } from '$lib/tablet/icons';
  import { colourLabel, lock, pickColour, powerOff, restart, setSetting, sleepMinutes, sleepNow, tablet } from '$lib/tablet/store.svelte';
  import Glyph from '$components/Glyph.svelte';

  const quick = $derived([
    { key: 'wifi' as const, label: t('os_wifi'), icon: '', on: tablet.set.wifi },
    {
      key: 'sound' as const,
      label: t('os_sound'),
      icon: tablet.set.sound ? IC.volume : IC.volumeOff,
      on: tablet.set.sound,
    },
    { key: 'dnd' as const, label: t('os_dnd'), icon: IC.moon, on: tablet.set.dnd },
  ]);

  function bright(event: MouseEvent) {
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();

    setSetting('bright', Math.max(30, Math.min(100, Math.round(((event.clientX - rect.left) / rect.width) * 100))));
  }
</script>

<aside class="t-cc" class:t-out={tablet.popOut} data-pop="c">
  <div class="t-user">
    <span class="t-avatar">{initials(tablet.user.name)}</span>
    <span class="t-who">
      <span class="t-name">{tablet.user.name}</span>
      {#if tablet.user.role || tablet.user.org}
        <span class="t-role">{#if tablet.user.role}<span class="t-chip">{tablet.user.role}</span>{/if}{#if tablet.user.org}<span class="t-org">{tablet.user.org}</span>{/if}</span>
      {/if}
    </span>
    <span class="t-battery mono">{tablet.battery}%</span>
  </div>
  <div class="t-quick">
    {#each quick as toggle (toggle.key)}
      <button type="button" class="t-toggle" class:t-on={toggle.on} aria-pressed={toggle.on} onclick={() => setSetting(toggle.key, !toggle.on)}>
        <span class="t-disc">{#if toggle.key === 'wifi'}<SignalBars bars={tablet.signal.bars} wired={tablet.signal.wired} off={!tablet.set.wifi} size={18} />{:else}<Glyph d={toggle.icon} size={18} stroke={1.75} />{/if}</span>
        <span class="t-words"><span class="t-label">{toggle.label}</span><span class="t-state">{toggle.on ? t('os_on') : t('os_off')}</span></span>
      </button>
    {/each}
    <button type="button" class="t-toggle" onclick={sleepNow}>
      <span class="t-disc"><Glyph d={IC.sleep} size={18} stroke={1.75} /></span>
      <span class="t-words"><span class="t-label">{t('os_sleep_now')}</span><span class="t-state">{sleepMinutes() ? t('os_sleep_after', sleepMinutes()) : t('os_sleep_never')}</span></span>
    </button>
  </div>
  <div class="t-card">
    <div class="t-card-row"><span class="t-card-label">{t('os_brightness')}</span><span class="t-value mono">{tablet.set.bright}%</span></div>
    <div class="t-track" onclick={bright}><span class="t-fill-bar" style:width="{tablet.set.bright}%"></span><span class="t-sun"><Glyph d={IC.sun} size={18} stroke={1.75} /></span></div>
  </div>
  {#if tablet.recolour}
    <div class="t-card">
      <div class="t-card-row"><span class="t-card-label">{t('os_tablet_colour')}</span><span class="t-value">{colourLabel(tablet.colour)}</span></div>
      <div class="t-swatches">
        {#each COLOURS as colour, index (colour.id)}
          <button type="button" class="t-swatch" class:t-on={tablet.colour === index} style:background={colour.hex} aria-label={colourLabel(index)} aria-pressed={tablet.colour === index} onclick={() => pickColour(index)}></button>
        {/each}
      </div>
    </div>
  {/if}
  <div class="t-foot">
    <button type="button" class="t-act" onclick={lock}><Glyph d={IC.lock} size={15} stroke={1.75} />{t('os_lock')}</button>
    <button type="button" class="t-act" onclick={restart}><Glyph d={IC.restart} size={15} stroke={1.75} />{t('os_restart')}</button>
    <button type="button" class="t-act t-danger" onclick={powerOff}><Glyph d={IC.power} size={15} stroke={1.75} />{t('os_power_off')}</button>
  </div>
</aside>

<style>
  .t-cc {
    position: absolute;
    top: 52px;
    right: 16px;
    z-index: 72;
    display: flex;
    flex-direction: column;
    gap: 14px;
    width: 400px;
    padding: 16px;
    background: rgba(12, 12, 17, 0.94);
    border: 1px solid #2a2a35;
    border-radius: 18px;
    backdrop-filter: blur(24px);
    animation: eot-drop 0.22s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .t-cc.t-out {
    animation: eot-drop-out 0.15s ease-in forwards;
  }
  .t-user {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 2px 2px 0;
  }
  .t-avatar {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    background: var(--accent);
    border-radius: 50%;
    color: var(--accent-content);
    font: 600 13px/1 'Poppins', system-ui, sans-serif;
  }
  .t-who {
    flex: 1;
    min-width: 0;
  }
  .t-name {
    display: block;
    font-size: 14px;
    font-weight: 600;
    line-height: 1.3;
  }
  .t-role {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    height: 20px;
    font-size: 12px;
    color: #a1a1aa;
  }
  .t-chip {
    flex-shrink: 0;
    padding: 0 5px;
    background: #17171f;
    border: 1px solid #2a2a35;
    border-radius: 5px;
    font: 500 11px/16px 'Poppins', system-ui, sans-serif;
    color: #a1a1aa;
  }
  .t-org {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .t-battery {
    font: 500 11px/1 'JetBrains Mono', monospace;
    color: #8b8b95;
  }
  .t-quick {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
  }
  .t-toggle {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 64px;
    padding: 0 14px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 14px;
    color: #a1a1aa;
    text-align: left;
    cursor: pointer;
  }
  .t-toggle.t-on {
    background: var(--accent-bg);
    border-color: var(--accent-strong);
    color: var(--accent);
  }
  .t-disc {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    flex-shrink: 0;
    background: #17171f;
    border-radius: 50%;
  }
  .t-toggle.t-on .t-disc {
    background: rgba(var(--accent-rgb), 0.14);
  }
  .t-words {
    min-width: 0;
  }
  .t-label {
    display: block;
    margin-bottom: var(--title-pull);
    font-size: 13px;
    font-weight: 600;
    line-height: var(--title-lh);
    color: #e4e4e7;
    white-space: nowrap;
  }
  .t-state {
    display: block;
    font-size: 11px;
    line-height: var(--sub-lh);
  }
  .t-card {
    padding: 14px;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 14px;
  }
  .t-card-row {
    display: flex;
    justify-content: space-between;
    font-size: 12px;
  }
  .t-card-label {
    font-weight: 600;
  }
  .t-value {
    color: #a1a1aa;
  }
  .t-track {
    position: relative;
    height: 36px;
    margin-top: 10px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 10px;
    overflow: hidden;
    cursor: pointer;
  }
  .t-fill-bar {
    position: absolute;
    top: 0;
    left: 0;
    bottom: 0;
    background: rgba(228, 228, 231, 0.16);
    border-right: 2px solid #e4e4e7;
  }
  .t-sun {
    position: absolute;
    top: 9px;
    left: 10px;
    display: flex;
    color: #a1a1aa;
  }
  .t-swatches {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(32px, 1fr));
    justify-items: center;
    row-gap: 8px;
    margin-top: 12px;
  }
  .t-swatch {
    width: 26px;
    height: 26px;
    padding: 0;
    border: 0;
    border-radius: 50%;
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.16);
    cursor: pointer;
    transition: box-shadow 0.16s;
  }
  .t-swatch:hover {
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.16), 0 0 0 2px #0f0f15, 0 0 0 3px #3a3a45;
  }
  .t-swatch.t-on {
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.16), 0 0 0 2px #0f0f15, 0 0 0 4px var(--accent);
  }
  .t-foot {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 6px;
  }
  .t-act {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 44px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 10px;
    color: #e4e4e7;
    font: 500 13px/1 'Poppins', system-ui, sans-serif;
    cursor: pointer;
  }
  .t-act:hover {
    border-color: #52525b;
  }
  .t-act.t-danger {
    border-color: #3a1a1f;
    color: #f82834;
  }
</style>

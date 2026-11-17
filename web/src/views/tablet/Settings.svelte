<script lang="ts">
  import PasswordForm from '$components/PasswordForm.svelte';
  import Wallpaper from '$components/Wallpaper.svelte';
  import { brand, osName, wallName, wallpapers } from '$lib/brand.svelte';
  import { t } from '$lib/state.svelte';
  import { initials } from '$lib/tablet/clock';
  import { SCREEN } from '$lib/tablet/frame';
  import { host } from '$lib/tablet/host';
  import { appOf, homeApps, LOCK_CHOICES, say, setGame, setPasswordOn, setSetting, SLEEP_CHOICES, tablet } from '$lib/tablet/store.svelte';
  import Slider from '../../os/Slider.svelte';
  import Toggle from '../../os/apps/Toggle.svelte';
  import { FI, IC } from '../../os/icons';
  import Glyph from '$components/Glyph.svelte';

  type Section = 'appearance' | 'account' | 'notifications' | 'display' | 'about';

  const SECTIONS: { id: Section; icon: string }[] = [
    { id: 'appearance', icon: IC.image },
    { id: 'account', icon: IC.user },
    { id: 'notifications', icon: IC.bell },
    { id: 'display', icon: IC.monitor },
    { id: 'about', icon: IC.info },
  ];

  const minutes = (value: number) => (value ? t('os_minutes_short', value) : t('os_never'));
  const sleepText = (value: number) => (value < 0 ? (tablet.rest.after ? t('os_sleep_default', tablet.rest.after) : t('os_sleep_default_never')) : minutes(value));

  let section = $state<Section>('account');

  const system = $derived(tablet.system);
  const hosted = $derived(homeApps().filter((app) => !app.builtin));
  const gear = $derived(appOf('settings')?.icon);
  const walls = $derived(['', ...wallpapers()]);

  function mute(id: string) {
    const muted = { ...tablet.set.muted };

    if (muted[id]) delete muted[id];
    else muted[id] = true;

    setSetting('muted', muted);
  }

  function passwordCall(action: 'set' | 'clear', data: Record<string, string>) {
    return host.os('password', action, data);
  }
</script>

<div class="t-set">
  <aside class="t-side">
    <p class="t-head"><span class="t-gear" style:color={gear?.color ?? '#a1a1aa'}><svg viewBox="0 0 24 24" class="fill" aria-hidden="true"><path d={FI.gear}></path></svg></span>{t('os_app_settings')}</p>
    {#each SECTIONS as entry (entry.id)}
      <button type="button" class="t-row" class:t-on={entry.id === section} onclick={() => (section = entry.id)}><Glyph d={entry.icon} size={18} stroke={1.75} />{t('os_settings_' + entry.id)}</button>
    {/each}
  </aside>
  <div class="t-page">
    <h2 class="t-title">{t('os_settings_' + section)}</h2>
    {#if section === 'appearance'}
      <p class="t-cap">{t('os_wall_title')}</p>
      <div class="t-walls">
        {#each walls as wall (wall)}
          <button type="button" class="t-wall" class:t-on={tablet.set.wall === wall} aria-pressed={tablet.set.wall === wall} onclick={() => setSetting('wall', wall)}>
            <span class="t-swatch"><Wallpaper wall={wall || brand.wallpaper} cls="t-swatch-fill" /></span>
            <span class="t-wall-name">{wall ? wallName(wall) : t('os_wall_default')}</span>
          </button>
        {/each}
      </div>
      <div class="t-stack">
        <Toggle label={t('os_settings_clock24')} help={t('os_settings_clock24_help')} on={tablet.set.clock24} ontoggle={() => setSetting('clock24', !tablet.set.clock24)} />
        <Toggle label={t('os_settings_seconds')} help={t('os_settings_seconds_help_tablet')} on={tablet.set.seconds} ontoggle={() => setSetting('seconds', !tablet.set.seconds)} />
        <div class="t-card t-line">
          <div class="t-grow"><p class="t-label">{t('os_settings_date')}</p><p class="t-help">{t('os_settings_date_help_tablet')}</p></div>
          <div class="t-chips">
            <button type="button" class="t-chip" class:t-on={tablet.set.date === 'dm'} aria-pressed={tablet.set.date === 'dm'} onclick={() => setSetting('date', 'dm')}>{t('os_date_dm')}</button>
            <button type="button" class="t-chip" class:t-on={tablet.set.date === 'md'} aria-pressed={tablet.set.date === 'md'} onclick={() => setSetting('date', 'md')}>{t('os_date_md')}</button>
          </div>
        </div>
        <Toggle label={t('os_settings_still')} help={t('os_settings_still_help')} on={tablet.set.still} ontoggle={() => setSetting('still', !tablet.set.still)} />
      </div>
    {:else if section === 'account'}
      <div class="t-card t-me">
        <span class="t-avatar">{initials(tablet.user.name)}</span>
        <div class="t-grow"><p class="t-small">{t('os_settings_name')}</p><p class="t-big">{tablet.user.name}</p></div>
        <span class="t-pill mono" class:t-lime={system.owner}>{system.owner ? t('os_settings_owner') : t('os_settings_user')}</span>
      </div>
      <PasswordForm
        on={system.password}
        can={system.canPassword}
        ownerName={system.ownerName}
        limits={system.limits}
        call={passwordCall}
        {say}
        onchange={setPasswordOn}
      />
    {:else if section === 'notifications'}
      <div class="t-stack">
        <Toggle label={t('os_dnd')} help={t('os_dnd_help')} on={tablet.set.dnd} ontoggle={() => setSetting('dnd', !tablet.set.dnd)} />
        <Toggle label={t('os_settings_chime')} help={t('os_settings_chime_help_tablet')} on={tablet.set.sound} ontoggle={() => setSetting('sound', !tablet.set.sound)} />
        {#each hosted as app (app.id)}
          <Toggle label={app.label} help={t('os_settings_popups', app.label)} on={tablet.set.muted[app.id] !== true} disabled={tablet.set.dnd} ontoggle={() => mute(app.id)} />
        {/each}
      </div>
      <p class="t-cap t-game">{t('os_settings_game')}</p>
      <div class="t-stack">
        <Toggle label={t('os_settings_game_popup')} help={tablet.game.canPopup ? t('os_settings_game_popup_help') : t('os_settings_game_off')} on={tablet.game.canPopup && tablet.game.popup} disabled={!tablet.game.canPopup} ontoggle={() => setGame({ popup: !tablet.game.popup })} />
        <Toggle label={t('os_settings_game_sound')} help={tablet.game.canSound ? t('os_settings_game_sound_help') : t('os_settings_game_off')} on={tablet.game.canSound && tablet.game.popup && tablet.game.sound} disabled={!tablet.game.canSound || !tablet.game.popup} ontoggle={() => setGame({ sound: !tablet.game.sound })} />
      </div>
    {:else if section === 'display'}
      <div class="t-stack">
        <div class="t-card">
          <div class="t-line"><div class="t-grow"><p class="t-label">{t('os_brightness')}</p><p class="t-help">{t('os_settings_bright_help_tablet')}</p></div><span class="t-pill mono">{tablet.set.bright}%</span></div>
          <div class="t-slide"><Slider value={tablet.set.bright} label={t('os_brightness')} onchange={(value) => setSetting('bright', Math.max(30, Math.min(100, value)))} /></div>
        </div>
        <div class="t-card">
          <p class="t-label">{t('os_settings_sleep')}</p>
          <p class="t-help">{t('os_settings_sleep_help_tablet')}</p>
          <div class="t-chips t-spaced">
            {#each SLEEP_CHOICES as value (value)}
              <button type="button" class="t-chip" class:t-on={tablet.set.sleep === value} aria-pressed={tablet.set.sleep === value} onclick={() => setSetting('sleep', value)}>{sleepText(value)}</button>
            {/each}
          </div>
        </div>
        <div class="t-card">
          <p class="t-label">{t('os_settings_lock')}</p>
          <p class="t-help">{t('os_settings_lock_help_tablet')}</p>
          <div class="t-chips t-spaced">
            {#each LOCK_CHOICES as value (value)}
              <button type="button" class="t-chip" class:t-on={tablet.set.lock === value} aria-pressed={tablet.set.lock === value} onclick={() => setSetting('lock', value)}>{minutes(value)}</button>
            {/each}
          </div>
        </div>
        <div class="t-card t-line"><div class="t-grow"><p class="t-label">{t('os_display_resolution')}</p><p class="t-help">{t('os_display_resolution_help')}</p></div><span class="t-pill mono">{SCREEN.width} × {SCREEN.height}</span></div>
      </div>
    {:else}
      <div class="t-card t-facts">
        <div><span>{t('os_about_kind')}</span><span class="mono">{t('kind_tablet')}</span></div>
        {#if tablet.serial}<div><span>{t('os_about_serial')}</span><span class="mono">{tablet.serial}</span></div>{/if}
        <div><span>{t('os_about_owner')}</span><span class="mono">{system.ownerName || t('os_about_server')}</span></div>
        <div><span>{t('os_display_resolution')}</span><span class="mono">{SCREEN.width} × {SCREEN.height}</span></div>
        <div><span>{osName()}</span><span class="mono">{system.version || '-'}</span></div>
      </div>
    {/if}
  </div>
</div>

<style>
  .t-set {
    position: absolute;
    inset: 0;
    display: flex;
    background: #0a0a0f;
    color: #e4e4e7;
  }
  .t-side {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex-shrink: 0;
    width: 240px;
    padding: 16px 12px;
    background: #0c0c11;
    border-right: 1px solid #1f1f27;
  }
  .t-head {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 4px 10px 16px;
    font-size: 17px;
    font-weight: 600;
    letter-spacing: -0.01em;
  }
  .t-gear {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
  }
  .t-gear svg {
    width: 24px;
    height: 24px;
  }
  .t-row {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 48px;
    padding: 0 12px;
    background: transparent;
    border: 0;
    border-radius: 10px;
    color: #a1a1aa;
    font: 500 14px/1 'Poppins', system-ui, sans-serif;
    text-align: left;
    cursor: pointer;
  }
  .t-row:hover {
    background: #13131a;
  }
  .t-row.t-on {
    background: #17171f;
    color: #e4e4e7;
  }
  .t-row.t-on :global(svg) {
    color: var(--accent);
  }
  .t-page {
    flex: 1;
    min-width: 0;
    overflow: auto;
    padding: 28px 40px 40px;
  }
  .t-title {
    margin: 0 0 18px;
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.02em;
  }
  .t-cap {
    margin-bottom: 10px;
    color: #a1a1aa;
    font-size: 13px;
    font-weight: 600;
  }
  .t-walls {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: 12px;
    margin-bottom: 20px;
  }
  .t-wall {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 0;
    background: transparent;
    border: 0;
    color: #a1a1aa;
    font: 500 13px/1.3 'Poppins', system-ui, sans-serif;
    text-align: left;
    cursor: pointer;
  }
  .t-swatch {
    position: relative;
    display: block;
    aspect-ratio: 16 / 10;
    overflow: hidden;
    border: 2px solid #2a2a35;
    border-radius: 12px;
  }
  .t-swatch :global(.t-swatch-fill) {
    position: absolute;
    inset: 0;
  }
  .t-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .t-chips.t-spaced {
    margin-top: 14px;
  }
  .t-chip {
    height: 40px;
    padding: 0 16px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 10px;
    color: #a1a1aa;
    font: 500 13px/1 'Poppins', system-ui, sans-serif;
    cursor: pointer;
  }
  .t-chip:hover {
    border-color: #3a3a46;
    color: #e4e4e7;
  }
  .t-chip.t-on {
    background: var(--accent-bg);
    border-color: var(--accent-line);
    color: var(--accent);
  }
  .t-slide {
    display: flex;
    margin-top: 14px;
  }
  .t-wall.t-on {
    color: #e4e4e7;
  }
  .t-wall.t-on .t-swatch {
    border-color: var(--accent);
  }
  .t-stack {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .t-cap.t-game {
    margin-top: 26px;
  }
  .t-card {
    padding: 16px 18px;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 14px;
  }
  .t-me,
  .t-line {
    display: flex;
    align-items: center;
    gap: 16px;
  }
  .t-grow {
    flex: 1;
    min-width: 0;
  }
  .t-avatar {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    flex-shrink: 0;
    background: var(--accent);
    border-radius: 50%;
    color: var(--accent-content);
    font-size: 18px;
    font-weight: 600;
  }
  .t-small {
    font-size: 12px;
    color: #a1a1aa;
  }
  .t-big {
    margin-top: 2px;
    font-size: 16px;
    font-weight: 600;
  }
  .t-label {
    font-size: 15px;
    font-weight: 600;
  }
  .t-help {
    margin-top: 2px;
    font-size: 12px;
    color: #a1a1aa;
  }
  .t-label + .t-help {
    margin-top: var(--sub-pull);
    line-height: var(--sub-lh);
  }
  .t-pill {
    padding: 4px 9px;
    background: #17171f;
    border: 1px solid #2a2a35;
    border-radius: 6px;
    font: 600 12px/1.3 'JetBrains Mono', monospace;
    color: #a1a1aa;
    white-space: nowrap;
  }
  .t-pill.t-lime {
    background: var(--accent-bg);
    border-color: var(--accent-line);
    color: var(--accent);
  }
  .t-facts {
    padding: 4px 18px;
  }
  .t-facts div {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    padding: 12px 0;
    border-bottom: 1px solid #1f1f27;
    font-size: 13px;
  }
  .t-facts div:last-child {
    border-bottom-color: transparent;
  }
  .t-facts span:first-child {
    color: #a1a1aa;
  }
</style>

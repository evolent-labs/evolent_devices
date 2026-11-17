<script lang="ts">
  import BrandMark from '$components/BrandMark.svelte';
  import PasswordForm from '$components/PasswordForm.svelte';
  import Wallpaper from '$components/Wallpaper.svelte';
  import { brand, osName, wallName, wallpapers } from '$lib/brand.svelte';
  import { plural, t } from '$lib/state.svelte';
  import { osCall, playSound } from '../bridge';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from '../icons';
  import { page, watching } from '../params';
  import Slider from '../Slider.svelte';
  import { homeApps, layout, os, publish, say, setPrefs, type Win } from '../store.svelte';
  import { isBuiltin, lockChoices, lockShown, SLEEP_CHOICES } from '../system';
  import { failed, loadNotes, loadPhotos, store } from './data.svelte';
  import Toggle from './Toggle.svelte';

  type Section = 'account' | 'appearance' | 'sound' | 'notifications' | 'display' | 'about';

  const SECTIONS: { id: Section; icon: string }[] = [
    { id: 'account', icon: IC.user },
    { id: 'appearance', icon: IC.image },
    { id: 'sound', icon: IC.volume },
    { id: 'notifications', icon: IC.bell },
    { id: 'display', icon: IC.monitor },
    { id: 'about', icon: IC.info },
  ];

  let { win }: { win: Win } = $props();

  let section = $state<Section>('account');
  let lastVolume = 100;
  let wallBusy = $state(false);

  const remote = $derived(os.states.settings ?? {});
  const shown = $derived<Section>(watching ? (SECTIONS.find((entry) => entry.id === remote.s)?.id ?? 'account') : section);
  const limits = $derived(os.system.limits);
  const hosted = $derived(homeApps().filter((app) => !isBuiltin(app.id)));
  const notesOn = $derived(os.system.apps.includes('notes') && os.system.keeps);
  const photosOn = $derived(os.system.apps.includes('photos') && os.system.keeps);
  const ownPhotos = $derived(store.photos.filter((photo) => photo.own).length);
  const walls = $derived(['', ...wallpapers()]);
  const wallNote = $derived(os.system.canWall ? t('os_wall_shared') : os.system.keeps ? t('os_wall_owner_only') : t('os_wall_keeps_nothing'));

  $effect(() => {
    if (watching) return;

    publish('settings', { s: section });
  });

  $effect(() => {
    const wanted = win.intent?.section;

    if (watching || typeof wanted !== 'string') return;

    win.intent = null;

    if (SECTIONS.some((entry) => entry.id === wanted)) {
      go(wanted as Section);
    }
  });

  $effect(() => () => {
    os.secret = false;
  });

  function go(next: Section) {
    section = next;

    if (next === 'about') {
      if (notesOn && store.notesLoad !== 'ready') loadNotes();
      if (photosOn && store.photosLoad !== 'ready') loadPhotos();
    }
  }

  function mute() {
    if (os.prefs.volume > 0) {
      lastVolume = os.prefs.volume;
      setPrefs({ volume: 0 });
    } else {
      setPrefs({ volume: lastVolume || 70 });
    }
  }

  function quiet(id: string) {
    const list = os.prefs.quiet.includes(id) ? os.prefs.quiet.filter((entry) => entry !== id) : [...os.prefs.quiet, id];

    setPrefs({ quiet: list });
  }

  const minutes = (value: number) => (value ? t('os_minutes_short', value) : t('os_never'));

  async function pickWall(wall: string) {
    if (watching || wallBusy || !os.system.canWall || wall === brand.wall) return;

    const before = brand.wall;

    brand.wall = wall;
    wallBusy = true;

    const answer = await osCall<{ wall: string }>('wall', wall);

    wallBusy = false;

    if (!answer.ok) {
      brand.wall = before;
      failed(answer.reason);
    }
  }

  function brightness(value: number) {
    setPrefs({ bright: Math.max(30, Math.min(100, value)) });
  }

  function share(used: number, max: number) {
    return max > 0 ? Math.min(100, Math.round((used / max) * 100)) : 0;
  }
</script>

<div class="settings">
  <aside>
    {#each SECTIONS as entry (entry.id)}
      <button type="button" class="section" class:on={entry.id === shown} onclick={() => go(entry.id)}><Glyph d={entry.icon} size={16} />{t('os_settings_' + entry.id)}</button>
    {/each}
  </aside>
  <div class="page">
    <h2>{t('os_settings_' + shown)}</h2>
    {#if watching}
      <div class="stack">{#each [0, 1, 2] as index (index)}<div class="card bones"><i class="bone wide"></i><i class="bone"></i></div>{/each}</div>
    {:else if shown === 'account'}
      <div class="card me">
        <span class="avatar">{os.user?.initials ?? ''}</span>
        <div class="grow"><p class="small">{t('os_settings_name')}</p><p class="big">{os.user?.name ?? ''}</p></div>
        <span class="pill mono" class:lime={os.system.owner}>{os.system.owner ? t('os_settings_owner') : t('os_settings_user')}</span>
      </div>
      <PasswordForm
        on={os.system.password}
        can={os.system.canPassword}
        ownerName={os.system.ownerName}
        {limits}
        call={(action, data) => osCall<{ left?: number }>('password', action, data)}
        {say}
        onchange={(on) => (os.system.password = on)}
        onsecret={(on) => (os.secret = on)}
      />
    {:else if shown === 'appearance'}
      <p class="cap">{t('os_wall_title')}</p>
      <div class="walls">
        {#each walls as wall (wall)}
          <button type="button" class="wall-pick" class:on={brand.wall === wall} aria-pressed={brand.wall === wall} disabled={!os.system.canWall || wallBusy} onclick={() => pickWall(wall)}>
            <span class="wall-swatch"><Wallpaper wall={wall || brand.wallpaper} cls="wall-fill" /></span>
            <span class="wall-name">{wall ? wallName(wall) : t('os_wall_default')}</span>
          </button>
        {/each}
      </div>
      <p class="help wall-note">{wallNote}</p>
      <div class="stack">
        <Toggle label={t('os_settings_clock24')} help={t('os_settings_clock24_help')} on={os.prefs.clock24} ontoggle={() => setPrefs({ clock24: !os.prefs.clock24 })} />
        <Toggle label={t('os_settings_seconds')} help={t('os_settings_seconds_help')} on={os.prefs.seconds} ontoggle={() => setPrefs({ seconds: !os.prefs.seconds })} />
        <div class="card row-card">
          <div class="grow"><p class="label">{t('os_settings_date')}</p><p class="help">{t('os_settings_date_help')}</p></div>
          <div class="chips">
            <button type="button" class="chip" class:on={os.prefs.dateFormat === 'dm'} aria-pressed={os.prefs.dateFormat === 'dm'} onclick={() => setPrefs({ dateFormat: 'dm' })}>{t('os_date_dm')}</button>
            <button type="button" class="chip" class:on={os.prefs.dateFormat === 'md'} aria-pressed={os.prefs.dateFormat === 'md'} onclick={() => setPrefs({ dateFormat: 'md' })}>{t('os_date_md')}</button>
          </div>
        </div>
        <Toggle label={t('os_settings_still')} help={t('os_settings_still_help')} on={os.prefs.reduceMotion} ontoggle={() => setPrefs({ reduceMotion: !os.prefs.reduceMotion })} />
      </div>
    {:else if shown === 'sound'}
      <div class="card">
        <div class="card-top">
          <div class="grow"><p class="label">{t('os_sound_volume')}</p><p class="help">{t('os_sound_volume_help')}</p></div>
          <span class="value mono">{os.prefs.volume}</span>
        </div>
        <div class="volume">
          <button type="button" class="icon" aria-label={t('os_sound_mute')} onclick={mute}><Glyph d={os.prefs.volume > 0 ? IC.volume : IC.volumeOff} size={20} stroke={2} /></button>
          <Slider value={os.prefs.volume} label={t('os_sound_volume')} onchange={(volume) => setPrefs({ volume })} />
        </div>
        <div class="card-foot"><button type="button" class="outline" disabled={os.prefs.volume === 0} onclick={() => playSound('notice')}><Glyph d={IC.bell} size={14} />{t('os_sound_test')}</button></div>
      </div>
      <div class="stack">
        <Toggle label={t('os_settings_chime')} help={t('os_settings_chime_help')} on={os.prefs.sound} ontoggle={() => setPrefs({ sound: !os.prefs.sound })} />
      </div>
    {:else if shown === 'notifications'}
      <div class="stack">
        <Toggle label={t('os_dnd')} help={t('os_dnd_help')} on={os.prefs.dnd} ontoggle={() => setPrefs({ dnd: !os.prefs.dnd })} />
        {#each hosted as app (app.id)}
          <Toggle label={app.label} help={t('os_settings_popups', app.label)} on={!os.prefs.quiet.includes(app.id)} disabled={os.prefs.dnd} ontoggle={() => quiet(app.id)} />
        {/each}
      </div>
      <p class="cap game">{t('os_settings_game')}</p>
      <div class="stack">
        <Toggle label={t('os_settings_game_popup')} help={os.alerts.popup ? t('os_settings_game_popup_help') : t('os_settings_game_off')} on={os.alerts.popup && os.prefs.gamePopup} disabled={!os.alerts.popup} ontoggle={() => setPrefs({ gamePopup: !os.prefs.gamePopup })} />
        <Toggle label={t('os_settings_game_sound')} help={os.alerts.sound ? t('os_settings_game_sound_help') : t('os_settings_game_off')} on={os.alerts.sound && os.prefs.gamePopup && os.prefs.gameSound} disabled={!os.alerts.sound || !os.prefs.gamePopup} ontoggle={() => setPrefs({ gameSound: !os.prefs.gameSound })} />
      </div>
    {:else if shown === 'display'}
      <div class="stack">
        <div class="card row-card"><div class="grow"><p class="label">{t('os_display_resolution')}</p><p class="help">{t('os_display_resolution_help')}</p></div><span class="pill mono">{layout.width} × {layout.height}</span></div>
        <div class="card">
          <div class="card-top">
            <div class="grow"><p class="label">{t('os_settings_bright')}</p><p class="help">{t('os_settings_bright_help')}</p></div>
            <span class="value mono">{os.prefs.bright}%</span>
          </div>
          <div class="volume">
            <span class="icon static"><Glyph d={IC.sun} size={20} stroke={2} /></span>
            <Slider value={os.prefs.bright} label={t('os_settings_bright')} onchange={brightness} />
          </div>
        </div>
        <div class="card row-card"><div class="grow"><p class="label">{t('os_brightness')}</p><p class="help">{t('os_display_brightness_help')}</p></div><span class="pill mono">{os.brightness}%</span></div>
        <div class="card">
          <p class="label">{t('os_settings_sleep')}</p>
          <p class="help">{t('os_settings_sleep_help')}</p>
          <div class="chips spaced">
            {#each SLEEP_CHOICES as value (value)}
              <button type="button" class="chip" class:on={os.prefs.sleep === value} aria-pressed={os.prefs.sleep === value} onclick={() => setPrefs({ sleep: value })}>{minutes(value)}</button>
            {/each}
          </div>
        </div>
        <div class="card">
          <p class="label">{t('os_settings_lock')}</p>
          <p class="help">{os.lockMinutes ? t('os_settings_lock_help', os.lockMinutes) : t('os_settings_lock_help_free')}</p>
          <div class="chips spaced">
            {#each lockChoices(os.lockMinutes) as value (value)}
              <button type="button" class="chip" class:on={lockShown(os.prefs.lock, os.lockMinutes) === value} aria-pressed={lockShown(os.prefs.lock, os.lockMinutes) === value} onclick={() => setPrefs({ lock: value })}>{value ? t('os_minutes_short', value) : t('os_lock_device')}</button>
            {/each}
          </div>
        </div>
      </div>
    {:else}
      <div class="card me">
        <span class="mark"><BrandMark /></span>
        <div class="grow"><p class="big">{osName()}</p><p class="help">{t('os_about_version', os.system.version || '-')}</p></div>
      </div>
      <div class="card facts">
        <div><span>{t('os_about_device')}</span><span class="mono">{os.device || t('kind_' + page.kind)}</span></div>
        <div><span>{t('os_about_kind')}</span><span class="mono">{t('kind_' + page.kind)}</span></div>
        {#if os.system.serial}<div><span>{t('os_about_serial')}</span><span class="mono">{os.system.serial}</span></div>{/if}
        <div><span>{t('os_about_owner')}</span><span class="mono">{os.system.ownerName || t('os_about_server')}</span></div>
        <div><span>{t('os_display_resolution')}</span><span class="mono">{layout.width} × {layout.height}</span></div>
      </div>
      {#if notesOn || photosOn}
        <div class="card">
          <p class="label">{t('os_about_storage')}</p>
          {#if notesOn}
            <div class="meter"><span>{t('os_app_notes')}</span><span class="mono dim">{t('os_about_used', store.notes.length, limits.notes)}</span></div>
            <div class="track"><div class="fill" style:width={share(store.notes.length, limits.notes) + '%'}></div></div>
          {/if}
          {#if photosOn}
            <div class="meter"><span>{t('os_app_photos')}</span><span class="mono dim">{t('os_about_used', ownPhotos, limits.photos)}</span></div>
            <div class="track"><div class="fill" style:width={share(ownPhotos, limits.photos) + '%'}></div></div>
          {/if}
          {#if notesOn && store.trash.length}<p class="help note">{plural('os_about_trash', store.trash.length)}</p>{/if}
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  .settings {
    position: absolute;
    inset: 0;
    display: flex;
  }
  aside {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex-shrink: 0;
    width: 200px;
    padding: 12px 10px;
    background: #0c0c11;
    border-right: 1px solid #1f1f27;
  }
  .section {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 38px;
    padding: 0 10px;
    background: transparent;
    border: 0;
    border-radius: 8px;
    color: #a1a1aa;
    font: 500 13px/1 Poppins, system-ui, sans-serif;
    text-align: left;
    cursor: pointer;
  }
  .section :global(svg) {
    color: #71717a;
  }
  .section:hover {
    background: #13131a;
  }
  .section.on {
    background: #17171f;
    color: #e4e4e7;
  }
  .section.on :global(svg) {
    color: var(--accent);
  }
  .page {
    flex: 1;
    min-width: 0;
    overflow: auto;
    padding: 20px 24px 24px;
  }
  h2 {
    margin: 0;
    font-size: 18px;
    font-weight: 600;
    letter-spacing: -0.02em;
  }
  .stack {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 16px;
  }
  .cap.game {
    margin-top: 28px;
  }
  .cap.game + .stack {
    margin-top: 10px;
  }
  .card {
    margin-top: 10px;
    padding: 16px 18px;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 12px;
  }
  .stack .card {
    margin-top: 0;
  }
  h2 + .card {
    margin-top: 16px;
  }
  .me,
  .card-top,
  .row-card {
    display: flex;
    align-items: center;
    gap: 16px;
  }
  .row-card {
    padding: 14px 16px;
  }
  .grow {
    flex: 1;
    min-width: 0;
  }
  .avatar {
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
  .mark {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    color: var(--accent);
  }
  .mark :global(svg),
  .mark :global(img) {
    width: 100%;
    height: 100%;
    object-fit: contain;
  }
  .cap {
    margin-top: 16px;
    font-size: 12px;
    font-weight: 600;
    color: #a1a1aa;
  }
  .walls {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 10px;
    margin-top: 10px;
  }
  .wall-pick {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 6px;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 12px;
    color: #a1a1aa;
    font: 500 12px/1.3 Poppins, system-ui, sans-serif;
    text-align: left;
    cursor: pointer;
  }
  .wall-pick:hover:not(:disabled) {
    border-color: #3a3a46;
  }
  .wall-pick:disabled {
    cursor: default;
  }
  .wall-pick:disabled:not(.on) {
    opacity: 0.55;
  }
  .wall-note {
    margin-top: 8px;
  }
  .wall-pick.on {
    border-color: var(--accent);
    color: #e4e4e7;
  }
  .wall-swatch {
    position: relative;
    display: block;
    height: 78px;
    overflow: hidden;
    border-radius: 8px;
  }
  .wall-swatch :global(.wall-fill) {
    position: absolute;
    inset: 0;
  }
  .wall-name {
    padding: 0 4px 2px;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .chips.spaced {
    margin-top: 12px;
  }
  .chip {
    height: 34px;
    padding: 0 12px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 8px;
    color: #a1a1aa;
    font: 500 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .chip:hover {
    border-color: #3a3a46;
    color: #e4e4e7;
  }
  .chip.on {
    background: var(--accent-bg);
    border-color: var(--accent-line);
    color: var(--accent);
  }
  .icon.static {
    cursor: default;
    color: #a1a1aa;
  }
  .icon.static:hover {
    border-color: #2a2a35;
  }
  .small {
    font-size: 12px;
    color: #a1a1aa;
  }
  .big {
    margin-top: 2px;
    font-size: 16px;
    font-weight: 600;
  }
  .label {
    font-size: 14px;
    font-weight: 600;
  }
  .help {
    margin-top: 2px;
    font-size: 12px;
    color: #a1a1aa;
  }
  .help.note {
    margin-top: 10px;
  }
  .label + .help,
  .big + .help {
    margin-top: var(--sub-pull);
    line-height: var(--sub-lh);
  }
  .pill {
    padding: 4px 9px;
    background: #17171f;
    border: 1px solid #2a2a35;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    line-height: 1.3;
    color: #a1a1aa;
    white-space: nowrap;
  }
  .pill.lime {
    background: var(--accent-bg);
    border-color: var(--accent-line);
    color: var(--accent);
  }
  .value {
    font-size: 20px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  .outline {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 14px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 8px;
    color: #e4e4e7;
    font: 500 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .outline:hover {
    border-color: var(--accent);
  }
  .outline:disabled {
    cursor: default;
    opacity: 0.55;
  }
  .volume {
    display: flex;
    align-items: center;
    gap: 14px;
    margin-top: 16px;
  }
  .icon {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    padding: 0;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 10px;
    color: #e4e4e7;
    cursor: pointer;
  }
  .icon:hover {
    border-color: var(--accent);
  }
  .card-foot {
    display: flex;
    margin-top: 16px;
  }
  .facts {
    padding: 4px 18px;
  }
  .facts div {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    padding: 10px 0;
    border-bottom: 1px solid #1f1f27;
    font-size: 13px;
  }
  .facts div:last-child {
    border-bottom-color: transparent;
  }
  .facts span:first-child {
    color: #a1a1aa;
  }
  .facts .mono {
    font-size: 12.5px;
    font-weight: 500;
  }
  .meter {
    display: flex;
    justify-content: space-between;
    margin-top: 12px;
    font-size: 13px;
  }
  .dim {
    color: #a1a1aa;
  }
  .track {
    height: 4px;
    margin-top: 8px;
    background: #1f1f27;
    border-radius: 4px;
  }
  .fill {
    height: 100%;
    background: var(--accent);
    border-radius: 4px;
  }
  .bones {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .bone {
    display: block;
    width: 120px;
    height: 9px;
    background: rgba(255, 255, 255, 0.07);
    border-radius: 6px;
  }
  .bone.wide {
    width: 220px;
  }
</style>

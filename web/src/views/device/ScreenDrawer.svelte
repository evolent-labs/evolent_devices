<script lang="ts">
  import { untrack } from 'svelte';
  import Drawer from '$components/Drawer.svelte';
  import Icon from '$components/Icon.svelte';
  import IdleCanvas from '$components/IdleCanvas.svelte';
  import Wallpaper from '$components/Wallpaper.svelte';
  import { brand, idlePicture, wallName, wallpapers } from '$lib/brand.svelte';
  import { names, readBulk } from '$lib/devices';
  import { call, previewParam } from '$lib/nui';
  import { presetName, screenLook, screenPick, screenWall, urlOk } from '$lib/screen';
  import { clone, deviceName, explain, kindName, list, reasonText, same, t, toast } from '$lib/state.svelte';
  import type { BulkResult, DeviceData, DeviceSummary, ScreenPreset, ScreenSettings, SignalMode } from '$lib/types';

  let { open, data, onclose, onsaved }: { open: boolean; data: DeviceData; onclose: () => void; onsaved: () => void } = $props();

  const device = $derived(data.device);
  const info = $derived(data.screen!);
  const size = $derived(info.size ?? { width: 1440, height: 900 });

  const initial = () => {
    const value = { ...clone(data.screen!.defaults), ...clone(data.device.screen ?? {}) } as ScreenSettings;

    value.wall = screenWall(data.screen!, value);

    return value;
  };

  let base = $state<ScreenSettings>(untrack(initial));
  let draft = $state<ScreenSettings>(untrack(initial));
  let enabled = $state(true);
  let more = $state(false);
  let also = $state(false);
  let others = $state<DeviceSummary[]>([]);
  let preview = $state<BulkResult | null>(null);
  let busy = $state(false);

  $effect(() => {
    if (!open) return;

    untrack(() => {
      base = initial();
      draft = clone(base);
      enabled = data.device.enabled;
      more = previewParam('more') === '1';
      also = previewParam('also') === '1';
      preview = null;
      loadOthers();
    });
  });

  async function loadOthers() {
    const result = await call<{ devices: DeviceSummary[] }>('evdev:admin:list', { kind: data.device.kind, owner: 'server', limit: 500 });

    others = result.ok ? list<DeviceSummary>(result.data!.devices).filter((entry) => entry.id !== data.device.id && !entry.from) : [];
  }

  const dirty = $derived(!same(draft, base) || enabled !== device.enabled);
  const look = $derived(screenLook(info, draft, enabled ? 'idle' : 'oos'));
  const picture = $derived(presetName(info.presets.find((entry) => entry.id === draft.idle), draft.idle));
  const shown = $derived.by(() => {
    const pick = screenPick(info, draft);

    return pick && (pick.shared || !info.os) ? wallName(pick.id) : picture;
  });
  const walls = $derived(info.os ? ['', ...wallpapers()] : info.pictures && brand.walls.length ? ['', ...brand.walls.map((entry) => entry.id)] : []);
  const ids = $derived(others.map((entry) => entry.id));

  const problems = $derived.by(() => {
    const found: string[] = [];

    if (draft.idle === 'url' && !urlOk(info, draft.url ?? '')) found.push(t('ui_screen_url_bad'));

    if (draft.lock !== false && (!Number.isInteger(Number(draft.lock)) || Number(draft.lock) < 0 || Number(draft.lock) > info.ranges.lock[1])) {
      found.push(t('ui_screen_range', t('ui_screen_lock_own'), 0, info.ranges.lock[1]));
    }

    return found;
  });

  const pictureForOthers = $derived({ idle: draft.idle, url: draft.idle === 'url' ? (draft.url ?? '').trim() : undefined });

  $effect(() => {
    const wanted = $state.snapshot(pictureForOthers);
    const targets = ids;

    if (!open || !also || !targets.length || (wanted.idle === 'url' && !urlOk(info, wanted.url ?? ''))) {
      preview = null;

      return;
    }

    untrack(async () => {
      const result = await call<BulkResult>('evdev:admin:screen:bulk', wanted, targets, true);

      preview = result.ok ? readBulk(result.data!) : null;
    });
  });

  const tileLook = (entry: ScreenPreset) => screenLook(info, { ...draft, idle: entry.id, brightness: 100, wall: '' }, 'idle', true);
  const sharedLook = $derived(screenLook(info, { ...draft, idle: draft.idle === 'url' ? info.defaults.idle : draft.idle, brightness: 100, wall: '' }));

  const signalText = (mode: SignalMode) => {
    if (mode === 'kind') {
      return t('ui_screen_signal_kind', info.wireless ? t('ui_signal_wireless') : t('ui_signal_wired'));
    }

    return mode === 'wired' ? t('ui_screen_signal_online') : t('ui_screen_signal_needs');
  };

  const nameOf = (id: number) => {
    const found = others.find((entry) => entry.id === id);

    return found ? deviceName(found) : '#' + id;
  };

  async function save() {
    const screen = $state.snapshot(draft) as ScreenSettings;

    const patch: Record<string, unknown> = {
      screen: {
        idle: screen.idle,
        url: screen.idle === 'url' || urlOk(info, screen.url ?? '') ? (screen.url ?? '').trim() : '',
        name: screen.name.trim(),
        message: screen.message.trim(),
        signal: screen.signal,
        lock: screen.lock === false ? false : Number(screen.lock),
        ...(info.os || info.pictures ? { wall: screen.wall ?? '' } : {}),
      },
    };

    if (enabled !== device.enabled) {
      patch.enabled = enabled;
    }

    busy = true;

    const result = await call('evdev:admin:save', device.id, device.version, patch);

    if (!result.ok) {
      busy = false;
      explain(result);

      if (result.reason === 'device_changed') onsaved();

      return;
    }

    if (also && preview?.changes.length) {
      const bulk = await call<BulkResult>('evdev:admin:screen:bulk', $state.snapshot(pictureForOthers), preview.changes.map((entry) => entry.id), false);

      if (bulk.ok) toast(t('ui_picture_on_others', picture, bulk.data!.changes.length + 1), 'success');
      else explain(bulk);
    } else {
      toast(t('ui_picture_saved', shown), 'success');
    }

    busy = false;
    onsaved();
  }
</script>

<Drawer {open} wide title={t('ui_screen_title', deviceName(device))} sub={t('ui_screen_sub')} {onclose}>
  <div class="thumb wide-thumb">
    <IdleCanvas {look} width={size.width} height={size.height} scale={0.4} />
    <span class="label">{look.wall ? wallName(look.wall) : picture}</span>
  </div>
  <p class="dim small">{info.liveRange > 0 ? t('ui_screen_preview_help', info.liveRange) : t('ui_screen_preview_help_off')}</p>
  <p class="dim small">{t('ui_screen_display_note')}</p>

  <span class="label">{t('ui_picture')}</span>
  <div class="pictures">
    {#each info.presets as entry (entry.id)}
      <button class="pic" aria-pressed={draft.idle === entry.id} onclick={() => (draft.idle = entry.id)}>
        <IdleCanvas look={tileLook(entry)} width={size.width} height={size.height} scale={0.12} />
        {presetName(entry, entry.id)}
      </button>
    {/each}
    <button class="pic" aria-pressed={draft.idle === 'url'} onclick={() => (draft.idle = 'url')}>
      <span class="linkpic" style:aspect-ratio={`${size.width} / ${size.height}`}><Icon name="link" /></span>
      {t('ui_picture_link')}
    </button>
  </div>
  {#if draft.idle === 'url'}
    <label class="field">{t('ui_screen_url')}<input type="url" maxlength={info.limits.url} placeholder="https://" bind:value={draft.url} /><small>{t('ui_screen_url_help', size.width, size.height, size.width * 2, size.height * 2)}</small></label>
  {/if}

  {#if walls.length}
    <span class="label">{t(info.os ? 'ui_screen_wall' : 'ui_screen_own')}</span>
    <div class="pictures">
      {#each walls as wall (wall)}
        <button class="pic" aria-pressed={(draft.wall ?? '') === wall} onclick={() => (draft.wall = wall)}>
          {#if wall || info.os}
            <span class="linkpic wallpic" style:aspect-ratio={`${size.width} / ${size.height}`}><Wallpaper wall={wall || brand.wallpaper} cls="wall-fill" /></span>
          {:else}
            <IdleCanvas look={sharedLook} width={size.width} height={size.height} scale={0.12} />
          {/if}
          {wall ? wallName(wall) : t('os_wall_default')}
        </button>
      {/each}
    </div>
    <p class="dim small">{t(!info.os ? 'ui_screen_own_help' : idlePicture(device.kind) ? 'ui_screen_wall_help_brand' : 'ui_screen_wall_help')}</p>
  {/if}

  {#if info.os}
    <label class="field">{t('ui_screen_name_os')}<input type="text" maxlength={info.limits.name} placeholder={t('os_name')} bind:value={draft.name} /><small>{t('ui_screen_name_os_help')}</small></label>
  {/if}

  {#if others.length}
    <label class="summary also-box">
      <input type="checkbox" class="box" bind:checked={also} />
      <span>
        <b>{t('ui_picture_also', others.length, t('kind_plural_' + device.kind).toLowerCase())}</b>
        <small class="dim">{t('ui_picture_also_help', names(others.slice(0, 4).map((entry) => deviceName(entry))) + (others.length > 4 ? ' +' + (others.length - 4) : ''))}</small>
        {#if also && preview}
          <small class="also-preview">
            {#if preview.changes.length}{t('ui_picture_will_change', names(preview.changes.map((entry) => nameOf(entry.id))))}{/if}
            {#if preview.unchanged}{' ' + t('ui_picture_already', preview.unchanged)}{/if}
            {#each preview.skipped as entry (entry.id)}<span class="warn-text">{' ' + t('ui_bulk_skipped', nameOf(entry.id), reasonText({ reason: entry.reason }))}</span>{/each}
          </small>
        {/if}
      </span>
    </label>
  {/if}

  <button class="more-toggle" aria-expanded={more} onclick={() => (more = !more)}><Icon name={more ? 'chevU' : 'chev'} />{t('ui_screen_more')}</button>
  {#if more}
    <div class="more-box form-stack">
      {#if info.os}
        <div class="field">
          <span>{t('ui_screen_lock_title')}</span>
          <div class="seg">
            <button aria-pressed={draft.lock === false} onclick={() => (draft.lock = false)}>{info.lockMinutes > 0 ? t('ui_screen_lock_server', info.lockMinutes) : t('ui_screen_lock_server_never')}</button>
            <button aria-pressed={draft.lock !== false} onclick={() => (draft.lock = draft.lock === false ? info.lockMinutes || 5 : draft.lock)}>{t('ui_screen_lock_own')}</button>
          </div>
        </div>
        {#if draft.lock !== false}
          <label class="field">{t('ui_screen_lock_minutes')}<input type="number" min="0" max={info.ranges.lock[1]} bind:value={draft.lock} /><small>{Number(draft.lock) > 0 ? t('ui_screen_lock_on', draft.lock) : t('ui_screen_lock_never')}</small></label>
        {/if}
      {/if}
      <div class="field">
        <span>{t('ui_screen_signal_title')}</span>
        <div class="seg">
          {#each ['kind', 'wired', 'wireless'] as mode (mode)}
            <button aria-pressed={draft.signal === mode} onclick={() => (draft.signal = mode as SignalMode)}>{signalText(mode as SignalMode)}</button>
          {/each}
        </div>
        <small>{t('ui_screen_signal_help')}</small>
      </div>
      <label class="switch-row">
        <span class="switch-text"><b>{t('ui_screen_oos_title')}</b><small>{t('ui_oos_switch_help')}</small></span>
        <input type="checkbox" class="switch" checked={!enabled} onchange={(event) => (enabled = !event.currentTarget.checked)} />
      </label>
      <label class="field">{t('ui_screen_oos_message')}<input type="text" maxlength={info.limits.message} placeholder={t('idle_oos_line')} bind:value={draft.message} /><small>{device.kind === 'terminal' ? t('ui_screen_oos_help_terminal') : t('ui_screen_oos_help')}</small></label>
    </div>
  {/if}

  {#snippet footer()}
    <span class="grow small">{problems[0] ?? (also && preview?.changes.length ? t('ui_picture_footer_many', picture, preview.changes.length + 1, t('kind_plural_' + device.kind).toLowerCase()) : t('ui_picture_footer', shown))}</span>
    <button class="button" onclick={onclose}>{t('ui_cancel')}</button>
    <button class="button primary" disabled={busy || (!dirty && !(also && preview?.changes.length)) || problems.length > 0} onclick={save}><Icon name="check" />{t('ui_save')}</button>
  {/snippet}
</Drawer>

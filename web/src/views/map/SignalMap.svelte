<script lang="ts">
  import Dropdown from '$components/Dropdown.svelte';
  import Icon from '$components/Icon.svelte';
  import MapCanvas, { type MapCircle, type MapDot, type MapLabel, type MapLine, type MapPin } from '$components/MapCanvas.svelte';
  import SaveBar from '$components/SaveBar.svelte';
  import { openDevice } from '$lib/nav.svelte';
  import { call, previewParam } from '$lib/nui';
  import { pickSpot } from '$lib/placement';
  import { namePlaces, placeOf } from '$lib/places.svelte';
  import { reading } from '$lib/signal';
  import { app, ask, clone, deviceName, explain, kindName, list, number, plural, t, toast } from '$lib/state.svelte';
  import type { Antenna, DeviceDetail, DeviceSummary, Kind, SignalView, SignalWhy, Tower } from '$lib/types';

  let { focus = null }: { focus?: number | null } = $props();

  const KINDS: Kind[] = ['laptop', 'pc', 'terminal', 'tablet'];
  const TYPES = ['cell', 'radio', 'base', 'airport', 'roof', 'aerial'];

  let view = $state<SignalView | null>(null);
  let antennas = $state<Antenna[]>([]);
  let kinds = $state<Partial<Record<Kind, boolean>>>({});
  let base = $state('');
  let devices = $state<DeviceSummary[]>([]);
  let selected = $state(previewParam('antenna'));
  let busy = $state(false);
  let picking = $state(false);
  let query = $state('');
  let typeFilter = $state('');
  let model = $state('');
  let why = $state<SignalWhy | null>(null);
  let target = $state<DeviceDetail | null>(null);
  let ready = $state(false);
  let nextKey = 0;
  const keys = new WeakMap<Antenna, string>();

  const keyOf = (antenna: Antenna) => {
    if (antenna.id) return 'a' + antenna.id;

    let key = keys.get(antenna);

    if (!key) keys.set(antenna, (key = 'n' + ++nextKey));

    return key;
  };

  const snapshot = () => JSON.stringify({ antennas, kinds });

  function fromView(data: SignalView) {
    view = data;
    antennas = clone(list<Antenna>(data.antennas));
    kinds = clone(data.kinds);
    base = snapshot();

    if (!model) model = data.masts[0] ?? '';
  }

  async function load() {
    const [signal, listed] = await Promise.all([
      call<SignalView>('evdev:admin:signal'),
      call<{ devices: DeviceSummary[] }>('evdev:admin:list', { state: 'placed', limit: 1000 }),
    ]);

    if (!signal.ok) {
      explain(signal);

      return;
    }

    fromView(signal.data!);

    if (listed.ok) {
      devices = list<DeviceSummary>(listed.data!.devices).filter((device) => device.position);
    }

    namePlaces([...view!.towers, ...antennas]);

    if (focus) {
      const [answer, detail] = await Promise.all([call<SignalWhy>('evdev:admin:signal:why', focus), call<{ device: DeviceDetail }>('evdev:admin:device', focus)]);

      why = answer.ok ? answer.data! : null;
      target = detail.ok ? detail.data!.device : null;

      if (why?.position) namePlaces([why.position]);
    }

    ready = true;
  }

  load();

  const dirty = $derived(!!view && snapshot() !== base);

  $effect(() => {
    app.dirty = dirty;
  });

  $effect(() => () => (app.dirty = false));

  const towersById = $derived(new Map((view?.towers ?? []).map((tower) => [tower.id, tower])));
  const used = $derived(new Set(antennas.filter((antenna) => antenna.source === 'tower').map((antenna) => antenna.tower)));
  const current = $derived(antennas.find((antenna) => keyOf(antenna) === selected) ?? null);
  const currentTower = $derived(selected.startsWith('t:') ? (towersById.get(selected.slice(2)) ?? null) : null);
  const thresholds = $derived(view?.bars ?? [5, 25, 50, 75]);
  const wireless = (kind: Kind) => kinds[kind] === true;

  function nameOf(antenna: Antenna) {
    if (antenna.label) return antenna.label;

    if (antenna.source === 'tower') {
      const tower = towersById.get(antenna.tower ?? '');

      return t('ui_signal_tower_named', t('ui_signal_type_' + (tower?.type ?? 'cell')), placeOf(antenna) || antenna.tower || '');
    }

    return t('ui_signal_mast_named', placeOf(antenna) || '#' + (antenna.id ?? ''));
  }

  const towerText = (tower: Tower) => t('ui_signal_tower_named', t('ui_signal_type_' + tower.type), placeOf(tower) || tower.id);

  const MASTS: Record<string, string> = {
    prop_mobile_mast_1: 'ui_signal_model_cell',
    prop_radiomast01: 'ui_signal_model_lattice',
    prop_radiomast02: 'ui_signal_model_roof',
    prop_air_mast_02: 'ui_signal_model_airport',
  };

  const mastName = (name: string | undefined) => (name && MASTS[name] ? t(MASTS[name]) : (name ?? ''));

  const circles = $derived<MapCircle[]>(antennas.map((antenna) => ({
    key: keyOf(antenna),
    x: antenna.x,
    y: antenna.y,
    radius: antenna.radius,
    label: nameOf(antenna),
    tone: keyOf(antenna) === selected ? 'sel' : antenna.on ? '' : 'off',
  })));

  const freeTowers = $derived((view?.towers ?? []).filter((tower) => !used.has(tower.id) && (!typeFilter || tower.type === typeFilter)));

  const dots = $derived<MapDot[]>(picking || selected.startsWith('t:')
    ? freeTowers.map((tower) => ({ key: 't:' + tower.id, x: tower.x, y: tower.y, label: towerText(tower) }))
    : []);

  const covered = $derived(devices.filter((device) => wireless(device.kind)).map((device) => ({
    device,
    bars: view?.enabled !== false ? reading(antennas, device.position!, device.space, thresholds, view?.homeLoss ?? 1).bars : 4,
  })));

  const dark = $derived(covered.filter((entry) => entry.bars === 0));

  const spot = $derived(why?.position ?? null);

  const focusBars = $derived(spot && target && view ? reading(antennas, spot, why?.space ?? 'b0', thresholds, view.homeLoss ?? 1).bars : null);
  const focusWireless = $derived(!!target && (target.screen?.signal === 'wired' ? false : target.screen?.signal === 'wireless' ? true : wireless(target.kind)));

  const pins = $derived<MapPin[]>([
    ...covered.filter((entry) => entry.device.id !== focus).map(({ device, bars }) => ({
      id: device.id,
      x: device.position!.x,
      y: device.position!.y,
      kind: device.kind,
      label: t('ui_signal_pin', deviceName(device), bars),
      tone: (bars === 0 ? 'warn' : '') as MapPin['tone'],
    })),
    ...(spot && target
      ? [{
        id: target.id,
        x: spot.x,
        y: spot.y,
        kind: target.kind,
        label: deviceName(target),
        tone: (focusBars === 0 && focusWireless ? 'warn' : 'use') as MapPin['tone'],
      }]
      : []),
  ]);

  const nearest = $derived.by(() => {
    if (!why?.nearest) return null;

    return antennas.find((antenna) => antenna.id === why!.nearest!.id) ?? null;
  });

  const nearestDistance = $derived(nearest && spot ? Math.round(Math.hypot(nearest.x - spot.x, nearest.y - spot.y)) : 0);

  const reach = $derived.by(() => {
    if (!nearest || !nearestDistance) return null;

    const first = thresholds[0] ?? 5;

    if (nearest.strength <= first) return null;

    const radius = Math.ceil(nearestDistance / Math.sqrt(1 - first / nearest.strength) / 10 + 1) * 10;

    return radius <= 6000 ? radius : null;
  });

  const lines = $derived<MapLine[]>(spot && nearest ? [{ key: 'why', from: spot, to: { x: nearest.x, y: nearest.y } }] : []);

  const labels = $derived<MapLabel[]>(spot && nearest && target
    ? [
      { key: 'mid', x: (spot.x + nearest.x) / 2, y: (spot.y + nearest.y) / 2, text: t('ui_signal_line', nearestDistance, Math.round(nearest.radius)), tone: 'warn' },
      { key: 'device', x: spot.x, y: spot.y, text: t('ui_signal_pin', deviceName(target), focusBars ?? 0) },
    ]
    : []);

  const start = $derived(spot && nearest
    ? { x: (spot.x + nearest.x) / 2, y: (spot.y + nearest.y) / 2, width: Math.min(60000, (640 * 9000) / Math.max(600, nearestDistance * 2.2)) }
    : current
      ? { x: current.x, y: current.y, width: (640 * 9000) / Math.max(600, current.radius * 2.6) }
      : view?.here ? { x: view.here.x, y: view.here.y, width: 1500 } : { x: -250, y: -900, width: 1300 });

  let canvas = $state<MapCanvas | null>(null);
  let frameWidth = $state(640);

  function focusOn(at: { x: number; y: number; radius?: number }) {
    canvas?.centre(at, (frameWidth * 9000) / Math.max(600, (at.radius ?? 400) * 2.6));
  }

  function pick(key: string, move = false) {
    selected = key;
    picking = false;

    if (!move) return;

    const antenna = antennas.find((entry) => keyOf(entry) === key);
    const tower = key.startsWith('t:') ? towersById.get(key.slice(2)) : null;

    if (antenna) focusOn(antenna);
    else if (tower) focusOn({ x: tower.x, y: tower.y, radius: tower.radius });
  }

  const towerList = $derived.by(() => {
    const words = query.trim().toLowerCase();
    const here = view?.here;

    return (view?.towers ?? [])
      .filter((tower) => !typeFilter || tower.type === typeFilter)
      .filter((tower) => !words || (tower.id + ' ' + tower.model + ' ' + placeOf(tower) + ' ' + t('ui_signal_type_' + tower.type)).toLowerCase().includes(words))
      .sort((a, b) => (here ? Math.hypot(a.x - here.x, a.y - here.y) - Math.hypot(b.x - here.x, b.y - here.y) : 0))
      .slice(0, 60);
  });

  function full() {
    if (antennas.length < (view?.limit ?? 200)) return false;

    toast(t('ui_signal_limit', view?.limit ?? 200), 'error');

    return true;
  }

  function addTower(tower: Tower) {
    if (used.has(tower.id) || full()) return;

    const antenna: Antenna = {
      source: 'tower',
      tower: tower.id,
      label: '',
      x: tower.x,
      y: tower.y,
      z: tower.z,
      h: 0,
      radius: tower.radius,
      strength: tower.strength,
      on: true,
    };

    antennas = [...antennas, antenna];
    selected = keyOf(antennas[antennas.length - 1]);
    picking = false;
  }

  async function placeMast() {
    if (full()) return;

    const spot = await pickSpot({
      kind: 'antenna',
      model,
      radius: view?.defaults.radius ?? 800,
      slots: {
        title: t('ui_slots_antennas'),
        plural: t('ui_slots_antennas'),
        items: [
          ...antennas.map((antenna) => ({ label: nameOf(antenna), state: 'done' as const })),
          { label: t('ui_placement_mast_title'), state: 'active' as const },
        ],
        placed: antennas.length,
        max: view?.limit ?? 200,
      },
    });

    if (!spot.ok) {
      if (spot.reason !== 'cancelled') explain(spot);

      return;
    }

    const { position } = spot.data!;

    const antenna: Antenna = {
      source: 'mast',
      model,
      label: '',
      x: position.x,
      y: position.y,
      z: position.z,
      h: position.h ?? 0,
      radius: view?.defaults.radius ?? 800,
      strength: view?.defaults.strength ?? 100,
      on: true,
    };

    antennas = [...antennas, antenna];
    selected = keyOf(antennas[antennas.length - 1]);
    namePlaces([antenna]);
  }

  async function moveMast(antenna: Antenna) {
    const spot = await pickSpot({
      kind: 'antenna',
      model: antenna.model,
      antennaId: antenna.id,
      radius: antenna.radius,
      slots: { title: t('ui_slots_move_antenna'), items: [{ label: nameOf(antenna), state: 'active' }] },
    });

    if (!spot.ok) {
      if (spot.reason !== 'cancelled') explain(spot);

      return;
    }

    const { position } = spot.data!;

    Object.assign(antenna, { x: position.x, y: position.y, z: position.z, h: position.h ?? 0 });
    namePlaces([antenna]);
  }

  async function remove(antenna: Antenna) {
    if (!(await ask({ title: t('ui_signal_remove_title'), message: t('ui_signal_remove_message', nameOf(antenna)), confirm: t('ui_remove'), danger: true }))) return;

    antennas = antennas.filter((entry) => entry !== antenna);
    selected = '';
  }

  function stretch() {
    if (!nearest || !reach) return;

    nearest.radius = reach;
    nearest.on = true;
    selected = keyOf(nearest);
  }

  function noSignalNeeded() {
    if (!target) return;

    kinds = { ...kinds, [target.kind]: false };
  }

  const problems = $derived.by(() => {
    const found: string[] = [];

    antennas.forEach((antenna, index) => {
      if (!(antenna.radius >= 50 && antenna.radius <= 6000)) found.push(t('ui_signal_bad_radius', index + 1));
      if (!(antenna.strength >= 10 && antenna.strength <= 100 && Number.isInteger(Number(antenna.strength)))) found.push(t('ui_signal_bad_strength', index + 1));
      if (antenna.label.length > 40) found.push(t('ui_signal_bad_label', index + 1));
    });

    return found;
  });

  async function save() {
    if (!view) return;

    busy = true;

    const payload = { antennas: antennas.map((antenna) => ({ ...antenna, radius: Number(antenna.radius), strength: Number(antenna.strength) })), kinds };
    const result = await call<SignalView>('evdev:admin:signal:save', payload, view.rev);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'signal_changed') {
        app.dirty = false;
        load();
      }

      return;
    }

    const keep = current ? { x: current.x, y: current.y } : null;

    fromView(result.data!);

    const again = keep ? antennas.find((antenna) => antenna.x === keep.x && antenna.y === keep.y) : null;

    selected = again ? keyOf(again) : '';
    toast(t('ui_saved'), 'success');
  }

  function discard() {
    if (!view) return;

    fromView(view);
    selected = '';
  }

  const area = $derived(spot ? placeOf(spot) : '');
</script>

<div class="map-page signal-page">
  <div class="map-main">
    {#if !view || !ready}
      <p class="empty">{t('ui_loading')}</p>
    {:else}
      <div class="signal-map" class:picking={picking || selected.startsWith('t:')} bind:clientWidth={frameWidth}>
        <MapCanvas bind:this={canvas} {pins} {circles} {dots} {lines} {labels} {start} selected={focus} onselect={(id) => id !== focus && openDevice(id)} onpick={(key) => pick(key)} />
      </div>
    {/if}
  </div>
  <aside class="map-side">
    {#if view}
      {#if !view.enabled}<p class="notice warn small">{t('ui_signal_disabled')}</p>{/if}

      {#if focus && target}
        <div>
          <h2 class="side-heading">{t('ui_signal_why_title', deviceName(target))}</h2>
          {#if !focusWireless}
            <p class="muted small">{t('ui_signal_why_wired', kindName(target.kind))}</p>
          {:else if !spot}
            <p class="muted small">{t('ui_signal_why_pocket')}</p>
          {:else if focusBars && focusBars > 0}
            <p class="muted small">{t('ui_signal_why_fixed', focusBars)}</p>
          {:else if nearest}
            <p class="muted small">{why?.holder ? t('ui_signal_why_held', t('kind_plural_' + target.kind), why.holder.name, area || '-', nameOf(nearest), nearestDistance, Math.round(nearest.radius)) : t('ui_signal_why_placed', t('kind_plural_' + target.kind), area || '-', nameOf(nearest), nearestDistance, Math.round(nearest.radius))}</p>
          {:else}
            <p class="muted small">{t('ui_signal_why_none', area || '-')}</p>
          {/if}
        </div>
        {#if focusWireless && spot}
          <div class="stack tight">
            <span class="side-title">{t('ui_signal_pick_fix')}</span>
            <button class="button primary start" disabled={app.placing} onclick={placeMast}><Icon name="signal" />{area ? t('ui_signal_fix_mast', area) : t('ui_signal_fix_mast_here')}</button>
            {#if nearest && reach}<button class="button start" onclick={stretch}><Icon name="target" />{t('ui_signal_fix_reach', nameOf(nearest), reach)}</button>{/if}
            <button class="button start" onclick={noSignalNeeded}><Icon name={target.kind === 'tablet' ? 'tablet' : 'laptop'} />{t('ui_signal_fix_kind', t('kind_plural_' + target.kind))}</button>
          </div>
          <p class="small dim">{t('ui_signal_why_note')}</p>
        {/if}
        <button class="link start" onclick={() => openDevice(target!.id)}>{t('ui_back_to', deviceName(target))}</button>
      {:else}
        <div class="signal-actions">
          <Dropdown class="input" label={t('ui_signal_mast_model')} bind:value={model} options={view.masts.map((entry) => ({ value: entry, label: mastName(entry) }))} />
          <button class="button small primary" disabled={busy || app.placing} onclick={placeMast}><Icon name="place" />{t('ui_signal_place_mast')}</button>
          <button class="button small" aria-pressed={picking} onclick={() => ((picking = !picking), (selected = ''))}><Icon name="signal" />{t('ui_signal_use_tower')}</button>
        </div>
      {/if}

      {#if current}
        {@const tower = current.source === 'tower' ? towersById.get(current.tower ?? '') : null}
        <div class="card map-card signal-card">
          <div class="map-card-head">
            <span class={'kind-tile' + (current.on ? ' live' : '')}><Icon name="signal" /></span>
            <div class="grow"><b>{nameOf(current)}</b><small class="mono">{current.source === 'tower' ? (tower?.model ?? current.tower) : mastName(current.model)}</small></div>
          </div>
          <label class="field">{t('ui_signal_label')}<input class="input" maxlength="40" placeholder={nameOf({ ...current, label: '' })} bind:value={current.label} /></label>
          <div class="grid two">
            <label class="field">{t('ui_signal_radius')}<input class="input mono" type="number" min="50" max="6000" step="10" bind:value={current.radius} /></label>
            <label class="field">{t('ui_signal_strength')}<input class="input mono" type="number" min="10" max="100" step="1" bind:value={current.strength} /></label>
          </div>
          <label class="switch-row"><span>{t('ui_signal_on')}</span><input type="checkbox" class="switch" bind:checked={current.on} /></label>
          <div class="card-actions">
            {#if current.source === 'mast'}<button class="button small" disabled={app.placing || !current.id} title={current.id ? '' : t('ui_signal_save_first')} onclick={() => moveMast(current)}><Icon name="move" />{t('ui_signal_move')}</button>{/if}
            <button class="button small" onclick={() => remove(current)}><Icon name="trash" />{t('ui_remove')}</button>
            <button class="button small ghost" onclick={() => (selected = '')}>{t('ui_close')}</button>
          </div>
        </div>
      {:else if currentTower}
        <div class="card map-card signal-card">
          <div class="map-card-head">
            <span class="kind-tile"><Icon name="signal" /></span>
            <div class="grow"><b>{towerText(currentTower)}</b><small class="mono">{currentTower.model}</small></div>
          </div>
          <div class="tags">
            <span class="tag">{t('ui_signal_type_' + currentTower.type)}</span>
            <span class="tag mono">{t('ui_signal_height', number(currentTower.height, 0))}</span>
            <span class="tag mono">{t('ui_signal_reach', number(currentTower.radius, 0), currentTower.strength)}</span>
          </div>
          <div class="card-actions"><button class="button small primary" onclick={() => addTower(currentTower)}><Icon name="plus" />{t('ui_signal_add_tower')}</button></div>
        </div>
      {:else if picking}
        <div class="card map-card signal-card">
          <p class="small muted">{t('ui_signal_towers_hint')}</p>
          <input class="input" placeholder={t('ui_signal_search_towers')} bind:value={query} />
          <div class="chips">
            <button class="pick-chip" aria-pressed={typeFilter === ''} onclick={() => (typeFilter = '')}>{t('ui_filter_all_kinds')}</button>
            {#each TYPES as type (type)}<button class="pick-chip" aria-pressed={typeFilter === type} onclick={() => (typeFilter = type)}>{t('ui_signal_type_' + type)}</button>{/each}
          </div>
          <div class="tower-list">
            {#each towerList as tower (tower.id)}
              <button class="tower-row" disabled={used.has(tower.id)} onclick={() => (addTower(tower), focusOn(tower))}>
                <span class="grow"><b>{towerText(tower)}</b><small class="mono">{tower.model}</small></span>
                {#if used.has(tower.id)}<span class="tag ok">{t('ui_signal_tower_used')}</span>{:else}<Icon name="plus" />{/if}
              </button>
            {/each}
          </div>
        </div>
      {/if}

      {#if !focus}
        <div>
          <span class="side-title">{t('ui_signal_antennas_on', antennas.filter((antenna) => antenna.on).length, antennas.length)}</span>
          {#if dark.length}<p class="small warn-text">{plural('ui_signal_dark', dark.length)}</p>{/if}
          <div class="signal-list">
            {#each antennas as antenna (keyOf(antenna))}
              <div class={'listrow signal-row' + (keyOf(antenna) === selected ? ' on' : '')}>
                <button class="grow plain-button" onclick={() => pick(keyOf(antenna), true)}><b>{nameOf(antenna)}</b><small>{antenna.source === 'mast' ? t('ui_signal_your_mast') : t('ui_signal_source_tower')}, {t('ui_signal_reaches', number(antenna.radius, 0))}</small></button>
                <input type="checkbox" class="switch" aria-label={t('ui_signal_on')} bind:checked={antenna.on} />
              </div>
            {:else}
              <div class="empty-state"><Icon name="signal" /><b>{t('ui_signal_empty_title')}</b><p>{t('ui_signal_empty_text')}</p></div>
            {/each}
          </div>
        </div>
      {/if}

      <div class="summary">
        <b class="medium">{t('ui_signal_kinds')}</b>
        <p class="dim small">{t('ui_signal_kinds_short')}</p>
        {#each KINDS as kind (kind)}
          <label class="listrow"><span class="grow">{t('kind_plural_' + kind)}</span><span class={'tag' + (wireless(kind) ? '' : ' ok')}>{wireless(kind) ? t('ui_signal_wireless') : t('ui_signal_wired')}</span><input type="checkbox" class="switch" aria-label={kindName(kind)} checked={wireless(kind)} onchange={(event) => (kinds = { ...kinds, [kind]: event.currentTarget.checked })} /></label>
        {/each}
      </div>
      <div class="map-legend">
        <span><i class="legend-signal"></i>{t('ui_signal_legend_reach')}</span>
        <span><i class="legend-dot warn"></i>{t('ui_signal_legend_dark')}</span>
        <span class="small">{t('ui_signal_legend_bars', thresholds[3] ?? 75, thresholds[0] ?? 5)}</span>
      </div>
    {/if}
  </aside>
</div>
{#if view}
  <SaveBar {dirty} {busy} {problems} onsave={save} ondiscard={discard} />
{/if}

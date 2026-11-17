<script lang="ts">
  import { untrack } from 'svelte';
  import Dropdown from '$components/Dropdown.svelte';
  import Icon from '$components/Icon.svelte';
  import MapCanvas, { type MapLabel, type MapPin } from '$components/MapCanvas.svelte';
  import { normalizeSummary, ownerLine, placeText, whoShort } from '$lib/devices';
  import { openDevice } from '$lib/nav.svelte';
  import { call, currentToken, post, previewParam } from '$lib/nui';
  import { namePlaces } from '$lib/places.svelte';
  import { KIND_ICONS, app, deviceName, explain, kindName, list, plural, reasonText, spaceText, t, toast } from '$lib/state.svelte';
  import type { Counts, DeviceSummary, Kind } from '$lib/types';

  let { focus = null }: { focus?: number | null } = $props();

  let devices = $state<DeviceSummary[] | null>(null);
  let kind = $state<Kind | ''>('');
  let space = $state('b0');
  let selected = $state<number | null>(untrack(() => focus) ?? (Number(previewParam('pin')) || null));

  async function load() {
    const result = await call<{ devices: DeviceSummary[]; counts: Counts }>('evdev:admin:list', { state: 'placed', limit: 1000 });

    if (!result.ok) {
      explain(result);
      devices = [];

      return;
    }

    devices = list<DeviceSummary>(result.data!.devices).filter((device) => device.position).map(normalizeSummary);
    app.counts = result.data!.counts;
    namePlaces(devices.filter((device) => device.space === 'b0').map((device) => device.position!));
  }

  load();

  const spaces = $derived([...new Set(['b0', ...(devices ?? []).map((device) => device.space)])]);
  const shown = $derived((devices ?? []).filter((device) => (!kind || device.kind === kind) && (!space || device.space === space)));
  const current = $derived(shown.find((device) => device.id === selected) ?? null);

  const pins = $derived<MapPin[]>(shown.map((device) => ({
    id: device.id,
    x: device.position!.x,
    y: device.position!.y,
    kind: device.kind,
    label: deviceName(device),
    tone: device.attention.length ? 'warn' : !device.enabled ? 'off' : device.inUse ? 'use' : '',
  })));

  const labels = $derived<MapLabel[]>(current ? [{ key: 'sel', x: current.position!.x, y: current.position!.y, text: deviceName(current) }] : []);
  const start = $derived(focus && current ? { x: current.position!.x, y: current.position!.y, width: 9000 } : null);
  const KINDS: Kind[] = ['laptop', 'pc', 'terminal'];

  async function waypoint(device: DeviceSummary) {
    const answer = await post<{ ok: boolean; reason?: string }>('waypoint', { x: device.position!.x, y: device.position!.y, __t: currentToken() }).catch(() => ({ ok: false, reason: 'no_response' }));

    if (answer.ok) toast(t('ui_waypoint_set'), 'success');
    else toast(reasonText(answer), 'error');
  }
</script>

<div class="map-page">
  <div class="map-main">
    {#if devices === null}
      <p class="empty">{t('ui_loading')}</p>
    {:else}
      <MapCanvas {pins} {labels} {selected} {start} onselect={(id) => (selected = id)} />
    {/if}
  </div>
  <aside class="map-side">
    <div class="chips">
      <button class="pick-chip" aria-pressed={kind === ''} onclick={() => (kind = '')}>{t('ui_filter_all_kinds')}</button>
      {#each KINDS as entry (entry)}<button class="pick-chip" aria-pressed={kind === entry} onclick={() => (kind = entry)}>{t('kind_plural_' + entry)}</button>{/each}
    </div>
    <Dropdown
      class="input"
      label={t('ui_filter_space')}
      bind:value={space}
      options={[{ value: '', label: t('ui_filter_space_any') }, ...spaces.map((entry) => ({ value: entry, label: spaceText(entry) }))]}
    />
    <p class="small muted">{plural('ui_map_count', shown.length)}</p>
    {#if current}
      <div class="card map-card">
        <div class="map-card-head">
          <span class={'kind-tile' + (current.inUse ? ' live' : '')}><Icon name={KIND_ICONS[current.kind]} /></span>
          <div class="grow"><b>{deviceName(current)}</b><small>{kindName(current.kind)}, {placeText(current)}</small></div>
        </div>
        <dl class="facts compact">
          <dt>{t('ui_col_who')}</dt><dd>{whoShort(current.access)}</dd>
          <dt>{t('ui_field_owner')}</dt><dd>{ownerLine(current)}</dd>
        </dl>
        {#each current.attention as code (code)}<p class="small warn-text">{t('attention_' + code)}</p>{/each}
        {#if current.inUse}<p class="small accent-text">{t('ui_in_use_by_short', current.inUse.name)}</p>{/if}
        <div class="card-actions">
          <button class="button small primary" onclick={() => openDevice(current.id)}><Icon name="chevR" />{t('ui_open')}</button>
          <button class="button small" onclick={() => waypoint(current)}><Icon name="flag" />{t('ui_waypoint')}</button>
        </div>
      </div>
    {:else}
      <p class="small muted">{t('ui_map_hint')}</p>
    {/if}
    <div class="map-legend">
      <span><i class="legend-dot"></i>{t('ui_map_legend_idle')}</span>
      <span><i class="legend-dot use"></i>{t('ui_map_legend_use')}</span>
      <span><i class="legend-dot warn"></i>{t('ui_map_legend_warn')}</span>
      <span><i class="legend-dot off"></i>{t('ui_map_legend_off')}</span>
      <span class="small dim">{t('ui_map_tablets_note')}</span>
    </div>
  </aside>
</div>

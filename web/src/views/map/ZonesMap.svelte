<script lang="ts">
  import MapCanvas, { type MapLabel, type MapZone } from '$components/MapCanvas.svelte';
  import SaveBar from '$components/SaveBar.svelte';
  import ZoneList from '$components/ZoneList.svelte';
  import { call } from '$lib/nui';
  import { app, clone, explain, list, same, t, toast } from '$lib/state.svelte';
  import type { SettingsView, Zone } from '$lib/types';

  let view = $state<SettingsView | null>(null);
  let zones = $state<Zone[]>([]);
  let base = $state<Zone[]>([]);
  let busy = $state(false);

  async function load() {
    const result = await call<SettingsView>('evdev:admin:settings');

    if (!result.ok) {
      explain(result);

      return;
    }

    view = result.data!;
    base = list<Zone>(view.settings.zones).map((zone) => ({ ...zone }));
    zones = clone(base);
  }

  load();

  const dirty = $derived(!!view && !same(zones, base));

  $effect(() => {
    app.dirty = dirty;
  });

  $effect(() => () => (app.dirty = false));

  const world = $derived(zones.filter((zone) => zone.space === 'b0'));
  const mapZones = $derived<MapZone[]>(world.map((zone, index) => ({ id: zone.id ?? -index - 1, x: zone.x, y: zone.y, radius: zone.radius, label: zone.label })));
  const labels = $derived<MapLabel[]>(world.map((zone, index) => ({
    key: 'z' + (zone.id ?? 'n' + index),
    x: zone.x,
    y: zone.y,
    text: t('ui_zone_label_radius', zone.label || '#' + (index + 1), Math.round(zone.radius)),
  })));

  const start = $derived(world.length
    ? { x: world.reduce((sum, zone) => sum + zone.x, 0) / world.length, y: world.reduce((sum, zone) => sum + zone.y, 0) / world.length, width: 9000 }
    : null);

  function zoneOk(zone: Zone) {
    if (zone.label.trim().length > (app.boot?.limits.label ?? 40)) return false;
    if (![zone.x, zone.y, zone.z].every(Number.isFinite)) return false;

    return zone.radius >= 2 && zone.radius <= 200 && /^[bp]\d+$/.test(zone.space);
  }

  const problems = $derived(zones.flatMap((zone, index) => (zoneOk(zone) ? [] : [t('ui_zone_bad', index + 1)])));

  async function save() {
    if (!view) return;

    busy = true;

    const payload = zones.map((zone) => ({
      ...(zone.id ? { id: zone.id } : {}),
      label: zone.label.trim(),
      x: Number(zone.x),
      y: Number(zone.y),
      z: Number(zone.z),
      radius: Number(zone.radius),
      space: zone.space,
    }));

    const result = await call<SettingsView>('evdev:admin:zones:save', payload, view.rev);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'settings_changed') {
        app.dirty = false;
        load();
      }

      return;
    }

    view = result.data!;
    base = list<Zone>(view.settings.zones).map((zone) => ({ ...zone }));
    zones = clone(base);
    app.dirty = false;
    toast(t('ui_saved'), 'success');
  }
</script>

<div class="map-page zones-page">
  <div class="map-main">
    {#if !view}
      <p class="empty">{t('ui_loading')}</p>
    {:else}
      <MapCanvas pins={[]} zones={mapZones} {labels} {start} selected={null} onselect={() => null} />
    {/if}
  </div>
  <aside class="map-side">
    <div>
      <span class="side-title">{t('ui_zones_title')}</span>
      <p class="small muted">{t('ui_zones_help')}</p>
    </div>
    {#if view}<ZoneList bind:zones />{/if}
    <p class="small dim">{t('ui_zones_camera_help')}</p>
  </aside>
</div>
{#if view}
  <SaveBar {dirty} {busy} {problems} onsave={save} ondiscard={() => (zones = clone(base))} />
{/if}

<script lang="ts">
  import Dropdown from './Dropdown.svelte';
  import Icon from './Icon.svelte';
  import { pickSpot } from '$lib/placement';
  import { app, explain, t } from '$lib/state.svelte';
  import type { Zone } from '$lib/types';

  let { zones = $bindable(), disabled = false }: { zones: Zone[]; disabled?: boolean } = $props();

  const max = $derived(app.boot?.limits.zones ?? 100);
  const maxLabel = $derived(app.boot?.limits.label ?? 40);

  function whereOf(space: string): 'world' | 'bucket' | 'home' {
    const match = /^([bp])(\d+)$/.exec(space);

    if (match?.[1] === 'p') {
      return 'home';
    }

    return match && Number(match[2]) > 0 ? 'bucket' : 'world';
  }

  function numberOf(space: string) {
    return Number(/^[bp](\d+)$/.exec(space)?.[1] ?? 0);
  }

  function setWhere(zone: Zone, where: string) {
    const number = Math.max(1, numberOf(zone.space));

    zone.space = where === 'world' ? 'b0' : (where === 'home' ? 'p' : 'b') + number;
  }

  function setNumber(zone: Zone, value: string) {
    const number = Math.max(0, Math.floor(Number(value) || 0));

    zone.space = (whereOf(zone.space) === 'home' ? 'p' : 'b') + number;
  }

  function numeric(zone: Zone, key: 'x' | 'y' | 'z' | 'radius', value: string) {
    const parsed = Number(value);

    zone[key] = Number.isFinite(parsed) ? parsed : 0;
  }

  async function addWithCamera() {
    const spot = await pickSpot({
      kind: 'zone',
      radius: 15,
      slots: {
        title: t('ui_slots_zones'),
        plural: t('ui_slots_zones_plural'),
        items: [
          ...zones.map((zone, index) => ({ label: zone.label || t('ui_zone_new', index + 1), state: 'done' as const })),
          { label: t('ui_zone_new', zones.length + 1), state: 'active' as const },
        ],
        placed: zones.length,
        max,
      },
    });

    if (!spot.ok) {
      if (spot.reason !== 'cancelled') {
        explain(spot);
      }

      return;
    }

    const { position, radius, space } = spot.data!;

    zones = [
      ...zones,
      {
        label: t('ui_zone_new', zones.length + 1),
        x: position.x,
        y: position.y,
        z: position.z,
        radius: radius ?? 15,
        space: space ?? 'b0',
      },
    ];
  }

  function addTyped() {
    zones = [...zones, { label: t('ui_zone_new', zones.length + 1), x: 0, y: 0, z: 0, radius: 15, space: 'b0' }];
  }
</script>

<div class="zone-list">
  {#each zones as zone, index (zone.id ?? 'new' + index)}
    {@const where = whereOf(zone.space)}
    <div class="zone-row">
      <div class={'zone-line' + (where === 'world' ? ' world' : '')}>
        <input class="input" aria-label={t('ui_zone_label')} placeholder={t('ui_zone_label')} maxlength={maxLabel} {disabled} bind:value={zone.label} />
        <Dropdown
          class="input"
          label={t('ui_zone_where')}
          {disabled}
          value={where}
          options={[
            { value: 'world', label: t('space_world') },
            { value: 'bucket', label: t('ui_zone_bucket') },
            { value: 'home', label: t('ui_zone_home') },
          ]}
          onchange={(value) => setWhere(zone, value)}
        />
        {#if where !== 'world'}<input class="input mono" type="number" min="1" aria-label={t('ui_zone_number')} {disabled} value={numberOf(zone.space)} oninput={(event) => setNumber(zone, event.currentTarget.value)} />{/if}
        <button class="icon-button" aria-label={t('ui_remove')} {disabled} onclick={() => (zones = zones.filter((_, position) => position !== index))}><Icon name="x" /></button>
      </div>
      <div class="zone-coords">
        <label class="zone-field">X<input class="input mono" type="number" step="0.1" {disabled} value={zone.x} oninput={(event) => numeric(zone, 'x', event.currentTarget.value)} /></label>
        <label class="zone-field">Y<input class="input mono" type="number" step="0.1" {disabled} value={zone.y} oninput={(event) => numeric(zone, 'y', event.currentTarget.value)} /></label>
        <label class="zone-field">Z<input class="input mono" type="number" step="0.1" {disabled} value={zone.z} oninput={(event) => numeric(zone, 'z', event.currentTarget.value)} /></label>
        <label class="zone-field">{t('ui_zone_radius')}<input class="input mono" type="number" min="2" max="200" {disabled} value={zone.radius} oninput={(event) => numeric(zone, 'radius', event.currentTarget.value)} /></label>
      </div>
    </div>
  {:else}
    <div class="empty-state"><Icon name="target" /><b>{t('ui_zones_empty_title')}</b><p>{t('ui_zones_empty_text')}</p></div>
  {/each}
  <div class="card-actions">
    <button class="button small primary" disabled={disabled || zones.length >= max} onclick={addWithCamera}><Icon name="place" />{t('ui_zone_add_camera')}</button>
    <button class="button small" disabled={disabled || zones.length >= max} onclick={addTyped}><Icon name="plus" />{t('ui_zone_add_typed')}</button>
    <small class="muted zone-count">{t('ui_zone_count', zones.length, max)}</small>
  </div>
</div>

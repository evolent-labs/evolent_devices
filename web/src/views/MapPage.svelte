<script lang="ts">
  import PageHead from '$components/PageHead.svelte';
  import { go, nav, type MapMode } from '$lib/nav.svelte';
  import { app, t } from '$lib/state.svelte';
  import DevicesMap from './map/DevicesMap.svelte';
  import SignalMap from './map/SignalMap.svelte';
  import ZonesMap from './map/ZonesMap.svelte';

  const admin = $derived(app.level === 'admin');
  const mode = $derived<MapMode>(admin ? nav.mapMode : 'devices');

  const MODES: { key: MapMode; label: string; hint: string }[] = [
    { key: 'devices', label: 'ui_map_devices', hint: 'ui_map_devices_hint' },
    { key: 'signal', label: 'ui_map_signal_mode', hint: 'ui_map_signal_hint' },
    { key: 'zones', label: 'ui_zones_title', hint: 'ui_map_zones_hint' },
  ];

  const hint = $derived(t(MODES.find((entry) => entry.key === mode)?.hint ?? 'ui_map_devices_hint'));
</script>

<PageHead title={t('ui_nav_map_signal')} />
{#if admin}
  <div class="tabs">
    <div class="tab-group" role="tablist">
      {#each MODES as entry (entry.key)}
        <button role="tab" aria-selected={mode === entry.key} onclick={() => go({ page: 'map', mapMode: entry.key, mapFocus: null })}>{t(entry.label)}</button>
      {/each}
    </div>
    <span class="tabs-side muted small">{hint}</span>
  </div>
{:else}
  <div class="mode-bar"><span class="muted small">{hint}</span></div>
{/if}
{#if mode === 'signal'}
  <SignalMap focus={nav.mapFocus} />
{:else if mode === 'zones'}
  <ZonesMap />
{:else}
  <DevicesMap focus={nav.mapFocus} />
{/if}
